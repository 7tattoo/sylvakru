package com.kugou.android.auto

import android.os.Bundle
import androidx.media.MediaMetadataCompat
import androidx.media.session.MediaControllerCompat
import androidx.media.session.MediaSessionCompat
import android.util.Log

/**
 * vivo 车联歌词双通道管理器。
 *
 * 当 Dart 端通过 super_lyric MethodChannel 推送歌词行时，
 * 本类同时完成两路注入：
 *
 * Channel A — ucar.media.metadata.* 注入 MediaSession 元数据
 *   车载 Launcher（com.vivo.carlauncher）直接读取，链路最短。
 *
 * Channel B — music.media.extras.* 写入 session extras
 *   手机端"智慧车联"App（com.vivo.ucar）读取后转发给车机。
 *
 * 关键设计：使用 MediaMetadataCompat.Builder(source) 复制现有元数据后追加歌词键，
 * 避免覆盖 AudioService 库设置的标题/艺术家/封面等基础字段。
 */
class CarLyricsManager {

    companion object {
        private const val TAG = "CarLyricsManager"
        private const val AUDIO_SERVICE_CLASS = "com.ryanheise.audioservice.AudioService"
        private const val MEDIA_SESSION_FIELD = "mediaSession"
    }

    private var currentLine: String? = null
    private var wholeLrc: String? = null
    private var status: Long = CarLyricsConstants.LYRICS_STATUS_NO_LYRICS
    @Volatile private var lastPushedLine: String? = null

    /**
     * 从 Dart 端收到歌词行时调用。
     * @param line 当前歌词行文本（空或 null 表示无歌词）
     * @param wholeLrc 完整 LRC 文本（可空）
     */
    fun updateLyricLine(line: String?, wholeLrc: String?) {
        currentLine = line?.takeIf { it.isNotBlank() }
        this.wholeLrc = wholeLrc
        status = if (currentLine.isNullOrEmpty()) {
            CarLyricsConstants.LYRICS_STATUS_NO_LYRICS
        } else {
            CarLyricsConstants.LYRICS_STATUS_SUCCESS
        }
        pushToMediaSession()
    }

    /**
     * 通知车载端歌词正在加载。
     */
    fun setLoading() {
        status = CarLyricsConstants.LYRICS_STATUS_LOADING
        pushToMediaSession()
    }

    /**
     * 清除歌词（停止推送）。
     */
    fun clear() {
        currentLine = null
        wholeLrc = null
        status = CarLyricsConstants.LYRICS_STATUS_NO_LYRICS
        pushToMediaSession()
    }

    /**
     * 执行双通道注入。
     * 通过反射获取 AudioService 的静态 MediaSessionCompat，
     * 在其现有元数据基础上追加 ucar.media.metadata.* 键，
     * 并设置 music.media.extras.* 到 session extras。
     */
    private fun pushToMediaSession() {
        val session = getMediaSession() ?: return
        val lineToPush = currentLine

        // 仅当歌词行真正变化时才更新元数据，避免无谓的广播
        if (lineToPush == lastPushedLine && status != CarLyricsConstants.LYRICS_STATUS_LOADING) {
            return
        }
        lastPushedLine = lineToPush

        try {
            // ---- Channel A: 注入 ucar.media.metadata.* 到元数据 ----
            val currentMetadata = session.controller?.metadata
            val builder = if (currentMetadata != null) {
                MediaMetadataCompat.Builder(currentMetadata)
            } else {
                MediaMetadataCompat.Builder()
            }

            if (!lineToPush.isNullOrEmpty()) {
                builder.putString(CarLyricsConstants.METADATA_KEY_LYRICS_LINE, lineToPush)
            }
            builder.putString(CarLyricsConstants.METADATA_KEY_LYRICS_WHOLE, wholeLrc ?: "-1")
            builder.putLong(CarLyricsConstants.METADATA_KEY_LYRICS_STATUS, status)

            session.setMetadata(builder.build())

            // ---- Channel B: 设置 music.media.extras.* 到 session extras ----
            val extras = Bundle()
            extras.putBoolean(CarLyricsConstants.EXTRAS_KEY_LYRIC_ALLOWED, true)
            extras.putBoolean(CarLyricsConstants.EXTRAS_KEY_NOTICE_CAR, true)
            if (!lineToPush.isNullOrEmpty()) {
                extras.putString(CarLyricsConstants.EXTRAS_KEY_LYRIC, lineToPush)
            }
            session.setExtras(extras)

        } catch (e: Exception) {
            Log.w(TAG, "Failed to inject car lyrics metadata", e)
        }
    }

    /**
     * 通过反射获取 AudioService 的静态 MediaSessionCompat 实例。
     * AudioService 类在音乐播放时已创建 session，若未启动则返回 null。
     */
    private fun getMediaSession(): MediaSessionCompat? {
        return try {
            val clazz = Class.forName(AUDIO_SERVICE_CLASS)
            val field = clazz.getDeclaredField(MEDIA_SESSION_FIELD)
            field.isAccessible = true
            val session = field.get(null) as? MediaSessionCompat
            if (session == null) {
                Log.d(TAG, "MediaSession not yet initialized (AudioService not started)")
            }
            session
        } catch (e: ClassNotFoundException) {
            Log.w(TAG, "AudioService class not found", e)
            null
        } catch (e: NoSuchFieldException) {
            Log.w(TAG, "mediaSession field not found in AudioService", e)
            null
        } catch (e: Exception) {
            Log.w(TAG, "Failed to access MediaSession", e)
            null
        }
    }
}
