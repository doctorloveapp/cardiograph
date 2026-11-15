package dev.danking.cardiograph

import java.time.ZonedDateTime

/** Local recurrence and session keys; no fixed 24-hour arithmetic. */
object ReminderPlan {
    val slots = linkedMapOf(1000 to 10, 1600 to 16, 2100 to 21)
    fun validMinute(id: Int, minute: Int): Boolean = minute in 0..1439 && when(id) {
        1000 -> minute in 420..780
        1600 -> minute in 781..1140
        2100 -> minute < 420 || minute > 1140
        else -> false
    }
    fun session(id: Int, at: ZonedDateTime): String =
        (if (id == 2100 && at.hour < 7) at.toLocalDate().minusDays(1) else at.toLocalDate()).toString()
    fun next(id: Int, now: ZonedDateTime, delivered: String? = null,
             minute: Int = requireNotNull(slots[id]) * 60, covered: Set<String> = emptySet()): ZonedDateTime {
        require(validMinute(id, minute))
        var day = now.toLocalDate()
        var next = day.atTime(minute / 60, minute % 60).atZone(now.zone)
        if (!next.isAfter(now)) {
            day = day.plusDays(1)
            next = day.atTime(minute / 60, minute % 60).atZone(now.zone)
        }
        if (session(id, next) == delivered || session(id, next) in covered) {
            day = day.plusDays(1)
            next = day.atTime(minute / 60, minute % 60).atZone(now.zone)
        }
        return next
    }
    fun canDeliver(enabled: Boolean, allowed: Boolean, last: String?, date: String,
                   covered: Boolean = false, dirty: Boolean = false) =
        enabled && allowed && last != date && !covered && !dirty
}
