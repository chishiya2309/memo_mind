package com.example.memo_mind

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "memo_mind/storage",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAvailableBytes" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("invalid_path", "Thiếu đường dẫn cần kiểm tra.", null)
                    } else {
                        try {
                            result.success(StatFs(path).availableBytes)
                        } catch (error: Exception) {
                            result.error("storage_error", error.message, null)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
