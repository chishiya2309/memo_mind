package vn.edu.hcmute.memo_mind

import android.os.StatFs
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.content.Context

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "memo_mind/connectivity")
            .setStreamHandler(object : EventChannel.StreamHandler {
                private val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                private var callback: ConnectivityManager.NetworkCallback? = null
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    callback = object : ConnectivityManager.NetworkCallback() {
                        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                            val ready = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                            runOnUiThread { events.success(ready) }
                        }
                        override fun onLost(network: Network) { runOnUiThread { events.success(false) } }
                    }
                    manager.registerDefaultNetworkCallback(callback!!)
                    val capabilities = manager.getNetworkCapabilities(manager.activeNetwork)
                    events.success(capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true)
                }
                override fun onCancel(arguments: Any?) {
                    callback?.let { manager.unregisterNetworkCallback(it) }
                    callback = null
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "memo_mind/reminders")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSdkInt" -> result.success(Build.VERSION.SDK_INT)
                    else -> result.notImplemented()
                }
            }
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
