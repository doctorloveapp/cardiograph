package dev.danking.cardiograph

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.time.ZoneId
import java.time.ZonedDateTime

object ReminderEngine {
    const val CHANNEL = "daily_reminders_v1"
    const val TAP = "dev.danking.cardiograph.NEW_MEASUREMENT"
    private const val ALARM = "dev.danking.cardiograph.REMINDER"
    private fun prefs(c: Context) = c.getSharedPreferences("daily_reminders", Context.MODE_PRIVATE)
    private fun manager(c: Context) = c.getSystemService(AlarmManager::class.java)
    fun channel(c: Context) {
        c.getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "Promemoria giornalieri", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Promemoria personali di CardioGraph"
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            })
    }
    fun allowed(c: Context): Boolean {
        channel(c)
        return (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(c,
            Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            NotificationManagerCompat.from(c).areNotificationsEnabled() &&
            c.getSystemService(NotificationManager::class.java).getNotificationChannel(CHANNEL).importance != NotificationManager.IMPORTANCE_NONE
    }
    fun exact(c: Context) = Build.VERSION.SDK_INT < 31 || manager(c).canScheduleExactAlarms()
    private fun pending(c: Context, id: Int, guard: Boolean) = PendingIntent.getBroadcast(c, id,
        Intent(c, ReminderReceiver::class.java).setAction(ALARM + if (guard) ".GUARD" else ".PRIMARY").putExtra("slot", id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    @Synchronized fun set(c: Context, id: Int, enabled: Boolean) {
        require(id in ReminderPlan.slots)
        prefs(c).edit().putBoolean("enabled_$id", enabled).commit()
        reconcile(c)
    }
    @Synchronized fun beginMutation(c: Context) {
        check(prefs(c).edit().putBoolean("coverage_dirty", true).commit())
        // Do not cancel recurrence: a crash must not permanently remove reminders.
    }
    private fun covered(c: Context, id: Int) = prefs(c).getStringSet("coverage_$id", emptySet()) ?: emptySet()
    private fun minute(c: Context, id: Int) = prefs(c).getInt("minutes_$id", requireNotNull(ReminderPlan.slots[id]) * 60)
    @Synchronized fun applyPreferences(c: Context, enabled: List<Boolean>, minutes: List<Int>, coverage: Map<String, List<String>>) {
        require(enabled.size == 3 && minutes.size == 3)
        val edit = prefs(c).edit()
        ReminderPlan.slots.keys.forEachIndexed { index, id ->
            require(ReminderPlan.validMinute(id, minutes[index]))
            val dates = requireNotNull(coverage[id.toString()])
            require(dates.size <= 100000 && dates.all { it.matches(Regex("\\d{4}-\\d{2}-\\d{2}")) })
            edit.putBoolean("enabled_$id", enabled[index])
            edit.putInt("minutes_$id", minutes[index])
            edit.putStringSet("coverage_$id", dates.toSet())
        }
        edit.putBoolean("coverage_dirty", false)
        check(edit.commit()) { "Preferenze promemoria non salvate" }
        reconcile(c)
    }
    @Synchronized fun reconcile(c: Context) {
        channel(c)
        val p = prefs(c); val alarms = manager(c)
        val now = ZonedDateTime.now(ZoneId.systemDefault())
        val allowed = allowed(c)
        ReminderPlan.slots.keys.forEach { id ->
            alarms.cancel(pending(c, id, false)); alarms.cancel(pending(c, id, true))
            if (p.getBoolean("enabled_$id", false) && allowed) {
                val at = ReminderPlan.next(id, now, p.getString("last_$id", null), minute(c, id), covered(c, id)).toInstant().toEpochMilli()
                // Inexact guard survives revocation: Android cancels exact alarms and kills
                // the process on revocation. Delivery is deduplicated by slot/local day.
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(c, id, true))
                if (exact(c)) try {
                    alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(c, id, false))
                } catch (_: SecurityException) { /* Inexact guard already armed. */ }
            }
        }
    }
    @Synchronized fun fire(c: Context, id: Int) {
        if (id !in ReminderPlan.slots) return
        val p = prefs(c); val day = ReminderPlan.session(id, ZonedDateTime.now())
        if (ReminderPlan.canDeliver(p.getBoolean("enabled_$id", false), allowed(c), p.getString("last_$id", null), day, day in covered(c, id), p.getBoolean("coverage_dirty", true))) {
            try {
                post(c, id)
                p.edit().putString("last_$id", day).commit()
            } catch (_: SecurityException) { /* Revoked between check and notify. */ }
        }
        reconcile(c)
    }
    fun post(c: Context, id: Int = 9900) {
        check(allowed(c)) { "Notifiche non consentite: controlla anche il canale Android." }
        val tap = PendingIntent.getActivity(c, 100,
            Intent(c, MainActivity::class.java).setAction(TAP)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val public = NotificationCompat.Builder(c, CHANNEL).setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("CardioGraph").setContentText("Promemoria personale").build()
        val notification = NotificationCompat.Builder(c, CHANNEL).setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("CardioGraph").setContentText("Apri l’app per continuare.")
            .setContentIntent(tap).setAutoCancel(true).setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).setPublicVersion(public).build()
        NotificationManagerCompat.from(c).notify(id, notification)
    }
    fun status(c: Context): Map<String, Any> {
        val now = ZonedDateTime.now(); val p = prefs(c)
        return mapOf("allowed" to allowed(c), "exact" to exact(c), "zone" to now.zone.id,
            "slots" to ReminderPlan.slots.map { (id, _) -> mapOf("id" to id,
                "enabled" to p.getBoolean("enabled_$id", false),
                "minutes" to minute(c, id),
                "pendingSync" to p.getBoolean("coverage_dirty", true),
                "covered" to (ReminderPlan.session(id, now) in covered(c, id)),
                "next" to ReminderPlan.next(id, now, p.getString("last_$id", null), minute(c, id), covered(c, id)).toString()) })
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.hasExtra("slot")) ReminderEngine.fire(context, intent.getIntExtra("slot", -1))
        else ReminderEngine.reconcile(context)
    }
}
