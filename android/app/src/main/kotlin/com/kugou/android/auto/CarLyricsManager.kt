package com.kugou.android.auto

import android.os.Bundle
import android.util.Log

/**
 * vivo 车联歌词双通道管理器（纯反射实现）。
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
 * 关键设计：通过反射访问 AudioService 的 MediaSessionCompat，
 * 使用 MediaMetadataCompat.Builder(source) 复制现有元数据后追加歌词键，
 * 避免覆盖 AudioService 库设置的标题/艺术家/封面等基础字段。
 * 采用纯反射以避免 androidx.media 依赖在编译期不可用的问题。
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

    fun setLoading() {
        status = CarLyricsConstants.LYRICS_STATUS_LOADING
        pushToMediaSession()
    }

    fun clear() {
        currentLine = null
        wholeLrc = null
        status = CarLyricsConstants.LYRICS_STATUS_NO_LYRICS
        pushToMediaSession()
    }

    /**
     * 执行双通道注入（全部通过反射）。
     */
    private fun pushToMediaSession() {
        val session = getMediaSessionObject() ?: return
        val lineToPush = currentLine

        if (lineToPush == lastPushedLine && status != CarLyricsConstants.LYRICS_STATUS_LOADING) {
            return
        }
        lastPushedLine = lineToPush

        try {
            // ---- Channel A: 注入 ucar.media.metadata.* 到元数据 ----
            val controller = invokeNoArg(session, "getController")
            val currentMetadata = controller?.let { invokeNoArg(it, "getMetadata") }

            val builder = createMetadataBuilder(currentMetadata)

            // putString(String key, String value)
            if (!lineToPush.isNullOrEmpty()) {
                invokeTwoArg(builder, "putString",
                    String::class.java, CarLyricsConstants.METADATA_KEY_LYRICS_LINE,
                    String::class.java, lineToPush)
            }
            invokeTwoArg(builder, "putString",
                String::class.java, CarLyricsConstants.METADATA_KEY_LYRICS_WHOLE,
                String::class.java, wholeLrc ?: "-1")
            // putLong(String key, long value) — javaPrimitiveType 是可空类型，用 !! 断言非空
            invokeTwoArg(builder, "putLong",
                String::class.java, CarLyricsConstants.METADATA_KEY_LYRICS_STATUS,
                Long::class.javaPrimitiveType!!, status)

            val newMetadata = invokeNoArg(builder, "build")
            // setMetadata(MediaMetadataCompat)
            val metadataClass = getMetadataClass()
            if (newMetadata != null && metadataClass != null) {
                invokeOneArg(session, "setMetadata", metadataClass, newMetadata)
            }

            // ---- Channel B: 设置 music.media.extras.* 到 session extras ----
            val extras = Bundle()
            extras.putBoolean(CarLyricsConstants.EXTRAS_KEY_LYRIC_ALLOWED, true)
            extras.putBoolean(CarLyricsConstants.EXTRAS_KEY_NOTICE_CAR, true)
            if (!lineToPush.isNullOrEmpty()) {
                extras.putString(CarLyricsConstants.EXTRAS_KEY_LYRIC, lineToPush)
            }
            invokeOneArg(session, "setExtras", Bundle::class.java, extras)

        } catch (e: Exception) {
            Log.w(TAG, "Failed to inject car lyrics metadata", e)
        }
    }

    // ---- 反射工具方法 ----

    private fun getMediaSessionObject(): Any? {
        return try {
            val clazz = Class.forName(AUDIO_SERVICE_CLASS)
            val field = clazz.getDeclaredField(MEDIA_SESSION_FIELD)
            field.isAccessible = true
            val session = field.get(null)
            if (session == null) {
                Log.d(TAG, "MediaSession not yet initialized (AudioService not started)")
            }
            session
        } catch (e: Exception) {
            Log.w(TAG, "Failed to access MediaSession", e)
            null
        }
    }

    private fun getMetadataClass(): Class<*>? {
        return try {
            Class.forName("android.support.v4.media.MediaMetadataCompat")
        } catch (e: Exception) {
            try {
                Class.forName("androidx.media.MediaMetadataCompat")
            } catch (e2: Exception) {
                Log.w(TAG, "MediaMetadataCompat class not found", e2)
                null
            }
        }
    }

    private fun createMetadataBuilder(source: Any?): Any {
        val builderClass = try {
            Class.forName("android.support.v4.media.MediaMetadataCompat\$Builder")
        } catch (e: Exception) {
            Class.forName("androidx.media.MediaMetadataCompat\$Builder")
        }

        return if (source != null) {
            val metadataClass = getMetadataClass()
            if (metadataClass != null) {
                builderClass.getConstructor(metadataClass).newInstance(source)
            } else {
                builderClass.getDeclaredConstructor().newInstance()
            }
        } else {
            builderClass.getDeclaredConstructor().newInstance()
        }
    }

    private fun invokeNoArg(target: Any, methodName: String): Any? {
        return try {
            val method = target.javaClass.getMethod(methodName)
            method.invoke(target)
        } catch (e: NoSuchMethodException) {
            val method = target.javaClass.declaredMethods.find { it.name == methodName && it.parameterCount == 0 }
            method?.isAccessible = true
            method?.invoke(target)
        }
    }

    private fun invokeOneArg(target: Any, methodName: String, argType: Class<*>, arg: Any?): Any? {
        return try {
            val method = target.javaClass.getMethod(methodName, argType)
            method.invoke(target, arg)
        } catch (e: NoSuchMethodException) {
            val method = target.javaClass.declaredMethods.find {
                it.name == methodName && it.parameterCount == 1
            }
            method?.isAccessible = true
            method?.invoke(target, arg)
        }
    }

    private fun invokeTwoArg(
        target: Any, methodName: String,
        argType1: Class<*>, arg1: Any?,
        argType2: Class<*>, arg2: Any?
    ): Any? {
        return try {
            val method = target.javaClass.getMethod(methodName, argType1, argType2)
            method.invoke(target, arg1, arg2)
        } catch (e: NoSuchMethodException) {
            val method = target.javaClass.declaredMethods.find {
                it.name == methodName && it.parameterCount == 2
            }
            method?.isAccessible = true
            method?.invoke(target, arg1, arg2)
        }
    }
}
