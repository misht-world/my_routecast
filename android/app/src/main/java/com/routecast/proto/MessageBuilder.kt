package com.routecast.proto

/**
 * Превращает закодированный маршрут в последовательность пакетов протокола
 * (docs/protocol.md): H -> L0..Ln -> M -> E. Координаты/манёвры — списки целых
 * (ложатся в Monkey C Array на стороне часов).
 */
object MessageBuilder {

    fun build(enc: Encoder.Encoded): List<Packet> {
        val out = ArrayList<Packet>()

        out.add(
            Packet(
                ackSeq = -1,
                payload = mapOf(
                    "t" to "H",
                    "v" to enc.header.v,
                    "np" to enc.header.np,
                    "nc" to enc.header.nc,
                    "nm" to enc.header.nm,
                    "name" to enc.header.name
                )
            )
        )

        for (c in enc.chunks) {
            val p = c.p.map { listOf(it[0], it[1]) }
            out.add(Packet(c.s, mapOf("t" to "L", "s" to c.s, "p" to p)))
        }

        val m = enc.maneuvers.m.map { listOf(it[0], it[1], it[2]) }
        out.add(Packet(-2, mapOf("t" to "M", "m" to m)))

        out.add(Packet(-3, mapOf("t" to "E")))
        return out
    }
}
