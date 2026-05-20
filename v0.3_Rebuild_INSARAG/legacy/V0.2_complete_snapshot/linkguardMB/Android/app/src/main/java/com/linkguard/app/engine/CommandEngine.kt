package com.linkguard.app.engine

import com.linkguard.app.model.*

class CommandEngine {

    private val senders = listOf("HQ-Alpha", "HQ-Bravo", "CMD-Central", "OPS-South")

    private data class Template(val title: String, val detail: String, val priority: CommandPriority)

    private val templates: Map<CommandType, List<Template>> = mapOf(
        CommandType.SEARCH_AREA to listOf(
            Template("搜索 B 區 3F", "請前往 B 區 3 樓西側走廊進行生命跡象掃描", CommandPriority.ROUTINE),
            Template("緊急搜索 A 區地下室", "偵測到微弱訊號，立即前往 A 區 B1 確認", CommandPriority.URGENT),
            Template("擴大搜索範圍至 C 區", "C 區尚未覆蓋，請擴展掃描", CommandPriority.ROUTINE),
        ),
        CommandType.STANDBY to listOf(
            Template("原地待命", "目前區域安全評估中，請暫停搜索等待指示", CommandPriority.ROUTINE),
            Template("暫停推進", "結構工程師正在評估建物穩定性，所有隊伍原地待命", CommandPriority.URGENT),
        ),
        CommandType.SUPPORT to listOf(
            Template("請求醫療支援", "B 區發現傷者，需要 EMT 支援", CommandPriority.URGENT),
            Template("請求重型設備", "C 區入口被堵，需要破壞工具", CommandPriority.ROUTINE),
            Template("緊急增援", "A 區發現多名受困者，人力不足請立即增援", CommandPriority.CRITICAL),
        ),
        CommandType.STATUS_REPORT to listOf(
            Template("回報搜索進度", "請各隊伍回報目前搜索完成百分比", CommandPriority.ROUTINE),
            Template("回報人員狀態", "請確認隊員健康狀況與裝備電量", CommandPriority.ROUTINE),
        ),
        CommandType.EVACUATION to listOf(
            Template("立即撤離", "偵測到餘震風險，所有人員立即撤離至安全區", CommandPriority.CRITICAL),
            Template("部分撤離 D 區", "D 區結構不穩，該區人員撤離至集合點", CommandPriority.URGENT),
            Template("撤離準備", "預計 10 分鐘後進行全面撤離，請做好準備", CommandPriority.ROUTINE),
        ),
    )

    fun generateRandomCommand(): CommandOrder {
        val type = CommandType.entries.random()
        val pool = templates[type] ?: templates.values.firstOrNull() ?: return CommandOrder(
            type = CommandType.SEARCH_AREA, priority = CommandPriority.ROUTINE,
            title = "一般搜救", detail = "", sender = "HQ"
        )
        val template = pool.random()
        val sender = senders.random()
        return CommandOrder(
            type = type,
            priority = template.priority,
            title = template.title,
            detail = template.detail,
            sender = sender
        )
    }

    fun nextInterval(): Long = (15000L..30000L).random()
}
