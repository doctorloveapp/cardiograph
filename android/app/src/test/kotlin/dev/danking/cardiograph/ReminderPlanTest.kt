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
    @Test fun suppressCoveredAndReactivateOnDeletion() {
        val now = ZonedDateTime.of(2026,11,15,9,30,0,0,rome)
        assertEquals("2026-11-16", ReminderPlan.next(1000, now, covered=setOf("2026-11-15")).toLocalDate().toString())
        assertEquals("2026-11-15", ReminderPlan.next(1000, now, covered=emptySet()).toLocalDate().toString())
        assertFalse(ReminderPlan.canDeliver(true,true,null,"2026-11-15",covered=true))
        assertTrue(ReminderPlan.canDeliver(true,true,null,"2026-11-15",covered=false))
        assertFalse(ReminderPlan.canDeliver(true,true,null,"2026-11-15",dirty=true))
    }
    @Test fun eveningNightDoesNotSuppressNextEvening() {
        val night = ZonedDateTime.of(2026,11,15,2,0,0,0,rome)
        assertEquals("2026-11-14",ReminderPlan.session(2100,night))
        val day = ZonedDateTime.of(2026,11,15,19,30,0,0,rome)
        assertEquals("2026-11-15",ReminderPlan.session(2100,day))
        assertEquals("2026-11-15",ReminderPlan.next(2100,day,covered=setOf("2026-11-14")).toLocalDate().toString())
        assertEquals("2026-11-16",ReminderPlan.next(2100,day,minute=120,covered=setOf("2026-11-14")).toLocalDate().toString())
    }
    @Test fun customTimesAndDst() {
        assertTrue(ReminderPlan.validMinute(1000,420)); assertTrue(ReminderPlan.validMinute(1000,780))
        assertTrue(ReminderPlan.validMinute(1600,781)); assertTrue(ReminderPlan.validMinute(1600,1140))
        assertTrue(ReminderPlan.validMinute(2100,0)); assertTrue(ReminderPlan.validMinute(2100,419))
        assertFalse(ReminderPlan.validMinute(2100,420)); assertFalse(ReminderPlan.validMinute(1000,781))
        val now = ZonedDateTime.of(2026,3,28,20,0,0,0,rome)
        val next=ReminderPlan.next(2100,now,minute=150)
        assertTrue(next.isAfter(now)); assertEquals("2026-03-28",ReminderPlan.session(2100,next))
        assertEquals(30,next.minute)
    }
}
