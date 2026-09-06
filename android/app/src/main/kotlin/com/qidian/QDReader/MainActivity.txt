package com.qidian.QDReader

import android.annotation.TargetApi
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceCallback
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugins.GeneratedPluginRegistrant.registerWith
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant.registerWith
class MainActivity: FlutterActivity() {
    private val TAG = "MainActivity"
    // MethodChannel 用于与 native 层交互
    private val METHOD_CHANNEL_NAME = "com.kugou.android.auto/atomic_lyrics"
    // 双层幂等锁
    private val idempotentLock = AtomicBoolean(false)
    // 25秒重发门限
    private val resendThresholdMs = 25000
    // ... (省略其他业务代码，保持不变)
    override fun configureFlutterEngine(@NotNull engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        GeneratedPluginRegistrant.registerWith(engine)
    }
}
