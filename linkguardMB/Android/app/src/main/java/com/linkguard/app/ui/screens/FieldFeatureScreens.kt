package com.linkguard.app.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationServices
import com.linkguard.app.model.*
import com.linkguard.app.ui.theme.NV
import com.linkguard.app.ui.theme.NVShape
import com.linkguard.app.viewmodel.LinkGuardViewModel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// =====================================================
//  前線災情檢視（唯讀，來自 HQ）
// =====================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FieldDisasterScreen(viewModel: LinkGuardViewModel) {
    val site by viewModel.disasterSite.collectAsState()
    val hazardReports by viewModel.hazardReports.collectAsState()
    var showHazardDialog by remember { mutableStateOf(false) }

    if (site == null) {
        Column(modifier = Modifier.fillMaxSize()) {
            Text("全區災情概況", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = NV.white,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp))
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Default.Domain, contentDescription = "Disaster info",
                        modifier = Modifier.size(64.dp), tint = NV.textSecondary.copy(alpha = 0.5f))
                    Spacer(modifier = Modifier.height(16.dp))
                    Text("尚未收到災情資訊", color = NV.textSecondary, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                    Spacer(modifier = Modifier.height(4.dp))
                    Text("連線指揮中心後將自動接收", color = NV.textSecondary.copy(alpha = 0.7f), fontSize = 14.sp)
                }
            }
        }
    } else {
        val s = site!!
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Text("全區災情概況", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white,
                    modifier = Modifier.padding(top = 12.dp))
            }
            // 建物資訊
            if (s.buildingName.isNotEmpty() || s.address.isNotEmpty()) {
                item {
                    InfoCard("建物資訊") {
                        if (s.buildingName.isNotEmpty()) FieldInfoRow("名稱", s.buildingName)
                        if (s.address.isNotEmpty()) FieldInfoRow("地址", s.address)
                        FieldInfoRow("倒塾類型", s.collapseType.label)
                        FieldInfoRow("地上樓層", "${s.aboveGroundFloors}F")
                        if (s.undergroundFloors > 0) FieldInfoRow("地下樓層", "B${s.undergroundFloors}F")
                    }
                }
            }
            // 樓層
            if (s.floors.isNotEmpty()) {
                item {
                    InfoCard("樓層狀態") {
                        s.floors.forEach { f ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("${f.id}F", fontWeight = FontWeight.Bold, color = NV.white,
                                    modifier = Modifier.width(40.dp))
                                Text(f.condition.label, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                                    color = f.condition.color,
                                    modifier = Modifier
                                        .background(f.condition.color.copy(alpha = 0.15f), RoundedCornerShape(4.dp))
                                        .padding(horizontal = 6.dp, vertical = 2.dp))
                                if (f.note.isNotEmpty()) {
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text(f.note, fontSize = 10.sp, color = NV.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            // 分區
            if (s.zones.isNotEmpty()) {
                item {
                    InfoCard("救援分區") {
                        s.zones.forEach { z ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(z.name, fontWeight = FontWeight.Bold, color = NV.white)
                                Spacer(modifier = Modifier.weight(1f))
                                Text(z.status.label, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                                    color = z.status.color,
                                    modifier = Modifier
                                        .background(z.status.color.copy(alpha = 0.15f), RoundedCornerShape(4.dp))
                                        .padding(horizontal = 6.dp, vertical = 2.dp))
                            }
                        }
                    }
                }
            }
            // 危害
            if (s.hazards.isNotEmpty()) {
                item {
                    InfoCard("已知危害") {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            s.hazards.forEach { h ->
                                Text("${h.icon} ${h.label}", fontSize = 11.sp, color = NV.danger,
                                    modifier = Modifier
                                        .background(NV.danger.copy(alpha = 0.15f), RoundedCornerShape(6.dp))
                                        .padding(horizontal = 8.dp, vertical = 4.dp))
                            }
                        }
                    }
                }
            }
            // 集結點
            if (s.rallyPoint.isNotEmpty()) {
                item { InfoCard("集結點") { Text(s.rallyPoint, color = NV.white, fontWeight = FontWeight.Bold) } }
            }

            // 回報危險按鈕
            item {
                val wifiConnected by viewModel.commandClient.isConnected.collectAsState()
                Button(
                    onClick = { showHazardDialog = true },
                    enabled = wifiConnected,
                    colors = ButtonDefaults.buttonColors(containerColor = NV.danger),
                    modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp),
                    shape = RoundedCornerShape(8.dp)
                ) {
                    Icon(Icons.Default.Warning, contentDescription = "Report hazard", modifier = Modifier.size(22.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("回報危險", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                }
            }

            // 已回報危險
            if (hazardReports.isNotEmpty()) {
                item { Text("已回報危險 (${hazardReports.size})", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = NV.textSecondary) }
                items(hazardReports.take(5), key = { it.id }) { hazard ->
                    CardContainer(borderColor = hazard.severityLevel.color) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Warning, contentDescription = null, tint = NV.warning, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(8.dp))
                            Column(modifier = Modifier.weight(1f)) {
                                Text(hazard.hazard?.label ?: hazard.hazardType, color = NV.white, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                                if (hazard.description.isNotEmpty()) {
                                    Text(hazard.description, color = NV.textSecondary, fontSize = 12.sp, maxLines = 1)
                                }
                                Text("${hazard.reporterName} · ${if (hazard.zone.isEmpty()) "未知區域" else hazard.zone} · ${hazard.timeText}",
                                    color = NV.textSecondary, fontSize = 11.sp)
                            }
                            Text(hazard.severityLevel.label, color = hazard.severityLevel.color, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }

    // 危險回報 Dialog
    if (showHazardDialog) {
        var selectedType by remember { mutableStateOf(HazardType.GAS_LEAK) }
        var selectedSeverity by remember { mutableStateOf(HazardSeverity.MEDIUM) }
        var zone by remember { mutableStateOf("") }
        var description by remember { mutableStateOf("") }

        AlertDialog(
            onDismissRequest = { showHazardDialog = false },
            title = { Text("回報危險", fontWeight = FontWeight.Bold) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("危害類型", fontSize = 12.sp, color = NV.textSecondary)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        HazardType.entries.take(3).forEach { type ->
                            FilterChip(
                                selected = selectedType == type,
                                onClick = { selectedType = type },
                                label = { Text(type.label, fontSize = 11.sp, color = NV.white) }
                            )
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        HazardType.entries.drop(3).forEach { type ->
                            FilterChip(
                                selected = selectedType == type,
                                onClick = { selectedType = type },
                                label = { Text(type.label, fontSize = 11.sp, color = NV.white) }
                            )
                        }
                    }
                    Text("嚴重程度", fontSize = 12.sp, color = NV.textSecondary)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        HazardSeverity.entries.forEach { sev ->
                            FilterChip(
                                selected = selectedSeverity == sev,
                                onClick = { selectedSeverity = sev },
                                label = { Text(sev.label, fontSize = 11.sp, color = NV.white) }
                            )
                        }
                    }
                    OutlinedTextField(value = zone, onValueChange = { zone = it },
                        label = { Text("區域") }, modifier = Modifier.fillMaxWidth(),
                        colors = OutlinedTextFieldDefaults.colors(focusedTextColor = NV.white, unfocusedTextColor = NV.white))
                    OutlinedTextField(value = description, onValueChange = { description = it },
                        label = { Text("描述") }, modifier = Modifier.fillMaxWidth(), maxLines = 3,
                        colors = OutlinedTextFieldDefaults.colors(focusedTextColor = NV.white, unfocusedTextColor = NV.white))
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.reportHazard(selectedType, description, zone, selectedSeverity)
                    showHazardDialog = false
                }) { Text("送出", color = NV.green) }
            },
            dismissButton = {
                TextButton(onClick = { showHazardDialog = false }) { Text("取消", color = NV.textSecondary) }
            },
            containerColor = NV.card
        )
    }
}

// =====================================================
//  前線通訊頻道
// =====================================================

@Composable
fun FieldChatScreen(viewModel: LinkGuardViewModel) {
    val messages by viewModel.chatMessages.collectAsState()
    val nodeStatus by viewModel.nodeStatus.collectAsState()
    var draft by remember { mutableStateOf("") }
    val listState = rememberLazyListState()

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1)
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // 標題
        Text("全域通訊頻道", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = NV.white,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp))

        // 連線狀態
        val isConnected by viewModel.commandClient.isConnected.collectAsState()
        if (!isConnected) {
            Row(
                modifier = Modifier.fillMaxWidth().background(NV.danger).padding(6.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Default.WifiOff, contentDescription = null, tint = NV.white, modifier = Modifier.size(14.dp))
                Spacer(modifier = Modifier.width(4.dp))
                Text("未連線指揮中心", color = NV.white, fontSize = 12.sp)
            }
        }

        // 訊息列表
        LazyColumn(
            state = listState,
            modifier = Modifier.weight(1f).padding(horizontal = 12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            contentPadding = PaddingValues(vertical = 8.dp)
        ) {
            items(messages, key = { it.id }) { msg ->
                val isSelf = msg.senderID == nodeStatus.nodeID
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = if (isSelf) Alignment.End else Alignment.Start
                ) {
                    val isHQ = msg.senderName.contains("HQ") || msg.senderID == "HQ"
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(msg.senderName, fontSize = 10.sp, color = NV.textSecondary)
                        if (isHQ) {
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("HQ", fontSize = 9.sp, fontWeight = FontWeight.Bold,
                                color = NV.white,
                                modifier = Modifier.background(NV.command.copy(alpha = 0.5f), RoundedCornerShape(4.dp))
                                    .padding(horizontal = 4.dp, vertical = 1.dp))
                        }
                    }
                    Box(
                        modifier = Modifier.background(
                            when {
                                isSelf -> NV.green.copy(alpha = 0.2f)
                                isHQ -> NV.command.copy(alpha = 0.15f)
                                else -> NV.textSecondary.copy(alpha = 0.15f)
                            },
                            NVShape.card
                        ).padding(horizontal = 12.dp, vertical = 8.dp)
                    ) {
                        Text(msg.content, color = NV.white, fontSize = 14.sp)
                    }
                }
            }
        }

        Divider(color = NV.cardBorder)

        // 預設訊息模板
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .padding(horizontal = 12.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            presetMessages.forEach { preset ->
                OutlinedButton(
                    onClick = { viewModel.sendChat(preset.text) },
                    enabled = isConnected,
                    border = BorderStroke(1.dp, NV.command.copy(alpha = 0.5f)),
                    contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp),
                    shape = NVShape.card
                ) {
                    Text("${preset.icon} ${preset.text}", color = NV.command, fontSize = 12.sp)
                }
            }
        }

        // 輸入列
        val personnel by viewModel.personnelAssignments.collectAsState()
        val team by viewModel.teamMembers.collectAsState()
        var showMentionPicker by remember { mutableStateOf(false) }
        Row(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedTextField(
                value = draft, onValueChange = { draft = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("輸入訊息…", color = NV.textSecondary.copy(alpha = 0.6f)) },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = NV.white, unfocusedTextColor = NV.white,
                    focusedBorderColor = NV.command, unfocusedBorderColor = NV.cardBorder,
                    cursorColor = NV.command
                ),
                maxLines = 3
            )
            Spacer(modifier = Modifier.width(4.dp))
            Box {
                IconButton(
                    onClick = { showMentionPicker = !showMentionPicker },
                    enabled = (personnel.isNotEmpty() || team.isNotEmpty()) && isConnected
                ) {
                    Icon(Icons.Default.AlternateEmail, contentDescription = "@提及", tint = NV.command)
                }
                DropdownMenu(
                    expanded = showMentionPicker,
                    onDismissRequest = { showMentionPicker = false }
                ) {
                    personnel.forEach { p ->
                        val tag = p.nickname?.takeIf { it.isNotBlank() } ?: p.name
                        DropdownMenuItem(
                            text = { Text("$tag  (${p.id.takeLast(6)})") },
                            onClick = {
                                draft = if (draft.endsWith(" ") || draft.isEmpty()) draft + "@$tag " else "$draft @$tag "
                                showMentionPicker = false
                            }
                        )
                    }
                    team.forEach { m ->
                        val tag = m.nickname?.takeIf { it.isNotBlank() } ?: m.id
                        DropdownMenuItem(
                            text = { Text("[隊] $tag  (${m.id.takeLast(6)})") },
                            onClick = {
                                draft = if (draft.endsWith(" ") || draft.isEmpty()) draft + "@$tag " else "$draft @$tag "
                                showMentionPicker = false
                            }
                        )
                    }
                }
            }
            Spacer(modifier = Modifier.width(4.dp))
            IconButton(
                onClick = { viewModel.sendChat(draft); draft = "" },
                enabled = draft.isNotBlank() && isConnected,
                modifier = Modifier.defaultMinSize(minHeight = 56.dp, minWidth = 56.dp)
            ) {
                Icon(Icons.Default.Send, contentDescription = "Send message", tint = NV.command, modifier = Modifier.size(28.dp))
            }
        }
    }
}

// =====================================================
//  前線通知中心（PWS + 會報 + 個人通知 + 人員配置）
// =====================================================

@Composable
fun FieldNotificationScreen(viewModel: LinkGuardViewModel) {
    val pwsAlerts by viewModel.pwsAlerts.collectAsState()
    val briefings by viewModel.briefings.collectAsState()
    val notifications by viewModel.personalNotifications.collectAsState()
    val assignments by viewModel.personnelAssignments.collectAsState()

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item { Text("前線動態通知", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = NV.white,
            modifier = Modifier.padding(top = 12.dp)) }

        // PWS 警報
        if (pwsAlerts.isNotEmpty()) {
            item { Text("PWS 警報", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = NV.danger) }
            items(pwsAlerts, key = { it.id }) { alert ->
                InfoCard(alert.title) {
                    Row {
                        Text(alert.alertType.label, fontSize = 11.sp, color = alert.severity.color,
                            modifier = Modifier.background(alert.severity.color.copy(alpha = 0.15f), RoundedCornerShape(4.dp))
                                .padding(horizontal = 6.dp, vertical = 2.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(alert.severity.label, fontSize = 11.sp, color = alert.severity.color)
                        Spacer(modifier = Modifier.weight(1f))
                        if (alert.isActive) {
                            Text("活躍", fontSize = 9.sp, color = NV.white, fontWeight = FontWeight.Bold,
                                modifier = Modifier.background(NV.danger, RoundedCornerShape(4.dp))
                                    .padding(horizontal = 4.dp, vertical = 2.dp))
                        }
                    }
                    Text(alert.content, fontSize = 12.sp, color = NV.textSecondary)
                }
            }
        }

        // 會報
        if (briefings.isNotEmpty()) {
            item { Text("會報", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = NV.info) }
            items(briefings, key = { it.id }) { report ->
                InfoCard(report.title) {
                    Row {
                        Text(report.type.label, fontSize = 11.sp, color = NV.info,
                            modifier = Modifier.background(NV.info.copy(alpha = 0.15f), RoundedCornerShape(4.dp))
                                .padding(horizontal = 6.dp, vertical = 2.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("by ${report.author}", fontSize = 11.sp, color = NV.textSecondary)
                    }
                    report.sections.forEach { s ->
                        Text(s.title, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = NV.white)
                        Text(s.content, fontSize = 11.sp, color = NV.textSecondary)
                    }
                }
            }
        }

        // 個人通知
        item { Text("個人通知", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = NV.warning) }
        if (notifications.isEmpty()) {
            item {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Icon(Icons.Default.NotificationsNone, contentDescription = null,
                        tint = NV.textSecondary.copy(alpha = 0.5f), modifier = Modifier.size(64.dp))
                    Spacer(modifier = Modifier.height(12.dp))
                    Text("無通知", fontSize = 16.sp, color = NV.textSecondary, fontWeight = FontWeight.SemiBold)
                }
            }
        }
        items(notifications, key = { it.id }) { notif ->
            InfoCard(notif.title) {
                Text(notif.content, fontSize = 12.sp, color = NV.textSecondary)
                if (!notif.isRead) {
                    TextButton(onClick = { viewModel.markNotificationAsRead(notif.id) }) {
                        Text("標為已讀", fontSize = 11.sp)
                    }
                }
            }
        }

        // 人員配置
        if (assignments.isNotEmpty()) {
            item { Text("人員配置", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = NV.info) }
            items(assignments, key = { it.id }) { a ->
                InfoCard(a.name) {
                    Row {
                        Text("${a.role.icon} ${a.role.label}", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = NV.info,
                            modifier = Modifier.background(NV.info.copy(alpha = 0.15f), RoundedCornerShape(4.dp))
                                .padding(horizontal = 6.dp, vertical = 2.dp))
                        if (a.assignedZone.isNotEmpty()) { Spacer(modifier = Modifier.width(6.dp)); Text(a.assignedZone, fontSize = 11.sp, color = NV.textSecondary) }
                        if (a.assignedFloor.isNotEmpty()) { Spacer(modifier = Modifier.width(6.dp)); Text("${a.assignedFloor}F", fontSize = 11.sp, color = NV.textSecondary) }
                    }
                }
            }
        }
    }
}

// =====================================================
//  共用元件
// =====================================================

@Composable
fun InfoCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(6.dp, NVShape.card, ambientColor = Color.Black.copy(alpha = 0.5f), spotColor = Color.Black.copy(alpha = 0.3f))
            .clip(NVShape.card)
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        NV.card,
                        Color(0xFF131920)
                    )
                )
            )
            .border(
                width = 1.dp,
                brush = Brush.verticalGradient(
                    colors = listOf(
                        NV.cardBorder.copy(alpha = 0.6f),
                        NV.cardBorder.copy(alpha = 0.2f)
                    )
                ),
                shape = NVShape.card
            )
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(title, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = NV.white)
        content()
    }
}

@Composable
fun FieldInfoRow(label: String, value: String) {
    Row {
        Text(label, fontSize = 12.sp, color = NV.textSecondary, modifier = Modifier.width(80.dp))
        Text(value, fontSize = 12.sp, color = NV.white, fontWeight = FontWeight.Bold)
    }
}

// =====================================================
//  傷員回報表單（對應 iOS PatientFormView）
// =====================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PatientFormScreen(viewModel: LinkGuardViewModel) {
    val context = LocalContext.current
    var location by remember { mutableStateOf("") }
    var breathingRateText by remember { mutableStateOf("") }
    var capillaryRefillText by remember { mutableStateOf("") }
    var canFollowCommands by remember { mutableStateOf(false) }
    var notes by remember { mutableStateOf("") }
    var gpsLat by remember { mutableStateOf<Double?>(null) }
    var gpsLon by remember { mutableStateOf<Double?>(null) }
    var showConfirmation by remember { mutableStateOf(false) }
    var gpsText by remember { mutableStateOf("GPS 定位中…") }

    // GPS 取得
    LaunchedEffect(Unit) {
        val hasPerm = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        if (hasPerm) {
            val fusedClient = LocationServices.getFusedLocationProviderClient(context)
            fusedClient.lastLocation.addOnSuccessListener { loc ->
                if (loc != null) {
                    gpsLat = loc.latitude
                    gpsLon = loc.longitude
                    gpsText = "%.5f, %.5f".format(loc.latitude, loc.longitude)
                }
            }
        } else {
            gpsText = "缺少定位權限"
        }
    }

    val isFormValid = location.isNotBlank() &&
            breathingRateText.toIntOrNull() != null &&
            capillaryRefillText.toDoubleOrNull() != null

    Box(modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Text("傷員回報", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = NV.white,
                    modifier = Modifier.padding(top = 12.dp))
            }

            // 自動生成 ID
            item {
                InfoCard("自動生成") {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("傷員 ID", fontSize = 12.sp, color = NV.textSecondary,
                            modifier = Modifier.width(80.dp))
                        Text("P${System.currentTimeMillis() / 1000}",
                            fontSize = 12.sp, color = NV.white, fontWeight = FontWeight.Bold)
                    }
                }
            }

            // 傷員資訊
            item {
                InfoCard("傷員資訊") {
                    OutlinedTextField(
                        value = location,
                        onValueChange = { location = it },
                        label = { Text("位置（例：A區 3F 走廊）") },
                        leadingIcon = { Icon(Icons.Default.LocationOn, null, tint = NV.command) },
                        modifier = Modifier.fillMaxWidth(),
                        colors = fieldColors(),
                        singleLine = true
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedTextField(
                        value = breathingRateText,
                        onValueChange = { breathingRateText = it },
                        label = { Text("呼吸速率（次/分，-1=無呼吸）") },
                        leadingIcon = {
                            Icon(Icons.Default.Air, null,
                                tint = if (breathingRateText == "-1") NV.danger else NV.info)
                        },
                        modifier = Modifier.fillMaxWidth(),
                        colors = fieldColors(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedTextField(
                        value = capillaryRefillText,
                        onValueChange = { capillaryRefillText = it },
                        label = { Text("微血管充盈時間（秒，-1=無脈搏）") },
                        leadingIcon = {
                            Icon(Icons.Default.MonitorHeart, null,
                                tint = if (capillaryRefillText == "-1") NV.danger else NV.info)
                        },
                        modifier = Modifier.fillMaxWidth(),
                        colors = fieldColors(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true
                    )
                }
            }

            // 意識狀態
            item {
                InfoCard("意識狀態") {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            if (canFollowCommands) Icons.Default.Psychology else Icons.Default.Cancel,
                            contentDescription = null,
                            tint = if (canFollowCommands) NV.green else NV.danger
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text("可遵從指令", fontSize = 14.sp, color = NV.white)
                            Text(
                                if (canFollowCommands) "意識清醒" else "意識不清",
                                fontSize = 11.sp, color = NV.textSecondary
                            )
                        }
                        Switch(
                            checked = canFollowCommands,
                            onCheckedChange = { canFollowCommands = it },
                            colors = SwitchDefaults.colors(
                                checkedThumbColor = NV.green,
                                checkedTrackColor = NV.green.copy(alpha = 0.3f)
                            )
                        )
                    }
                }
            }

            // 語音輸入
            item {
                InfoCard("語音輸入") {
                    Column {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text(
                                "長按麥克風錄音，放開後自動上傳轉錄。\n轉錄結果會自動填入位置欄位。",
                                fontSize = 11.sp,
                                color = NV.textSecondary,
                                modifier = Modifier.weight(1f)
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            VoiceInputButton(
                                serverHost = viewModel.commandClient.serverHost,
                                onTranscribed = { text ->
                                    location = if (location.isEmpty()) text else "$location $text"
                                }
                            )
                        }
                    }
                }
            }

            // 備註
            item {
                InfoCard("補充說明") {
                    OutlinedTextField(
                        value = notes,
                        onValueChange = { notes = it },
                        label = { Text("備註（選填）") },
                        modifier = Modifier.fillMaxWidth(),
                        colors = fieldColors(),
                        minLines = 2, maxLines = 4
                    )
                }
            }

            // GPS
            item {
                InfoCard("GPS 座標（自動取得）") {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            if (gpsLat != null) Icons.Default.LocationOn else Icons.Default.LocationDisabled,
                            contentDescription = null,
                            tint = if (gpsLat != null) NV.green else NV.textSecondary
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(gpsText, fontSize = 12.sp, color = NV.textSecondary)
                    }
                }
            }

            // 送出按鈕
            item {
                Button(
                    onClick = {
                        val breathingRate = breathingRateText.toIntOrNull() ?: return@Button
                        val capillaryRefill = capillaryRefillText.toDoubleOrNull() ?: return@Button

                        val report = PatientReport(
                            location = location.trim(),
                            breathingRate = breathingRate,
                            capillaryRefill = capillaryRefill,
                            canFollowCommands = canFollowCommands,
                            gpsLat = gpsLat,
                            gpsLon = gpsLon,
                            notes = notes.trim()
                        )
                        viewModel.submitPatientReport(report)

                        // 清空
                        location = ""
                        breathingRateText = ""
                        capillaryRefillText = ""
                        canFollowCommands = false
                        notes = ""
                        showConfirmation = true
                    },
                    enabled = isFormValid,
                    modifier = Modifier
                        .fillMaxWidth()
                        .defaultMinSize(minHeight = 56.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (isFormValid) NV.danger else NV.card,
                        disabledContainerColor = NV.card
                    ),
                    shape = RoundedCornerShape(8.dp)
                ) {
                    Icon(Icons.Default.Send, contentDescription = "Submit", tint = NV.white, modifier = Modifier.size(22.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("送出傷員回報", color = NV.white, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                }
            }

            item { Spacer(modifier = Modifier.height(16.dp)) }
        }

        // 確認提示
        AnimatedVisibility(
            visible = showConfirmation,
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 24.dp),
            enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
        ) {
            Surface(
                shape = RoundedCornerShape(24.dp),
                color = NV.green.copy(alpha = 0.15f),
                border = BorderStroke(1.dp, NV.green.copy(alpha = 0.3f))
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.CheckCircle, null, tint = NV.green)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("傷員回報已送出", color = NV.white, fontSize = 14.sp)
                }
            }
        }

        LaunchedEffect(showConfirmation) {
            if (showConfirmation) {
                kotlinx.coroutines.delay(2500)
                showConfirmation = false
            }
        }
    }
}

@Composable
private fun fieldColors() = OutlinedTextFieldDefaults.colors(
    focusedTextColor = NV.white,
    unfocusedTextColor = NV.white,
    focusedBorderColor = NV.blue,
    unfocusedBorderColor = NV.cardBorder,
    focusedLabelColor = NV.blue,
    unfocusedLabelColor = NV.textSecondary,
    cursorColor = NV.blue,
    focusedLeadingIconColor = NV.blue,
    unfocusedLeadingIconColor = NV.textSecondary
)

// =====================================================
//  指揮決策顯示（對應 iOS DecisionView）
// =====================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DecisionScreen(viewModel: LinkGuardViewModel) {
    val decisions by viewModel.decisions.collectAsState()
    val readStatuses by viewModel.readStatuses.collectAsState()
    val context = LocalContext.current
    var previousCount by remember { mutableIntStateOf(decisions.size) }

    // 新決策震動
    LaunchedEffect(decisions.size) {
        if (decisions.size > previousCount && previousCount > 0) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vm = context.getSystemService(VibratorManager::class.java)
                    vm?.defaultVibrator?.vibrate(
                        VibrationEffect.createOneShot(200, VibrationEffect.DEFAULT_AMPLITUDE)
                    )
                } else {
                    @Suppress("DEPRECATION")
                    val v = context.getSystemService(Vibrator::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        v?.vibrate(VibrationEffect.createOneShot(200, VibrationEffect.DEFAULT_AMPLITUDE))
                    }
                }
            } catch (_: Exception) { }
        }
        previousCount = decisions.size
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Text("指揮決策", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white,
            modifier = Modifier.padding(start = 16.dp, top = 12.dp, end = 16.dp))

        if (decisions.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Default.Inbox, contentDescription = "No decisions",
                        modifier = Modifier.size(64.dp), tint = NV.textSecondary.copy(alpha = 0.5f))
                    Spacer(modifier = Modifier.height(16.dp))
                    Text("尚未收到指揮決策", color = NV.textSecondary, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                    Spacer(modifier = Modifier.height(4.dp))
                    Text("當指揮中心發布決策後，將顯示於此處",
                        color = NV.textSecondary.copy(alpha = 0.7f), fontSize = 14.sp)
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                items(decisions, key = { it.id }) { decision ->
                    DecisionCard(
                        decision = decision,
                        readStatus = readStatuses[decision.decisionId]
                    )
                }
                item { Spacer(modifier = Modifier.height(16.dp)) }
            }
        }
    }
}

@Composable
private fun DecisionCard(decision: HQDecision, readStatus: Pair<Int, Int>? = null) {
    var isExpanded by remember { mutableStateOf(true) }
    val receivedTime = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
        .format(Date(decision.receivedAt))
    val triggerLabel = when (decision.trigger) {
        "patient" -> "傷員回報觸發"
        "voice"   -> "語音回報觸發"
        "manual"  -> "手動觸發"
        "hq_request" -> "AI 建議觸發"
        "llm", "ai" -> "AI 自動觸發"
        else      -> if (decision.trigger.isNotEmpty()) "觸發: ${decision.trigger}" else ""
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = NV.card),
        border = BorderStroke(1.dp, NV.cardBorder.copy(alpha = 0.5f)),
        shape = NVShape.card,
        elevation = CardDefaults.cardElevation(defaultElevation = 6.dp)
    ) {
        Column {
            // 標題列
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { isExpanded = !isExpanded }
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Default.Campaign, null, tint = NV.command)
                Spacer(modifier = Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("指揮決策", fontSize = 12.sp, color = NV.textSecondary)
                        if (triggerLabel.isNotEmpty()) {
                            Text(triggerLabel, fontSize = 10.sp, color = NV.info,
                                modifier = Modifier
                                    .background(NV.info.copy(alpha = 0.15f), RoundedCornerShape(8.dp))
                                    .padding(horizontal = 6.dp, vertical = 1.dp))
                        }
                    }
                    Text("收到：$receivedTime  ·  發布：${decision.timestamp}",
                        fontSize = 10.sp, color = NV.textSecondary)
                }
                Icon(
                    if (isExpanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    null, tint = NV.textSecondary
                )
            }

            Divider(color = NV.cardBorder, modifier = Modifier.padding(horizontal = 16.dp))

            // 決策文字
            Text(
                decision.decision,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = NV.command,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp)
            )

            // 傷員列表
            AnimatedVisibility(
                visible = isExpanded && decision.patients.isNotEmpty(),
                enter = expandVertically() + fadeIn(),
                exit = shrinkVertically() + fadeOut()
            ) {
                Column {
                    Divider(color = NV.cardBorder, modifier = Modifier.padding(horizontal = 16.dp))
                    Text("傷員優先順序 (${decision.patients.size} 人)",
                        fontSize = 11.sp, color = NV.textSecondary,
                        modifier = Modifier.padding(start = 16.dp, top = 10.dp))
                    decision.patients.forEach { patient ->
                        PatientEntryRow(patient)
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                }
            }

            // 氣象快照
            AnimatedVisibility(
                visible = isExpanded && decision.weather != null,
                enter = expandVertically() + fadeIn(),
                exit = shrinkVertically() + fadeOut()
            ) {
                val w = decision.weather!!
                Column {
                    Divider(color = NV.cardBorder, modifier = Modifier.padding(horizontal = 16.dp))
                    Row(
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        w.temp?.let {
                            Text("%.1f°C".format(it), fontSize = 11.sp, color = NV.textSecondary)
                        }
                        w.humidity?.let {
                            Text("%.0f%%".format(it), fontSize = 11.sp, color = NV.textSecondary)
                        }
                        w.wind?.let {
                            Text("%.1fm/s".format(it), fontSize = 11.sp, color = NV.textSecondary)
                        }
                        w.rainfall?.let { if (it > 0) {
                            Text("%.1fmm".format(it), fontSize = 11.sp, color = NV.textSecondary)
                        }}
                    }
                }
            }

            // 已讀回條
            readStatus?.let { (total, readCount) ->
                if (total > 0) {
                    Divider(color = NV.cardBorder, modifier = Modifier.padding(horizontal = 16.dp))
                    Row(
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            Icons.Default.CheckCircle, null,
                            tint = if (readCount >= total) NV.green else NV.textSecondary,
                            modifier = Modifier.size(16.dp)
                        )
                        Text("已讀 $readCount/$total",
                            fontSize = 11.sp, color = NV.textSecondary)
                        LinearProgressIndicator(
                            progress = readCount.toFloat() / total.toFloat(),
                            modifier = Modifier.weight(1f).height(4.dp),
                            color = if (readCount >= total) NV.green else NV.command,
                            trackColor = NV.cardBorder
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PatientEntryRow(patient: PatientDecisionEntry) {
    val priorityColor = when (patient.priority.lowercase()) {
        "red", "紅" -> NV.danger
        "black", "黑" -> Color(0xFF444444)
        "yellow", "黃" -> NV.warning
        "green", "綠" -> NV.green
        else -> NV.textSecondary
    }
    val priorityLabel = when (patient.priority.lowercase()) {
        "red", "紅" -> "紅"
        "black", "黑" -> "黑"
        "yellow", "黃" -> "黃"
        "green", "綠" -> "綠"
        else -> patient.priority
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            priorityLabel,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = NV.white,
            modifier = Modifier
                .background(priorityColor, RoundedCornerShape(4.dp))
                .padding(horizontal = 8.dp, vertical = 2.dp)
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(patient.id, fontSize = 12.sp, color = NV.white, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.width(8.dp))
        Text(patient.location, fontSize = 11.sp, color = NV.textSecondary,
            modifier = Modifier.weight(1f))
        if (patient.reason.isNotEmpty()) {
            Text(patient.reason, fontSize = 10.sp, color = NV.textSecondary)
        }
    }
}
