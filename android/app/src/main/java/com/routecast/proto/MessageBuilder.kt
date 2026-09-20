package com.routecast.proto

import com.routecast.Config
import java.util.UUID

/**
 * Превращает закодированный маршрут в последовательность пакетов протокола
 * (docs/protocol.md): H -> L0..Ln -> M -> E. Координаты/манёвры — списки целых
 * (ложатся в Monkey C Array на стороне часов).
 */
object MessageBuilder {

    fun build(enc: Encoder.Encoded, id: String = UUID.randomUUID().toString().replace("-", "")): List<Packet> {
        require(id.matches(Regex("[0-9a-f]{32}")))
        val maneuverChunks = enc.maneuvers.m.chunked(Config.MANEUVERS_PER_CHUNK).ifEmpty { listOf(emptyList()) }
        val out = ArrayList<Packet>()

        out.add(
            Packet(
                ackSeq = -1,
                payload = mapOf(
                    "t" to "H",
                    "v" to enc.header.v,
                    "id" to id,
                    "np" to enc.header.np,
                    "nc" to enc.header.nc,
                    "nm" to enc.header.nm,
                    "mc" to maneuverChunks.size,
                    "name" to enc.header.name
                )
            )
        )

        for (c in enc.chunks) {
            val p = c.p.map { listOf(it[0], it[1]) }
            out.add(Packet(c.s, mapOf("t" to "L", "id" to id, "s" to c.s, "p" to p)))
        }

        for ((index, chunk) in maneuverChunks.withIndex()) {
            val seq = enc.chunks.size + index
            val m = chunk.map { listOf(it[0], it[1], it[2]) }
            out.add(Packet(seq, mapOf("t" to "M", "id" to id, "s" to seq, "m" to m)))
        }

        out.add(Packet(-3, mapOf("t" to "E", "id" to id)))
        return out
    }
}
