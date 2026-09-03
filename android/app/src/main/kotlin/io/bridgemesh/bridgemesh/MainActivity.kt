package io.bridgemesh.bridgemesh

import android.content.Intent
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Точка входа в приложение.
 *
 * Регистрирует MethodChannel `bridge_mesh/foreground`,
 * через который Dart-слой может запустить/остановить
 * foreground-сервис, чтобы сеть жила в фоне.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "bridge_mesh/foreground"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val intent = Intent(this, MeshForegroundService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (t: Throwable) {
                        result.error("START_FAIL", t.message, null)
                    }
                }
                "stop" -> {
                    try {
                        val intent = Intent(this, MeshForegroundService::class.java)
                        stopService(intent)
                        result.success(true)
                    } catch (t: Throwable) {
                        result.error("STOP_FAIL", t.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
