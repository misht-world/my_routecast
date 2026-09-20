package com.routecast

import java.io.Reader
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.Future
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** One running import and at most one pending replacement. Never a growing queue. */
class LatestTaskRunner {
    private val executor = ThreadPoolExecutor(1, 1, 0, TimeUnit.MILLISECONDS,
        ArrayBlockingQueue<Runnable>(1), ThreadPoolExecutor.DiscardOldestPolicy())
    private var task: Future<*>? = null

    @Synchronized fun submit(block: () -> Unit) {
        task?.cancel(true)
        executor.queue.clear()
        task = executor.submit(block)
    }
    @Synchronized fun close() { task?.cancel(true); executor.shutdownNow() }
}

object RouteInput {
    fun read(reader: Reader): String {
        val text = StringBuilder()
        val buffer = CharArray(8192)
        while (true) {
            if (Thread.currentThread().isInterrupted) throw InterruptedException()
            val n = reader.read(buffer)
            if (n < 0) break
            require(text.length + n <= Config.MAX_INPUT_CHARS) { "Route file is too large." }
            text.append(buffer, 0, n)
        }
        return text.toString().removePrefix("\uFEFF")
    }
}
