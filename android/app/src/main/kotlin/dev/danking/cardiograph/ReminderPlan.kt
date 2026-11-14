package dev.danking.cardiograph

import java.time.ZonedDateTime

/** Calendar recurrence, never a fixed 24-hour duration. Shared by alarm and UI. */
object ReminderPlan {
    val slots = linkedMapOf(1000 to 10, 1600 to 16, 2100 to 21)
    fun next(id: Int, now: ZonedDateTime, delivered: String? = null): ZonedDateTime {
        val hour = requireNotNull(slots[id])
        var day = now.toLocalDate()
        var next = day.atTime(hour, 0).atZone(now.zone)
        if (!next.isAfter(now) || day.toString() == delivered) {
            day = day.plusDays(1)
            next = day.atTime(hour, 0).atZone(now.zone)
        }
        return next
    }
    fun canDeliver(enabled: Boolean, allowed: Boolean, last: String?, date: String) =
        enabled && allowed && last != date
}
