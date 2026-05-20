package com.linkguard.app.engine

import com.linkguard.app.model.*

class SimulationEngine {

    private val victimIDs = listOf("VT-A3F", "VT-B72", "VT-C1E", "VT-D9A", "VT-E45")

    fun createInitialNodeStatus(): RescueNodeStatus {
        return RescueNodeStatus(
            nodeID = "RT-7F2-EMT",
            deptCode = "EMT",
            battery = 85,
            loraLevel = 4,
            isConnected = false,
            pairCode = "0000"
        )
    }

    fun createInitialVictims(): List<VictimNode> {
        val now = System.currentTimeMillis()
        return listOf(
            VictimNode("VT-A3F", 78, 65, -62.0, 8.5, true, now, true),
            VictimNode("VT-B72", 92, 43, -78.0, 5.2, false, now - 10000, true),
            VictimNode("VT-C1E", 0, 12, -91.0, 1.3, true, now - 45000, false),
        )
    }

    fun createInitialSOSRecords(): List<SOSRecord> {
        val now = System.currentTimeMillis()
        return listOf(
            SOSRecord(victimID = "VT-A3F", heartRate = 78, rssi = -62.0,
                distance = "1.2m", battery = 65, time = now - 30000, isAcknowledged = false),
            SOSRecord(victimID = "VT-C1E", heartRate = 0, rssi = -91.0,
                distance = "48m", battery = 12, time = now - 120000, isAcknowledged = true),
        )
    }

    fun updateVictimSignals(victims: MutableList<VictimNode>) {
        for (i in victims.indices) {
            if (!victims[i].isOnline) continue
            val rssiDrift = (-3..3).random().toDouble()
            val snrDrift = (-0.5 + Math.random()).let { it - 0.5 }
            val hrDrift = (-3..3).random()

            victims[i] = victims[i].copy(
                rssi = (victims[i].rssi + rssiDrift).coerceIn(-99.0, -30.0),
                snr = (victims[i].snr + snrDrift).coerceIn(-5.0, 15.0),
                heartRate = if (victims[i].heartRate > 0)
                    (victims[i].heartRate + hrDrift).coerceIn(40, 180) else 0,
                lastSeen = System.currentTimeMillis(),
                battery = if ((0..15).random() == 0)
                    maxOf(0, victims[i].battery - 1) else victims[i].battery
            )
        }
    }

    fun updateVictimOnlineStatus(victims: MutableList<VictimNode>) {
        val now = System.currentTimeMillis()
        for (i in victims.indices) {
            val interval = (now - victims[i].lastSeen) / 1000
            var online = interval < 30
            if (!online && (0..10).random() == 0) {
                online = true
                victims[i] = victims[i].copy(
                    isOnline = true,
                    rssi = (-85..-50).random().toDouble(),
                    lastSeen = now
                )
            } else {
                victims[i] = victims[i].copy(isOnline = online)
            }
        }
    }

    fun updateNodeStatus(status: RescueNodeStatus): RescueNodeStatus {
        return if ((0..30).random() == 0) {
            status.copy(battery = maxOf(0, status.battery - 1))
        } else status
    }

    fun maybeDiscoverNewVictim(existing: List<VictimNode>): VictimNode? {
        if ((0..30).random() != 0) return null
        val existingIDs = existing.map { it.id }.toSet()
        val available = victimIDs.filter { it !in existingIDs }
        val newID = available.randomOrNull() ?: return null
        return VictimNode(
            id = newID,
            heartRate = if ((0..1).random() == 0) (50..120).random() else 0,
            battery = (10..90).random(),
            rssi = (-90..-50).random().toDouble(),
            snr = (0..10).random().toDouble(),
            isSOS = (0..2).random() == 0,
            lastSeen = System.currentTimeMillis(),
            isOnline = true
        )
    }

    fun maybeToggleSOS(victims: MutableList<VictimNode>): SOSRecord? {
        if (victims.isEmpty()) return null
        val i = victims.indices.random()
        if (!victims[i].isOnline || (0..20).random() != 0) return null
        victims[i] = victims[i].copy(isSOS = !victims[i].isSOS)
        if (!victims[i].isSOS) return null
        return SOSRecord(
            victimID = victims[i].id,
            heartRate = victims[i].heartRate,
            rssi = victims[i].rssi,
            distance = victims[i].distanceText,
            battery = victims[i].battery,
            time = System.currentTimeMillis()
        )
    }
}
