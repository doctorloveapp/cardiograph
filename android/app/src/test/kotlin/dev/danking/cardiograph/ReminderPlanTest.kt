package dev.danking.cardiograph

import org.junit.Assert.*
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

class ReminderPlanTest {
    private val rome = ZoneId.of("Europe/Rome")
    @Test fun stableSlotsAndIdempotence() {
        assertEquals(listOf(1000,1600,2100), ReminderPlan.slots.keys.toList())
        val now = ZonedDateTime.of(2026,11,14,9,0,0,0,rome)
        assertEquals(ReminderPlan.next(1000, now), ReminderPlan.next(1000, now))
        assertEquals(10, ReminderPlan.next(1000, now).hour)
        assertEquals(15, ReminderPlan.next(1000, now, "2026-11-14").dayOfMonth)
    }
    @Test fun dstKeepsLocalHoursAndYearBoundary() {
        for ((month, day, delta) in listOf(Triple(3,28,23L),Triple(10,24,25L))) {
            val now = ZonedDateTime.of(2026,month,day,10,0,0,0,rome)
            val next = ReminderPlan.next(1000, now)
            assertEquals(10,next.hour)
            assertEquals(delta, java.time.Duration.between(now,next).toHours())
        }
        val next = ReminderPlan.next(2100, ZonedDateTime.of(2026,12,31,21,0,0,0,rome))
        assertEquals("2027-01-01",next.toLocalDate().toString())
        assertEquals(21,next.hour)
    }
    @Test fun permissionAndGuardDeduplication() {
        assertTrue(ReminderPlan.canDeliver(true,true,null,"2026-11-14"))
        assertFalse(ReminderPlan.canDeliver(false,true,null,"2026-11-14"))
        assertFalse(ReminderPlan.canDeliver(true,false,null,"2026-11-14"))
        assertFalse(ReminderPlan.canDeliver(true,true,"2026-11-14","2026-11-14"))
    }
}
