package dev.danking.cardiograph
import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    private lateinit var cameraBridge: CameraBridge
    private lateinit var platformBridge: PlatformBridge
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        cameraBridge = CameraBridge(this, engine)
        platformBridge = PlatformBridge(this, engine)
    }
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        if (::cameraBridge.isInitialized) cameraBridge.permissionResult(code)
        if (::platformBridge.isInitialized) platformBridge.permissionResult(code)
    }
    override fun onActivityResult(code: Int, status: Int, data: Intent?) {
        if (::platformBridge.isInitialized && platformBridge.activityResult(code, status, data)) return
        super.onActivityResult(code, status, data)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (::platformBridge.isInitialized) platformBridge.newIntent(intent)
    }
    override fun onResume() {
        super.onResume()
        ReminderEngine.reconcile(this)
    }
    override fun onStop() {
        if (::cameraBridge.isInitialized) cameraBridge.close()
        super.onStop()
    }
    override fun onDestroy() {
        if (::cameraBridge.isInitialized) cameraBridge.dispose()
        if (::platformBridge.isInitialized) platformBridge.dispose()
        super.onDestroy()
    }
}
