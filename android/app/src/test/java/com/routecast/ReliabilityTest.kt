package com.routecast

import com.routecast.model.Pt
import com.routecast.proto.Encoder
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.StringReader
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class ReliabilityTest {
    @get:Rule val temp = TemporaryFolder()

    @Test fun snapshotRoundTripAndInvalidReplacementPreservesPrevious() {
        val store = RouteStore(temp.newFolder())
        val route = RouteStore.Saved(Encoder.encode(listOf(Pt(50.0, 30.0), Pt(50.001, 30.001)), emptyList(), "Saved"), 132)
        store.save(route)
        val loaded = store.load()!!
        assertEquals("Saved", loaded.encoded.header.name)
        assertEquals(132, loaded.meters)
        assertEquals(2, loaded.encoded.header.v)
        assertThrows(IllegalArgumentException::class.java) { store.save(route.copy(meters = -1)) }
        assertEquals("Saved", store.load()!!.encoded.header.name)
    }

    @Test fun corruptSnapshotIsRejected() {
        assertThrows(Exception::class.java) { RouteStore.decode("{}") }
        assertThrows(Exception::class.java) { RouteStore.decode("""{"format":1,"name":"x","meters":1,"points":[[91000000,0],[0,0]],"maneuvers":[]}""") }
    }

    @Test fun inputLimitAndBom() {
        assertEquals("<gpx/>", RouteInput.read(StringReader("\uFEFF<gpx/>")))
        assertThrows(IllegalArgumentException::class.java) {
            RouteInput.read(StringReader("x".repeat(Config.MAX_INPUT_CHARS + 1)))
        }
    }

    @Test fun onlyNewestQueuedImportRuns() {
        val runner = LatestTaskRunner()
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val done = CountDownLatch(1)
        val seen = Collections.synchronizedList(mutableListOf<Int>())
        try {
            runner.submit {
                started.countDown()
                // Simulate a provider that is slow to respond to interruption.
                while (release.count > 0) { try { release.await() } catch (_: InterruptedException) {} }
            }
            assertTrue(started.await(3, TimeUnit.SECONDS))
            runner.submit { seen.add(1) }
            runner.submit { seen.add(2); done.countDown() }
            release.countDown()
            assertTrue(done.await(3, TimeUnit.SECONDS))
            assertEquals(listOf(2), seen.toList())
        } finally { release.countDown(); runner.close() }
    }
}
