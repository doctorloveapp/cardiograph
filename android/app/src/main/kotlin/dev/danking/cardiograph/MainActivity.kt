package dev.danking.cardiograph
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    private lateinit var cameraBridge: CameraBridge
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        cameraBridge = CameraBridge(this, engine)
    }
    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        if (::cameraBridge.isInitialized) cameraBridge.permissionResult(code)
    }
    override fun onStop() {
        if (::cameraBridge.isInitialized) cameraBridge.close()
        super.onStop()
    }
    override fun onDestroy() {
        if (::cameraBridge.isInitialized) cameraBridge.dispose()
        super.onDestroy()
    }
}
