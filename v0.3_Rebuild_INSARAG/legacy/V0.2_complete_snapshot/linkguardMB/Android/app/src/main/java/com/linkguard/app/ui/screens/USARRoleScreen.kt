package com.linkguard.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.linkguard.app.model.*
import com.linkguard.app.ui.theme.NV
import com.linkguard.app.ui.theme.NVShape
import com.linkguard.app.viewmodel.LinkGuardViewModel

// =====================================================
//  USAR 角色視圖 — 對齊 iOS USARFieldRoleView + SquadLeaderView
//  依人員配置角色自動路由到三個子視圖：
//    - SquadLeaderView    (隊長 / 一般隊員)
//    - SectorCommanderView (區段指揮官)
//    - WorksiteManagerView (救援現場管理)
// =====================================================

@Composable
fun USARRoleScreen(viewModel: LinkGuardViewModel) {
    val role by viewModel.usarRole.collectAsState()

    when (role) {
        UsarRole.SECTOR_COMMANDER -> SectorCommanderView(viewModel)
        UsarRole.WORKSITE_MANAGER -> WorksiteManagerView(viewModel)
        else                      -> SquadLeaderView(viewModel)
    }
}

// =====================================================
//  Squad Leader View
// =====================================================

@Composable
private fun SquadLeaderView(viewModel: LinkGuardViewModel) {
    val tasks by viewModel.tasks.collectAsState()
    val personnelAssignments by viewModel.personnelAssignments.collectAsState()
    var currentStatus by remember { mutableStateOf(OperationalStatus.STANDBY) }
    var locationNote by remember { mutableStateOf("") }
    var incidentNote by remember { mutableStateOf("") }
    var incidentLog by remember { mutableStateOf<List<String>>(emptyList()) }
    var showResourceDialog by remember { mutableStateOf(false) }
    var resourceType by remember { mutableStateOf("") }
    var resourceQty by remember { mutableStateOf("") }
    val isConnected by viewModel.commandClient.isConnected.collectAsState()

    LazyColumn(
        modifier = Modifier.fillMaxSize().background(NV.bg),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        // 標題
        item {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 6.dp)) {
                Icon(Icons.Default.Groups, contentDescription = null, tint = NV.green, modifier = Modifier.size(24.dp))
                Spacer(Modifier.width(8.dp))
                Text("班長面板", color = NV.white, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                UsarRoleBadge("SQUAD LEADER", NV.green)
            }
        }

        // 操作狀態
        item {
            UsarCard(title = "操作狀態") {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("當前狀態：", color = NV.textSecondary, fontSize = 12.sp)
                    val rows = OperationalStatus.entries.chunked(4)
                    rows.forEach { row ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            row.forEach { status ->
                                val selected = currentStatus == status
                                Box(
                                    modifier = Modifier
                                        .weight(1f)
                                        .clip(RoundedCornerShape(6.dp))
                                        .background(if (selected) status.color.copy(alpha = 0.2f) else NV.surface)
                                        .border(1.dp, if (selected) status.color else NV.cardBorder, RoundedCornerShape(6.dp))
                                        .clickable { currentStatus = status }
                                        .padding(vertical = 8.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        status.label,
                                        color = if (selected) status.color else NV.textSecondary,
                                        fontSize = 11.sp,
                                        fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal
                                    )
                                }
                            }
                        }
                    }
                    Spacer(Modifier.height(2.dp))
                    OutlinedTextField(
                        value = locationNote,
                        onValueChange = { locationNote = it },
                        label = { Text("目前位置 / 備註", fontSize = 12.sp) },
                        modifier = Modifier.fillMaxWidth(),
                        colors = outlinedFieldColors(),
                        shape = NVShape.card,
                        singleLine = true
                    )
                    Button(
                        onClick = {
                            if (isConnected) {
                                viewModel.sendQuickStatus(
                                    type = currentStatus.key,
                                    zone = locationNote
                                )
                            }
                        },
                        enabled = isConnected,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = currentStatus.color,
                            disabledContainerColor = NV.surface
                        ),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Default.Send, contentDescription = null, tint = Color.Black, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("回報狀態", color = Color.Black, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }

        // 任務列表
        item {
            UsarCard(title = "任務指派 (${tasks.filter { it.isActive }.size} 項待辦)") {
                if (tasks.isEmpty()) {
                    Text("目前無任務指派", color = NV.textSecondary, fontSize = 13.sp)
                } else {
                    tasks.take(5).forEach { task ->
                        TaskRow(
                            task = task,
                            onAccept = { viewModel.acceptTask(task.id) }
                        )
                        Divider(color = NV.divider, thickness = 0.5.dp, modifier = Modifier.padding(vertical = 4.dp))
                    }
                }
            }
        }

        // 醫療轉送追蹤
        item {
            UsarCard(title = "醫療轉送") {
                val patients by viewModel.localPatients.collectAsState()
                if (patients.isEmpty()) {
                    Text("尚無傷員回報", color = NV.textSecondary, fontSize = 13.sp)
                } else {
                    patients.take(3).forEach { p ->
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.LocalHospital, contentDescription = null, tint = NV.danger, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(6.dp))
                            Column(Modifier.weight(1f)) {
                                Text(p.patientId, color = NV.textPrimary, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                                Text(p.location.takeIf { it.isNotBlank() } ?: "位置未填", color = NV.textSecondary, fontSize = 11.sp)
                            }
                            Text(
                                if (p.breathingRate == -1) "無呼吸" else "呼吸 ${p.breathingRate}/min",
                                color = if (p.breathingRate == -1) NV.danger else NV.info,
                                fontSize = 11.sp
                            )
                        }
                    }
                }
            }
        }

        // 資源請求
        item {
            UsarCard(title = "資源請求") {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    OutlinedTextField(
                        value = resourceType,
                        onValueChange = { resourceType = it },
                        label = { Text("資源類型", fontSize = 12.sp) },
                        modifier = Modifier.weight(2f),
                        colors = outlinedFieldColors(),
                        shape = NVShape.card,
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = resourceQty,
                        onValueChange = { resourceQty = it },
                        label = { Text("數量", fontSize = 12.sp) },
                        modifier = Modifier.weight(1f),
                        colors = outlinedFieldColors(),
                        shape = NVShape.card,
                        singleLine = true
                    )
                }
                Spacer(Modifier.height(4.dp))
                Button(
                    onClick = {
                        if (resourceType.isNotBlank() && isConnected) {
                            viewModel.sendReinforcementRequest(
                                message = "資源請求：$resourceType x${resourceQty.ifEmpty{"1"}}",
                                location = locationNote
                            )
                            resourceType = ""; resourceQty = ""
                        }
                    },
                    enabled = resourceType.isNotBlank() && isConnected,
                    colors = ButtonDefaults.buttonColors(containerColor = NV.reinforce),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Icon(Icons.Default.Shield, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("發送請求", color = Color.White, fontWeight = FontWeight.Bold)
                }
            }
        }

        // 事件紀錄
        item {
            UsarCard(title = "事件紀錄 (${incidentLog.size})") {
                OutlinedTextField(
                    value = incidentNote,
                    onValueChange = { incidentNote = it },
                    label = { Text("輸入事件說明", fontSize = 12.sp) },
                    modifier = Modifier.fillMaxWidth(),
                    colors = outlinedFieldColors(),
                    shape = NVShape.card,
                    maxLines = 3
                )
                Spacer(Modifier.height(4.dp))
                Button(
                    onClick = {
                        if (incidentNote.isNotBlank()) {
                            val ts = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date())
                            incidentLog = listOf("[$ts] $incidentNote") + incidentLog
                            incidentNote = ""
                        }
                    },
                    enabled = incidentNote.isNotBlank(),
                    colors = ButtonDefaults.buttonColors(containerColor = NV.command),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("新增紀錄", color = Color.White, fontWeight = FontWeight.Bold)
                }
                if (incidentLog.isNotEmpty()) {
                    Spacer(Modifier.height(6.dp))
                    incidentLog.take(5).forEach { entry ->
                        Text(entry, color = NV.textSecondary, fontSize = 11.sp, fontFamily = FontFamily.Monospace,
                            modifier = Modifier.padding(vertical = 2.dp))
                    }
                }
            }
        }

        item { Spacer(Modifier.height(80.dp)) }
    }
}

// =====================================================
//  Sector Commander View
// =====================================================

@Composable
private fun SectorCommanderView(viewModel: LinkGuardViewModel) {
    val disasterSite by viewModel.disasterSite.collectAsState()
    val commandOrders by viewModel.commandOrders.collectAsState()
    val isConnected by viewModel.commandClient.isConnected.collectAsState()

    LazyColumn(
        modifier = Modifier.fillMaxSize().background(NV.bg),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 6.dp)) {
                Icon(Icons.Default.AccountBalance, contentDescription = null, tint = NV.command, modifier = Modifier.size(24.dp))
                Spacer(Modifier.width(8.dp))
                Text("區段指揮官", color = NV.white, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                UsarRoleBadge("SECTOR CDR", NV.command)
            }
        }

        // 區域狀態格
        item {
            UsarCard(title = "救援區域狀態") {
                val zones = disasterSite?.zones ?: emptyList()
                if (zones.isEmpty()) {
                    Text("尚未收到區域資訊（等待 HQ）", color = NV.textSecondary, fontSize = 13.sp)
                } else {
                    zones.forEach { zone ->
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(10.dp)
                                    .clip(RoundedCornerShape(3.dp))
                                    .background(zone.status.color)
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(zone.name, color = NV.textPrimary, fontSize = 13.sp, modifier = Modifier.weight(1f))
                            StatusBadge(zone.status.label, zone.status.color)
                        }
                    }
                }
            }
        }

        // 最近命令
        item {
            UsarCard(title = "指揮命令 (${commandOrders.size})") {
                commandOrders.take(3).forEach { order ->
                    Column(modifier = Modifier.padding(vertical = 4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            StatusBadge(order.priority.label, order.priority.color)
                            Spacer(Modifier.width(6.dp))
                            Text(order.title, color = NV.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                        }
                        Text(order.detail, color = NV.textSecondary, fontSize = 11.sp, modifier = Modifier.padding(start = 4.dp))
                    }
                    Divider(color = NV.divider, thickness = 0.5.dp)
                }
                if (commandOrders.isEmpty()) Text("無命令記錄", color = NV.textSecondary, fontSize = 13.sp)
            }
        }

        item { Spacer(Modifier.height(80.dp)) }
    }
}

// =====================================================
//  Worksite Manager View
// =====================================================

@Composable
private fun WorksiteManagerView(viewModel: LinkGuardViewModel) {
    val disasterSite by viewModel.disasterSite.collectAsState()
    val victims by viewModel.victims.collectAsState()
    val hazardReports by viewModel.hazardReports.collectAsState()

    LazyColumn(
        modifier = Modifier.fillMaxSize().background(NV.bg),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 6.dp)) {
                Icon(Icons.Default.Construction, contentDescription = null, tint = NV.reinforce, modifier = Modifier.size(24.dp))
                Spacer(Modifier.width(8.dp))
                Text("現場管理員", color = NV.white, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                UsarRoleBadge("WORKSITE MGR", NV.reinforce)
            }
        }

        // 樓層狀況
        item {
            UsarCard(title = "樓層狀況") {
                val floors = disasterSite?.floors ?: emptyList()
                if (floors.isEmpty()) {
                    Text("尚未收到樓層資訊", color = NV.textSecondary, fontSize = 13.sp)
                } else {
                    floors.forEach { floor ->
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Box(
                                modifier = Modifier.size(8.dp).clip(RoundedCornerShape(2.dp)).background(floor.condition.color)
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(floor.id, color = NV.textPrimary, fontSize = 13.sp, modifier = Modifier.weight(1f))
                            StatusBadge(floor.condition.label, floor.condition.color)
                        }
                    }
                }
            }
        }

        // 受困者摘要
        item {
            UsarCard(title = "受困者 (${victims.size})") {
                val onlineVictims = victims.filter { it.isOnline }
                val sosVictims = victims.filter { it.isSOS }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    StatBox("總計", "${victims.size}", NV.textPrimary, Modifier.weight(1f))
                    StatBox("在線", "${onlineVictims.size}", NV.green, Modifier.weight(1f))
                    StatBox("SOS", "${sosVictims.size}", NV.danger, Modifier.weight(1f))
                }
            }
        }

        // 危險標記
        item {
            UsarCard(title = "危險標記 (${hazardReports.size})") {
                if (hazardReports.isEmpty()) {
                    Text("無危險標記", color = NV.textSecondary, fontSize = 13.sp)
                } else {
                    hazardReports.take(4).forEach { report ->
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.Warning, contentDescription = null, tint = report.severityLevel.color, modifier = Modifier.size(14.dp))
                            Spacer(Modifier.width(6.dp))
                            Text(report.hazard?.label ?: report.hazardType, color = NV.textPrimary, fontSize = 12.sp, modifier = Modifier.weight(1f))
                            Text(report.zone, color = NV.textSecondary, fontSize = 11.sp)
                        }
                    }
                }
            }
        }

        item { Spacer(Modifier.height(80.dp)) }
    }
}

// =====================================================
//  Shared helpers
// =====================================================

@Composable
private fun UsarCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(NVShape.card)
            .background(NV.card)
            .border(1.dp, NV.cardBorder, NVShape.card)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(title, color = NV.textSecondary, fontSize = 11.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
        content()
    }
}

@Composable
private fun UsarRoleBadge(label: String, color: Color) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(color.copy(alpha = 0.12f))
            .border(1.dp, color.copy(alpha = 0.5f), RoundedCornerShape(20.dp))
            .padding(horizontal = 10.dp, vertical = 4.dp)
    ) {
        Text(label, color = color, fontSize = 10.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun StatusBadge(label: String, color: Color) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(4.dp))
            .background(color.copy(alpha = 0.12f))
            .border(0.5.dp, color.copy(alpha = 0.35f), RoundedCornerShape(4.dp))
            .padding(horizontal = 6.dp, vertical = 2.dp)
    ) {
        Text(label, color = color, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
    }
}

@Composable
private fun StatBox(label: String, value: String, color: Color, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .background(color.copy(alpha = 0.08f))
            .padding(vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(value, color = color, fontSize = 20.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
        Text(label, color = NV.textSecondary, fontSize = 11.sp)
    }
}

@Composable
private fun TaskRow(task: TaskAssignment, onAccept: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f)) {
            Text(task.title, color = NV.textPrimary, fontSize = 13.sp, fontWeight = FontWeight.Medium)
            Text(task.detail.takeIf { it.isNotBlank() } ?: task.zone, color = NV.textSecondary, fontSize = 11.sp)
        }
        Spacer(Modifier.width(8.dp))
        if (task.taskStatus == TaskStatus.PENDING) {
            TextButton(
                onClick = onAccept,
                colors = ButtonDefaults.textButtonColors(contentColor = NV.green)
            ) {
                Text("接受", fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }
        } else {
            StatusBadge(task.taskStatus.label, task.taskStatus.color)
        }
    }
}

@Composable
private fun outlinedFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = NV.green,
    unfocusedBorderColor = NV.cardBorder,
    focusedTextColor = NV.textPrimary,
    unfocusedTextColor = NV.textPrimary,
    focusedLabelColor = NV.green,
    unfocusedLabelColor = NV.textSecondary,
    cursorColor = NV.green
)
