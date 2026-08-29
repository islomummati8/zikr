package com.zikr.zkr

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private val CHANNEL = "app.channel.timezone"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getTimeZoneName") {
                try {
                    val tz = TimeZone.getDefault().id
                    result.success(tz)
                } catch (e: Exception) {
                    result.error("UNAVAILABLE", "Timezone not available", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}