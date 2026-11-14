package dev.danking.cardiograph

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** SAF owns destination URIs; neither a path nor broad storage permission is required. */
class PlatformBridge(private val activity: MainActivity, engine: FlutterEngine) {
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "dev.danking.cardiograph/platform")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var bytes: ByteArray? = null
    private var permission: MethodChannel.Result? = null
    private var launch = activity.intent?.action == ReminderEngine.TAP
    private val directory = File(activity.cacheDir, "cardiograph_reports").apply { mkdirs() }
    init {
        // Only app-owned share PDFs, never a SAF destination or another cache directory.
        clean()
        ReminderEngine.reconcile(activity)
        channel.setMethodCallHandler { call, result ->
            try {
                when(call.method) {
                    "save" -> {
                        check(pending == null) { "Selettore documenti già aperto" }
                        bytes = call.argument<ByteArray>("bytes") ?: error("Documento mancante")
                        val name = call.argument<String>("name") ?: "CardioGraph.pdf"
                        pending = result
                        activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(if (name.endsWith(".pdf")) "application/pdf" else "application/octet-stream")
                            .putExtra(Intent.EXTRA_TITLE, name), 703)
                    }
                    "openBackup" -> {
                        check(pending == null) { "Selettore documenti già aperto" }; pending = result
                        activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("*/*"), 704)
                    }
                    "share" -> {
                        val data = call.argument<ByteArray>("bytes") ?: error("Documento mancante")
                        val f = File(directory, "report_${UUID.randomUUID()}.pdf"); f.writeBytes(data)
                        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.reports", f)
                        val send = Intent(Intent.ACTION_SEND).setType("application/pdf").putExtra(Intent.EXTRA_STREAM, uri)
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        activity.startActivity(Intent.createChooser(send, "Condividi PDF"))
                        // Let receiving apps finish reading; crash leftovers are removed next launch.
                        main.postDelayed({ if (f.parentFile?.canonicalFile == directory.canonicalFile) f.delete() }, 15 * 60 * 1000L)
                        result.success(null)
                    }
                    "reminderStatus" -> result.success(ReminderEngine.status(activity))
                    "reconcile" -> { ReminderEngine.reconcile(activity); result.success(ReminderEngine.status(activity)) }
                    "setReminder" -> {
                        ReminderEngine.set(activity, call.argument<Int>("id")!!, call.argument<Boolean>("enabled") == true)
                        result.success(ReminderEngine.status(activity))
                    }
                    "requestNotifications" -> {
                        if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                            check(permission == null); permission = result
                            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 702)
                        } else result.success(ReminderEngine.status(activity))
                    }
                    "notificationSettings" -> {
                        activity.startActivity(Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName).putExtra(Settings.EXTRA_CHANNEL_ID, ReminderEngine.CHANNEL))
                        result.success(null)
                    }
                    "exactSettings" -> {
                        if (Build.VERSION.SDK_INT >= 31) activity.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                            Uri.parse("package:${activity.packageName}")))
                        result.success(null)
                    }
                    "testNotification" -> { ReminderEngine.post(activity); result.success(null) }
                    "takeLaunch" -> { result.success(launch); launch = false }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                if (pending === result) { pending = null; bytes = null }
                result.error("PLATFORM", e.message ?: "Operazione non riuscita", null)
            }
        }
    }
    private fun clean() {
        directory.listFiles()?.filter { it.isFile && it.name.startsWith("report_") && it.extension == "pdf" }?.forEach { it.delete() }
    }
    fun permissionResult(code: Int) {
        if (code == 702) { ReminderEngine.reconcile(activity); permission?.success(ReminderEngine.status(activity)); permission = null }
    }
    fun newIntent(intent: Intent) {
        if (intent.action == ReminderEngine.TAP) {
            launch = true
            channel.invokeMethod("notificationTap", null)
        }
    }
    fun activityResult(code: Int, status: Int, data: Intent?): Boolean {
        if (code != 703 && code != 704) return false
        val result = pending ?: return true
        val payload = bytes; pending = null; bytes = null
        val uri = data?.data
        if (status != Activity.RESULT_OK || uri == null) { result.success(if (code == 703) false else null); return true }
        io.execute {
            try {
                val value: Any = if (code == 703) {
                    activity.contentResolver.openOutputStream(uri, "wt")?.use { it.write(requireNotNull(payload)); it.flush() }
                        ?: error("Destinazione non scrivibile")
                    true
                } else activity.contentResolver.openInputStream(uri)?.use {
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val n = it.read(buffer); if (n < 0) break
                        check(output.size() + n <= 64 * 1024 * 1024) { "Backup troppo grande" }
                        output.write(buffer, 0, n)
                    }
                    output.toByteArray()
                } ?: error("Documento non leggibile")
                main.post { result.success(value) }
            } catch (_: Exception) { main.post { result.error("DOCUMENT", "Lettura o scrittura del documento non riuscita", null) } }
        }
        return true
    }
    fun dispose() {
        pending?.error("CANCELLED", "Operazione interrotta", null); pending = null; bytes = null
        permission?.error("CANCELLED", "Richiesta interrotta", null); permission = null
        channel.setMethodCallHandler(null); io.shutdown()
    }
}
