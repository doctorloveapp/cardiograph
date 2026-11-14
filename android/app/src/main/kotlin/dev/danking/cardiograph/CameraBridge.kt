package dev.danking.cardiograph

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.hardware.camera2.CameraCharacteristics
import android.net.Uri
import android.os.SystemClock
import android.provider.Settings
import android.view.View
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.math.abs

/** One lifecycle-bound CameraX owner. No second camera stream supplies the timestamp. */
class CameraBridge(private val activity: MainActivity, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "dev.danking.cardiograph/camera")
    private val executor = Executors.newSingleThreadExecutor()
    private val main = ContextCompat.getMainExecutor(activity)
    private val prefs = activity.getSharedPreferences("camera_permission", Context.MODE_PRIVATE)
    private val directory = File(activity.cacheDir, "cardiograph_camera").apply { mkdirs() }
    private var preview: PreviewView? = null
    private var provider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var capture: ImageCapture? = null
    private var permission: MethodChannel.Result? = null
    private var pendingCapture: MethodChannel.Result? = null
    private var generation = 0
    private var timestampSource: Int? = null

    init {
        // Crash leftovers belong exclusively to this dedicated private directory.
        directory.listFiles()?.filter { it.isFile && it.name.startsWith("frame_") }?.forEach { it.delete() }
        engine.platformViewsController.registry.registerViewFactory("dev.danking.cardiograph/preview",
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context, id: Int, args: Any?): PlatformView {
                    val view = PreviewView(context).apply {
                        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                        scaleType = PreviewView.ScaleType.FILL_CENTER
                        setOnTouchListener { _, event ->
                            if (event.action == android.view.MotionEvent.ACTION_UP) {
                                camera?.cameraControl?.startFocusAndMetering(
                                    FocusMeteringAction.Builder(
                                        meteringPointFactory.createPoint(event.x, event.y),
                                        FocusMeteringAction.FLAG_AF).build())
                            }
                            true
                        }
                    }
                    preview = view
                    return object : PlatformView {
                        override fun getView(): View = view
                        override fun dispose() { if (preview === view) { close(); preview = null } }
                    }
                }
            })
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "permission" -> result.success(permissionState())
                "requestPermission" -> {
                    if (permissionState() == "granted") result.success("granted")
                    else if (permission != null) result.error("BUSY", "Richiesta già attiva", null)
                    else {
                        permission = result
                        prefs.edit().putBoolean("asked", true).apply()
                        activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), 701)
                    }
                }
                "settings" -> { activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:${activity.packageName}"))); result.success(null) }
                "start" -> start(result)
                "capture" -> takePicture(result)
                "torch" -> {
                    val cam = camera
                    if (cam == null || !cam.cameraInfo.hasFlashUnit()) result.success(false)
                    else cam.cameraControl.enableTorch(call.argument<Boolean>("enabled") == true).addListener({
                        result.success(true)
                    }, main)
                }
                "close" -> { close(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private fun permissionState(): String = when {
        ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED -> "granted"
        prefs.getBoolean("asked", false) && !activity.shouldShowRequestPermissionRationale(Manifest.permission.CAMERA) -> "permanent"
        else -> "denied"
    }
    fun permissionResult(code: Int) {
        if (code == 701) { permission?.success(permissionState()); permission = null }
    }

    @androidx.annotation.OptIn(markerClass = [ExperimentalCamera2Interop::class])
    private fun start(result: MethodChannel.Result, attempts: Int = 0) {
        if (permissionState() != "granted") { result.error("PERMISSION", "Permesso fotocamera necessario", null); return }
        val view = preview
        if (view == null) { result.error("PREVIEW", "Anteprima non pronta", null); return }
        if (view.width == 0 || view.height == 0 || view.viewPort == null) {
            if (attempts < 25) view.postDelayed({ start(result, attempts + 1) }, 40)
            else result.error("PREVIEW", "Anteprima non disponibile", null)
            return
        }
        val token = generation
        val future = ProcessCameraProvider.getInstance(activity)
        future.addListener({
            try {
                if (token != generation) { result.error("CANCELLED", "Fotocamera sospesa", null); return@addListener }
                provider = future.get()
                camera?.cameraInfo?.cameraState?.removeObservers(activity)
                provider?.unbindAll()
                val rotation = view.display.rotation
                val imageCapture = ImageCapture.Builder().setTargetRotation(rotation)
                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).build()
                val live = Preview.Builder().setTargetRotation(rotation).build()
                live.setSurfaceProvider(view.surfaceProvider)
                val group = UseCaseGroup.Builder().setViewPort(view.viewPort!!)
                    .addUseCase(live).addUseCase(imageCapture).build()
                val bound = provider!!.bindToLifecycle(activity, CameraSelector.DEFAULT_BACK_CAMERA, group)
                camera = bound; capture = imageCapture
                bound.cameraControl.enableTorch(false)
                timestampSource = Camera2CameraInfo.from(bound.cameraInfo)
                    .getCameraCharacteristic(CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE)
                bound.cameraInfo.cameraState.observe(activity) { state ->
                    if (state.error != null) channel.invokeMethod("cameraError", "Fotocamera occupata o non disponibile. Riprova.")
                }
                result.success(mapOf("torch" to bound.cameraInfo.hasFlashUnit()))
            } catch (_: Exception) { result.error("CAMERA", "Fotocamera occupata o non disponibile", null) }
        }, main)
    }

    private fun takePicture(result: MethodChannel.Result) {
        val shot = capture
        if (shot == null) { result.error("CAMERA", "Fotocamera non pronta", null); return }
        if (pendingCapture != null) { result.error("BUSY", "Scatto già in corso", null); return }
        pendingCapture = result
        val requestedMono = SystemClock.elapsedRealtimeNanos()
        val requestedWall = System.currentTimeMillis()
        val source = timestampSource
        shot.takePicture(executor, object : ImageCapture.OnImageCapturedCallback() {
            override fun onCaptureSuccess(image: ImageProxy) {
                var file: File? = null
                try {
                    val before = SystemClock.elapsedRealtimeNanos()
                    val wall = System.currentTimeMillis()
                    val after = SystemClock.elapsedRealtimeNanos()
                    val mono = before + (after - before) / 2
                    val mapped = wall + (image.imageInfo.timestamp - mono) / 1_000_000
                    val stableClock = abs((wall-requestedWall) - (mono-requestedMono)/1_000_000) < 100
                    val precise = source == CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME &&
                        stableClock && mapped >= requestedWall - 100 && mapped <= wall + 10
                    val epoch = if (precise) mapped else requestedWall
                    // JPEG bytes, crop and rotation metadata all belong to THIS ImageProxy.
                    val buffer = image.planes[0].buffer
                    val bytes = ByteArray(buffer.remaining()); buffer.get(bytes)
                    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        ?: throw IllegalStateException("Unsupported image")
                    val rect = image.cropRect
                    val cropped = Bitmap.createBitmap(bitmap, rect.left, rect.top, rect.width(), rect.height())
                    val matrix = Matrix().apply { postRotate(image.imageInfo.rotationDegrees.toFloat()) }
                    val upright = Bitmap.createBitmap(cropped, 0, 0, cropped.width, cropped.height, matrix, true)
                    val scale = minOf(1.0, 2048.0/maxOf(upright.width, upright.height))
                    val output = if (scale < 1) Bitmap.createScaledBitmap(upright,
                        (upright.width*scale).toInt(), (upright.height*scale).toInt(), true) else upright
                    file = File(directory, "frame_${UUID.randomUUID()}.jpg")
                    file.outputStream().use { if (!output.compress(Bitmap.CompressFormat.JPEG, 95, it)) throw IllegalStateException() }
                    val zone = TimeZone.getDefault()
                    val payload = mapOf("path" to file.absolutePath, "capturedAt" to epoch,
                        "precise" to precise, "source" to if (precise) "REALTIME" else "UNKNOWN",
                        "zone" to zone.id, "offsetMinutes" to zone.getOffset(epoch)/60000,
                        "sensorNanos" to image.imageInfo.timestamp,
                        "width" to output.width, "height" to output.height)
                    setOf(bitmap, cropped, upright, output).forEach { it.recycle() }
                    val completed = file
                    activity.runOnUiThread {
                        if (pendingCapture === result) { pendingCapture = null; result.success(payload) }
                        else completed.delete()
                    }
                } catch (_: Exception) {
                    file?.delete()
                    activity.runOnUiThread { failCapture(result) }
                } finally { image.close() }
            }
            override fun onError(exception: ImageCaptureException) { activity.runOnUiThread { failCapture(result) } }
        })
    }
    private fun failCapture(result: MethodChannel.Result) {
        if (pendingCapture === result) { pendingCapture = null; result.error("CAPTURE", "Scatto non riuscito. Riprova.", null) }
    }
    fun close() {
        generation++
        camera?.cameraInfo?.cameraState?.removeObservers(activity)
        camera?.cameraControl?.enableTorch(false)
        provider?.unbindAll(); camera = null; capture = null
        pendingCapture?.error("CANCELLED", "Scatto annullato", null); pendingCapture = null
    }
    fun dispose() { close(); executor.shutdown(); channel.setMethodCallHandler(null) }
}
