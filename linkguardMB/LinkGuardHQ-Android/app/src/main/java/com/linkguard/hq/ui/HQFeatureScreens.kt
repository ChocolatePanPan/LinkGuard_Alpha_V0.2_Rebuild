@file:OptIn(ExperimentalMaterial3Api::class)
package com.linkguard.hq.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.res.stringResource
import coil.compose.AsyncImage
import com.linkguard.hq.R
import com.linkguard.hq.model.*
import com.linkguard.hq.viewmodel.HQViewModel

// =====================================================
//  災情狀態 Tab
// =====================================================

@Composable
fun HQDisasterTab(viewModel: HQViewModel) {
    val site by viewModel.disasterSite.collectAsState()
    var buildingName by remember { mutableStateOf(site.buildingName) }
    var address by remember { mutableStateOf(site.address) }
    var rallyPoint by remember { mutableStateOf(site.rallyPoint) }
    var noteText by remember { mutableStateOf(site.note) }
    var selectedCollapse by remember { mutableStateOf(site.collapseType) }
    var aboveFloors by remember { mutableStateOf(site.aboveGroundFloors.toString()) }
    var belowFloors by remember { mutableStateOf(site.undergroundFloors.toString()) }
    var showAddEntryPoint by remember { mutableStateOf(false) }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text(stringResource(R.string.disaster_status), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white)
        }
        // 建物資訊
        item {
            SectionCard(stringResource(R.string.building_info)) {
                OutlinedTextField(value = buildingName, onValueChange = { buildingName = it },
                    label = { Text(stringResource(R.string.label_building_name)) }, modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors())
                Spacer(modifier = Modifier.height(8.dp))
                OutlinedTextField(value = address, onValueChange = { address = it },
                    label = { Text(stringResource(R.string.label_address)) }, modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors())
                Spacer(modifier = Modifier.height(8.dp))
                // 倒塌類型選擇
                Text(stringResource(R.string.label_collapse_type), color = NV.textSecondary, fontSize = 12.sp)
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.horizontalScroll(rememberScrollState())
                ) {
                    CollapseType.entries.forEach { ct ->
                        FilterChip(
                            selected = selectedCollapse == ct,
                            onClick = { selectedCollapse = ct },
                            label = { Text(ct.label, fontSize = 10.sp) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = NV.warning.copy(alpha = 0.3f),
                                selectedLabelColor = NV.warning
                            )
                        )
                    }
                }
            }
        }
        // 樓層設定
        item {
            SectionCard(stringResource(R.string.section_floors)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedTextField(
                        value = aboveFloors, onValueChange = { aboveFloors = it.filter { c -> c.isDigit() } },
                        label = { Text(stringResource(R.string.label_above_floors)) },
                        modifier = Modifier.weight(1f), colors = fieldColors(), singleLine = true
                    )
                    OutlinedTextField(
                        value = belowFloors, onValueChange = { belowFloors = it.filter { c -> c.isDigit() } },
                        label = { Text(stringResource(R.string.label_below_floors)) },
                        modifier = Modifier.weight(1f), colors = fieldColors(), singleLine = true
                    )
                    TextButton(onClick = {
                        viewModel.generateFloors(
                            aboveFloors.toIntOrNull() ?: 1,
                            belowFloors.toIntOrNull() ?: 0
                        )
                    }) {
                        Text(stringResource(R.string.generate_floors), color = NV.command, fontSize = 11.sp)
                    }
                }
                // 樓層狀態列表
                if (site.floors.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(4.dp))
                    site.floors.forEach { floor ->
                        var expanded by remember { mutableStateOf(false) }
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { expanded = !expanded }
                                .padding(vertical = 4.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(floor.id, color = NV.white, fontSize = 13.sp, fontWeight = FontWeight.Bold,
                                modifier = Modifier.width(48.dp))
                            Text(
                                floor.condition.label, fontSize = 11.sp,
                                color = floor.condition.color,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier
                                    .background(floor.condition.color.copy(alpha = 0.15f), RoundedCornerShape(4.dp))
                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                            )
                            Icon(
                                if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                                contentDescription = null, tint = NV.textSecondary, modifier = Modifier.size(20.dp)
                            )
                        }
                        if (expanded) {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                                modifier = Modifier.horizontalScroll(rememberScrollState()).padding(start = 48.dp)
                            ) {
                                FloorCondition.entries.forEach { cond ->
                                    FilterChip(
                                        selected = floor.condition == cond,
                                        onClick = { viewModel.updateFloorCondition(floor.id, cond) },
                                        label = { Text(cond.label, fontSize = 9.sp) },
                                        colors = FilterChipDefaults.filterChipColors(
                                            selectedContainerColor = cond.color.copy(alpha = 0.3f),
                                            selectedLabelColor = cond.color
                                        )
                                    )
                                }
                            }
                        }
                        Divider(color = NV.cardBorder.copy(alpha = 0.3f))
                    }
                }
            }
        }
        // 危害管理
        item {
            SectionCard(stringResource(R.string.section_hazards)) {
                if (site.hazards.isEmpty()) {
                    Text(stringResource(R.string.no_hazards), color = NV.textSecondary, fontSize = 12.sp)
                }
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.horizontalScroll(rememberScrollState())
                ) {
                    HazardType.entries.forEach { hazard ->
                        val active = site.hazards.contains(hazard)
                        FilterChip(
                            selected = active,
                            onClick = { viewModel.toggleHazard(hazard) },
                            label = { Text("${hazard.icon} ${hazard.label}", fontSize = 10.sp) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = NV.danger.copy(alpha = 0.3f),
                                selectedLabelColor = NV.danger,
                                labelColor = NV.textSecondary
                            )
                        )
                    }
                }
            }
        }
        // 進入點管理
        item {
            SectionCard(stringResource(R.string.section_entry_points)) {
                if (site.entryPoints.isEmpty()) {
                    Text(stringResource(R.string.no_entry_points), color = NV.textSecondary, fontSize = 12.sp)
                }
                site.entryPoints.forEach { ep ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(ep.name, color = NV.white, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                            if (ep.description.isNotEmpty()) {
                                Text(ep.description, color = NV.textSecondary, fontSize = 11.sp)
                            }
                        }
                        Text(
                            if (ep.isAccessible) stringResource(R.string.label_accessible) else stringResource(R.string.label_blocked),
                            fontSize = 10.sp, fontWeight = FontWeight.Bold,
                            color = if (ep.isAccessible) NV.green else NV.danger,
                            modifier = Modifier
                                .clickable { viewModel.toggleEntryPointAccessible(ep.id) }
                                .background(
                                    (if (ep.isAccessible) NV.green else NV.danger).copy(alpha = 0.15f),
                                    RoundedCornerShape(4.dp)
                                )
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        )
                        IconButton(onClick = { viewModel.removeEntryPoint(ep.id) }, modifier = Modifier.size(28.dp)) {
                            Icon(Icons.Default.Close, contentDescription = null, tint = NV.danger, modifier = Modifier.size(14.dp))
                        }
                    }
                    Divider(color = NV.cardBorder.copy(alpha = 0.3f))
                }
                TextButton(onClick = { showAddEntryPoint = true }) {
                    Icon(Icons.Default.Add, contentDescription = null, tint = NV.green, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(stringResource(R.string.add_entry_point), color = NV.green, fontSize = 12.sp)
                }
            }
        }
        // 集結點 & 備註
        item {
            SectionCard(stringResource(R.string.section_other)) {
                OutlinedTextField(value = rallyPoint, onValueChange = { rallyPoint = it },
                    label = { Text(stringResource(R.string.label_rally_point)) }, modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors())
                Spacer(modifier = Modifier.height(8.dp))
                OutlinedTextField(value = noteText, onValueChange = { noteText = it },
                    label = { Text(stringResource(R.string.label_notes)) }, modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors())
            }
        }
        // PADOS 目標選擇
        item {
            val targetMode by viewModel.targetMode.collectAsState()
            val selectedTargetIDs by viewModel.selectedTargetDeviceIDs.collectAsState()
            val fieldUnits by viewModel.server.fieldUnits.collectAsState()

            DeviceTargetSelector(
                targetMode = targetMode,
                selectedIDs = selectedTargetIDs,
                fieldUnits = fieldUnits,
                onModeChange = { viewModel.setTargetMode(it) },
                onToggleDevice = { viewModel.toggleTargetDevice(it) },
                onSelectAll = { viewModel.selectAllDevices() },
                onDeselectAll = { viewModel.deselectAllDevices() }
            )
        }
        // 儲存按鈕
        item {
            val isRunning by viewModel.isHQActive.collectAsState()
            val targetMode by viewModel.targetMode.collectAsState()
            val selectedTargetIDs by viewModel.selectedTargetDeviceIDs.collectAsState()
            Button(
                onClick = {
                    viewModel.updateDisasterSite(site.copy(
                        buildingName = buildingName, address = address,
                        collapseType = selectedCollapse,
                        rallyPoint = rallyPoint, note = noteText
                    ))
                },
                enabled = isRunning,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = NV.warning)
            ) {
                Text(
                    if (targetMode == HQViewModel.TargetMode.BROADCAST) stringResource(R.string.save_broadcast_disaster)
                    else stringResource(R.string.send_to_n_devices, selectedTargetIDs.size),
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }

    // 新增進入點 Dialog
    if (showAddEntryPoint) {
        var epName by remember { mutableStateOf("") }
        var epDesc by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showAddEntryPoint = false },
            containerColor = NV.card,
            title = { Text(stringResource(R.string.add_entry_point), color = NV.white) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(value = epName, onValueChange = { epName = it },
                        label = { Text(stringResource(R.string.label_entry_name)) },
                        colors = fieldColors(), modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = epDesc, onValueChange = { epDesc = it },
                        label = { Text(stringResource(R.string.label_entry_desc)) },
                        colors = fieldColors(), modifier = Modifier.fillMaxWidth())
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    if (epName.isNotBlank()) {
                        viewModel.addEntryPoint(epName.trim(), epDesc.trim())
                        showAddEntryPoint = false
                    }
                }) { Text(stringResource(R.string.btn_confirm), color = NV.command) }
            },
            dismissButton = {
                TextButton(onClick = { showAddEntryPoint = false }) { Text(stringResource(R.string.btn_cancel), color = NV.textSecondary) }
            }
        )
    }
}

// =====================================================
//  通訊頻道 Tab
// =====================================================

@Composable
fun HQChatTab(viewModel: HQViewModel) {
    val messages by viewModel.chatMessages.collectAsState()
    val senderName by viewModel.senderName.collectAsState()
    var draft by remember { mutableStateOf("") }
    val listState = rememberLazyListState()

    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1)
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // 訊息列表
        LazyColumn(
            state = listState,
            modifier = Modifier.weight(1f).padding(horizontal = 12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            contentPadding = PaddingValues(vertical = 8.dp)
        ) {
            items(messages) { msg ->
                ChatBubbleItem(msg, isFromHQ = msg.senderID == "HQ")
            }
        }
        // 輸入列
        val personnel by viewModel.personnelAssignments.collectAsState()
        var showMentionPicker by remember { mutableStateOf(false) }
        Row(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            val isRunning by viewModel.isHQActive.collectAsState()
            OutlinedTextField(
                value = draft, onValueChange = { draft = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text(stringResource(R.string.input_message_hint)) },
                colors = fieldColors(),
                maxLines = 3
            )
            Spacer(modifier = Modifier.width(4.dp))
            // @ 提及選人鈕
            Box {
                IconButton(
                    onClick = { showMentionPicker = !showMentionPicker },
                    enabled = personnel.isNotEmpty() && isRunning
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
                }
            }
            Spacer(modifier = Modifier.width(4.dp))
            IconButton(
                onClick = {
                    viewModel.sendChat(draft)
                    draft = ""
                },
                enabled = draft.isNotBlank() && isRunning
            ) {
                Icon(Icons.Default.Send, contentDescription = stringResource(R.string.cd_send), tint = NV.command)
            }
        }
    }
}

@Composable
fun ChatBubbleItem(msg: ChatMessage, isFromHQ: Boolean) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = if (isFromHQ) Alignment.End else Alignment.Start
    ) {
        Text(msg.senderName, fontSize = 10.sp, color = NV.textSecondary)
        Box(
            modifier = Modifier
                .background(
                    if (isFromHQ) NV.command.copy(alpha = 0.2f) else Color.Gray.copy(alpha = 0.15f),
                    NVShape.card
                )
                .padding(horizontal = 12.dp, vertical = 8.dp)
        ) {
            Text(msg.content, color = NV.white, fontSize = 14.sp)
        }
        if (msg.mentions.isNotEmpty()) {
            Row(modifier = Modifier.padding(top = 2.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                msg.mentions.take(5).forEach { mid ->
                    Text(
                        "@${mid.takeLast(6)}",
                        fontSize = 9.sp, color = NV.command,
                        modifier = Modifier
                            .background(NV.command.copy(alpha = 0.15f), RoundedCornerShape(4.dp))
                            .padding(horizontal = 4.dp, vertical = 1.dp)
                    )
                }
            }
        }
    }
}

// =====================================================
//  人員配置 Tab
// =====================================================

@Composable
fun HQPersonnelTab(viewModel: HQViewModel) {
    val assignments by viewModel.personnelAssignments.collectAsState()
    var showCreate by remember { mutableStateOf(false) }

    Box(modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item {
                Text(stringResource(R.string.personnel_assignment), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white)
                Spacer(modifier = Modifier.height(4.dp))
                Text(stringResource(R.string.assigned_count, assignments.size), fontSize = 12.sp, color = NV.textSecondary)
            }
            if (assignments.isEmpty()) {
                item {
                    Box(modifier = Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
                        Text(stringResource(R.string.no_personnel), color = NV.textSecondary)
                    }
                }
            }
            items(assignments) { a ->
                SectionCard(a.displayLabel) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(a.role.label, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                            color = NV.info,
                            modifier = Modifier
                                .background(NV.info.copy(alpha = 0.15f), RoundedCornerShape(4.dp))
                                .padding(horizontal = 6.dp, vertical = 2.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        if (a.assignedZone.isNotEmpty()) { Text(a.assignedZone, fontSize = 12.sp, color = NV.textSecondary) }
                        if (a.assignedFloor.isNotEmpty()) { Text(a.assignedFloor, fontSize = 12.sp, color = NV.textSecondary) }
                    }
                }
            }
        }
        FloatingActionButton(
            onClick = { showCreate = true },
            containerColor = NV.command,
            modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp)
        ) { Icon(Icons.Default.PersonAdd, contentDescription = stringResource(R.string.cd_add_personnel)) }
    }

    if (showCreate) {
        var name by remember { mutableStateOf("") }
        var nickname by remember { mutableStateOf("") }
        var selectedRole by remember { mutableStateOf(PersonnelRole.SEARCH) }
        var zone by remember { mutableStateOf("") }
        var floor by remember { mutableStateOf("") }

        AlertDialog(
            onDismissRequest = { showCreate = false },
            containerColor = NV.card,
            title = { Text(stringResource(R.string.add_personnel), color = NV.white) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(value = nickname, onValueChange = { nickname = it }, label = { Text("暱稱（顯示名）") }, colors = fieldColors(), modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text(stringResource(R.string.label_name)) }, colors = fieldColors(), modifier = Modifier.fillMaxWidth())
                    Text(stringResource(R.string.label_role), color = NV.textSecondary, fontSize = 12.sp)
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        PersonnelRole.entries.take(4).forEach { role ->
                            FilterChip(selected = selectedRole == role, onClick = { selectedRole = role },
                                label = { Text(role.label, fontSize = 10.sp) })
                        }
                    }
                    OutlinedTextField(value = zone, onValueChange = { zone = it }, label = { Text(stringResource(R.string.label_zone)) }, colors = fieldColors(), modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = floor, onValueChange = { floor = it }, label = { Text(stringResource(R.string.label_floor)) }, colors = fieldColors(), modifier = Modifier.fillMaxWidth())
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    if (name.isNotBlank()) {
                        viewModel.assignPersonnel(PersonnelAssignment(
                            name = name.trim(),
                            nickname = nickname.trim().ifEmpty { null },
                            role = selectedRole,
                            assignedZone = zone.trim(),
                            assignedFloor = floor.trim()
                        ))
                        showCreate = false
                    }
                }) { Text(stringResource(R.string.btn_confirm), color = NV.command) }
            },
            dismissButton = { TextButton(onClick = { showCreate = false }) { Text(stringResource(R.string.btn_cancel), color = NV.textSecondary) } }
        )
    }
}

// =====================================================
//  PWS 警報 Tab
// =====================================================

@Composable
fun HQPWSTab(viewModel: HQViewModel) {
    val alerts by viewModel.pwsAlerts.collectAsState()
    var showCreate by remember { mutableStateOf(false) }

    Box(modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item {
                Text(stringResource(R.string.pws_alerts), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white)
            }
            if (alerts.isEmpty()) {
                item {
                    Box(modifier = Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(Icons.Default.Shield, contentDescription = null, tint = NV.green, modifier = Modifier.size(40.dp))
                            Text(stringResource(R.string.no_pws_alerts), color = NV.textSecondary)
                        }
                    }
                }
            }
            items(alerts) { alert ->
                SectionCard(alert.title) {
                    Row {
                        Text(alert.alertType.label, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                            color = alert.severity.color,
                            modifier = Modifier
                                .background(alert.severity.color.copy(alpha = 0.15f), RoundedCornerShape(4.dp))
                                .padding(horizontal = 6.dp, vertical = 2.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(alert.severity.label, fontSize = 12.sp, color = alert.severity.color)
                        Spacer(modifier = Modifier.weight(1f))
                        if (alert.isActive) {
                            Text(stringResource(R.string.pws_active), fontSize = 10.sp, color = NV.white, fontWeight = FontWeight.Bold,
                                modifier = Modifier.background(NV.danger, RoundedCornerShape(4.dp))
                                    .padding(horizontal = 4.dp, vertical = 2.dp))
                        }
                    }
                    Text(alert.content, fontSize = 12.sp, color = NV.textSecondary)
                    Text(stringResource(R.string.source_prefix, alert.publisher), fontSize = 10.sp, color = NV.textSecondary)
                }
            }
        }
        FloatingActionButton(
            onClick = { showCreate = true },
            containerColor = NV.warning,
            modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp)
        ) { Icon(Icons.Default.AddAlert, contentDescription = stringResource(R.string.cd_add_alert)) }
    }

    if (showCreate) {
        var title by remember { mutableStateOf("") }
        var content by remember { mutableStateOf("") }
        var selectedType by remember { mutableStateOf(PWSAlertType.EARTHQUAKE) }
        var selectedSeverity by remember { mutableStateOf(PWSSeverity.SEVERE) }

        AlertDialog(
            onDismissRequest = { showCreate = false },
            containerColor = NV.card,
            title = { Text(stringResource(R.string.add_pws_alert), color = NV.white) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(value = title, onValueChange = { title = it }, label = { Text(stringResource(R.string.label_title)) }, colors = fieldColors(), modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = content, onValueChange = { content = it }, label = { Text(stringResource(R.string.label_content)) }, colors = fieldColors(), modifier = Modifier.fillMaxWidth(), minLines = 2)
                    Text(stringResource(R.string.label_type), color = NV.textSecondary, fontSize = 12.sp)
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.horizontalScroll(rememberScrollState())) {
                        PWSAlertType.entries.forEach { type ->
                            FilterChip(selected = selectedType == type, onClick = { selectedType = type },
                                label = { Text(type.label, fontSize = 10.sp) })
                        }
                    }
                    Text(stringResource(R.string.label_severity), color = NV.textSecondary, fontSize = 12.sp)
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        PWSSeverity.entries.forEach { sev ->
                            FilterChip(selected = selectedSeverity == sev, onClick = { selectedSeverity = sev },
                                label = { Text(sev.label, fontSize = 10.sp) })
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    if (title.isNotBlank()) {
                        viewModel.addPWSAlert(PWSAlert(alertType = selectedType, title = title.trim(), content = content.trim(), severity = selectedSeverity))
                        showCreate = false
                    }
                }) { Text(stringResource(R.string.btn_confirm), color = NV.command) }
            },
            dismissButton = { TextButton(onClick = { showCreate = false }) { Text(stringResource(R.string.btn_cancel), color = NV.textSecondary) } }
        )
    }
}

// =====================================================
//  會報系統 Tab
// =====================================================

@Composable
fun HQBriefingTab(viewModel: HQViewModel) {
    val briefings by viewModel.briefings.collectAsState()
    var showCreate by remember { mutableStateOf(false) }

    Box(modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item {
                Text(stringResource(R.string.briefing_system), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white)
            }
            if (briefings.isEmpty()) {
                item {
                    Box(modifier = Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
                        Text(stringResource(R.string.no_briefings), color = NV.textSecondary)
                    }
                }
            }
            items(briefings) { report ->
                SectionCard(report.title) {
                    Row {
                        Text(report.type.label, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                            color = NV.info,
                            modifier = Modifier
                                .background(NV.info.copy(alpha = 0.15f), RoundedCornerShape(4.dp))
                                .padding(horizontal = 6.dp, vertical = 2.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("by ${report.author}", fontSize = 12.sp, color = NV.textSecondary)
                    }
                    report.sections.forEach { section ->
                        Column {
                            Text(section.title, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = NV.white)
                            Text(section.content, fontSize = 12.sp, color = NV.textSecondary)
                        }
                    }
                }
            }
        }
        FloatingActionButton(
            onClick = { showCreate = true },
            containerColor = NV.info,
            modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp)
        ) { Icon(Icons.Default.NoteAdd, contentDescription = stringResource(R.string.cd_add_briefing)) }
    }

    if (showCreate) {
        var title by remember { mutableStateOf("") }
        var author by remember { mutableStateOf("") }
        var sectionTitle by remember { mutableStateOf("") }
        var sectionContent by remember { mutableStateOf("") }
        var selectedType by remember { mutableStateOf(BriefingType.INITIAL) }

        AlertDialog(
            onDismissRequest = { showCreate = false },
            containerColor = NV.card,
            title = { Text(stringResource(R.string.add_briefing), color = NV.white) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(value = title, onValueChange = { title = it }, label = { Text(stringResource(R.string.label_title)) }, colors = fieldColors(), modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = author, onValueChange = { author = it }, label = { Text(stringResource(R.string.label_author)) }, colors = fieldColors(), modifier = Modifier.fillMaxWidth())
                    Text(stringResource(R.string.label_type), color = NV.textSecondary, fontSize = 12.sp)
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        BriefingType.entries.forEach { type ->
                            FilterChip(selected = selectedType == type, onClick = { selectedType = type },
                                label = { Text(type.localizedLabel(), fontSize = 10.sp) })
                        }
                    }
                    OutlinedTextField(value = sectionTitle, onValueChange = { sectionTitle = it }, label = { Text(stringResource(R.string.label_section_title)) }, colors = fieldColors(), modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(value = sectionContent, onValueChange = { sectionContent = it }, label = { Text(stringResource(R.string.label_section_content)) }, colors = fieldColors(), modifier = Modifier.fillMaxWidth(), minLines = 3)
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    if (title.isNotBlank()) {
                        viewModel.addBriefing(BriefingReport(type = selectedType, title = title.trim(), author = author.trim(), sections = if (sectionTitle.isNotBlank()) listOf(BriefingSection(title = sectionTitle.trim(), content = sectionContent.trim())) else emptyList()))
                        showCreate = false
                    }
                }) { Text(stringResource(R.string.btn_confirm), color = NV.command) }
            },
            dismissButton = { TextButton(onClick = { showCreate = false }) { Text(stringResource(R.string.btn_cancel), color = NV.textSecondary) } }
        )
    }
}

// =====================================================
//  個人通知 Tab
// =====================================================

@Composable
fun HQNotificationTab(viewModel: HQViewModel) {
    val notifications by viewModel.personalNotifications.collectAsState()
    val fieldUnits by viewModel.server.fieldUnits.collectAsState()
    var showCreateDialog by remember { mutableStateOf(false) }
    var notifTitle by remember { mutableStateOf("") }
    var notifContent by remember { mutableStateOf("") }
    var targetDeviceID by remember { mutableStateOf("") }

    Box(modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.personal_notifications), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white)
                    Spacer(modifier = Modifier.weight(1f))
                    Text(stringResource(R.string.count_items, notifications.size), color = NV.textSecondary, fontSize = 12.sp)
                }
            }
            if (notifications.isEmpty()) {
                item {
                    Box(modifier = Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
                        Text(stringResource(R.string.no_personal_notifications), color = NV.textSecondary)
                    }
                }
            }
            items(notifications) { notif ->
                SectionCard(notif.title) {
                    Text(notif.content, fontSize = 12.sp, color = NV.textSecondary)
                    Text("→ ${notif.targetDeviceID}", fontSize = 10.sp, color = NV.textSecondary)
                }
            }
        }

        // FAB
        FloatingActionButton(
            onClick = { showCreateDialog = true },
            modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp),
            containerColor = NV.command
        ) {
            Icon(Icons.Default.Add, contentDescription = "Add", tint = Color.White)
        }

        // Create notification dialog
        if (showCreateDialog) {
            AlertDialog(
                onDismissRequest = { showCreateDialog = false },
                title = { Text(stringResource(R.string.send_notification), color = NV.white) },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(value = notifTitle, onValueChange = { notifTitle = it },
                            label = { Text(stringResource(R.string.label_title)) }, modifier = Modifier.fillMaxWidth(), colors = fieldColors())
                        OutlinedTextField(value = notifContent, onValueChange = { notifContent = it },
                            label = { Text(stringResource(R.string.label_content)) }, modifier = Modifier.fillMaxWidth(), colors = fieldColors(), minLines = 2)
                        Text(stringResource(R.string.label_target_device), color = NV.textSecondary, fontSize = 12.sp)
                        if (fieldUnits.isEmpty()) {
                            Text(stringResource(R.string.no_online_units), color = NV.textSecondary, fontSize = 11.sp)
                        } else {
                            fieldUnits.filter { it.isOnline }.forEach { unit ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable { targetDeviceID = unit.deviceID }
                                        .background(
                                            if (targetDeviceID == unit.deviceID) NV.command.copy(alpha = 0.2f)
                                            else Color.Transparent, RoundedCornerShape(6.dp)
                                        )
                                        .padding(8.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Icon(Icons.Default.Person, contentDescription = null, tint = NV.green, modifier = Modifier.size(16.dp))
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text("${unit.deptCode} (${unit.deviceID.takeLast(4)})", color = NV.white, fontSize = 12.sp)
                                }
                            }
                        }
                    }
                },
                confirmButton = {
                    TextButton(
                        onClick = {
                            if (notifTitle.isNotBlank() && targetDeviceID.isNotBlank()) {
                                viewModel.sendNotification(PersonalNotification(
                                    targetDeviceID = targetDeviceID, title = notifTitle.trim(), content = notifContent.trim()
                                ))
                                notifTitle = ""; notifContent = ""; targetDeviceID = ""
                                showCreateDialog = false
                            }
                        }
                    ) { Text(stringResource(R.string.btn_send), color = NV.command) }
                },
                dismissButton = {
                    TextButton(onClick = { showCreateDialog = false }) { Text(stringResource(R.string.btn_cancel), color = NV.textSecondary) }
                },
                containerColor = NV.card
            )
        }
    }
}

// =====================================================
//  共用元件
// =====================================================

@Composable
fun SectionCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(NV.card, NVShape.card)
            .border(1.dp, NV.cardBorder, NVShape.card)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(title, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = NV.white)
        content()
    }
}

@Composable
fun fieldColors() = OutlinedTextFieldDefaults.colors(
    focusedTextColor = NV.white,
    unfocusedTextColor = NV.white,
    focusedBorderColor = NV.command,
    unfocusedBorderColor = NV.cardBorder,
    focusedLabelColor = NV.command,
    unfocusedLabelColor = NV.textSecondary,
    cursorColor = NV.command
)

// =====================================================
//  事件日誌 Tab
// =====================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HQTimelineTab(viewModel: HQViewModel) {
    val events by viewModel.timelineEvents.collectAsState()
    var selectedFilter by remember { mutableStateOf<TimelineEventType?>(null) }

    val filtered = if (selectedFilter == null) events else events.filter { it.eventType == selectedFilter }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(stringResource(R.string.event_log), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white)
                if (events.isNotEmpty()) {
                    TextButton(onClick = { viewModel.clearTimeline() }) {
                        Text(stringResource(R.string.btn_clear), color = NV.danger, fontSize = 12.sp)
                    }
                }
            }
        }

        // 篩選列
        item {
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.horizontalScroll(rememberScrollState())
            ) {
                FilterChip(
                    selected = selectedFilter == null,
                    onClick = { selectedFilter = null },
                    label = { Text(stringResource(R.string.filter_all), fontSize = 11.sp) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = NV.blue.copy(alpha = 0.3f),
                        selectedLabelColor = NV.white,
                        labelColor = NV.textSecondary
                    )
                )
                TimelineEventType.entries.forEach { type ->
                    FilterChip(
                        selected = selectedFilter == type,
                        onClick = { selectedFilter = if (selectedFilter == type) null else type },
                        label = { Text("${type.icon} ${type.label}", fontSize = 11.sp) },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = type.color.copy(alpha = 0.3f),
                            selectedLabelColor = NV.white,
                            labelColor = NV.textSecondary
                        )
                    )
                }
            }
        }

        if (filtered.isEmpty()) {
            item {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(48.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Icon(Icons.Default.Schedule, contentDescription = null,
                        modifier = Modifier.size(48.dp), tint = NV.textSecondary)
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(stringResource(R.string.no_events), color = NV.textSecondary, fontSize = 16.sp)
                    Text(stringResource(R.string.events_auto_log), color = NV.textSecondary, fontSize = 12.sp)
                }
            }
        } else {
            items(filtered, key = { it.id }) { event ->
                SectionCard(event.title) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(event.eventType.icon, fontSize = 16.sp)
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(event.eventType.label, color = event.eventType.color, fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier
                                    .background(event.eventType.color.copy(alpha = 0.15f), RoundedCornerShape(4.dp))
                                    .padding(horizontal = 6.dp, vertical = 2.dp))
                        }
                        Text(event.timeText, color = NV.textSecondary, fontSize = 11.sp)
                    }
                    if (event.detail.isNotEmpty()) {
                        Text(event.detail, color = NV.textSecondary, fontSize = 13.sp)
                    }
                }
            }
        }
    }
}

// =====================================================
//  分區地圖 Tab
// =====================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HQZoneMapTab(viewModel: HQViewModel) {
    val site by viewModel.disasterSite.collectAsState()
    val zones = site.zones
    val personnel by viewModel.personnelAssignments.collectAsState()
    var showAddDialog by remember { mutableStateOf(false) }
    var newZoneName by remember { mutableStateOf("") }
    var editingZoneId by remember { mutableStateOf<String?>(null) }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(stringResource(R.string.zone_map), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white)
                IconButton(onClick = { showAddDialog = true }) {
                    Icon(Icons.Default.Add, contentDescription = stringResource(R.string.cd_add_zone), tint = NV.green)
                }
            }
        }

        // 統計條
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ZoneStatCard(stringResource(R.string.stat_total_zones), "${zones.size}", NV.info, Modifier.weight(1f))
                ZoneStatCard(stringResource(R.string.stat_searching), "${zones.count { it.status == ZoneStatus.ACTIVE }}", NV.green, Modifier.weight(1f))
                ZoneStatCard(stringResource(R.string.stat_cleared), "${zones.count { it.status == ZoneStatus.CLEARED }}", NV.info, Modifier.weight(1f))
                ZoneStatCard(stringResource(R.string.stat_dangerous), "${zones.count { it.status == ZoneStatus.DANGEROUS }}", NV.danger, Modifier.weight(1f))
            }
        }

        // Canvas zone visualization
        if (zones.isNotEmpty()) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(180.dp)
                        .background(NV.surface, NVShape.card)
                        .border(1.dp, NV.cardBorder, NVShape.card)
                        .padding(12.dp)
                ) {
                    Canvas(modifier = Modifier.fillMaxSize()) {
                        val cols = kotlin.math.ceil(kotlin.math.sqrt(zones.size.toDouble())).toInt().coerceAtLeast(1)
                        val rows = kotlin.math.ceil(zones.size.toDouble() / cols).toInt()
                        val cellW = size.width / cols
                        val cellH = size.height / rows
                        val pad = 4f

                        zones.forEachIndexed { idx, zone ->
                            val col = idx % cols
                            val row = idx / cols
                            val x = col * cellW + pad
                            val y = row * cellH + pad
                            val w = cellW - pad * 2
                            val h = cellH - pad * 2

                            val fillColor = when (zone.status) {
                                ZoneStatus.ACTIVE -> Color(0xFF14B840).copy(alpha = 0.25f)
                                ZoneStatus.DANGEROUS -> Color(0xFFD13838).copy(alpha = 0.25f)
                                ZoneStatus.CLEARED -> Color(0xFF1AAD8C).copy(alpha = 0.25f)
                                ZoneStatus.STANDBY -> Color(0xFFB8941F).copy(alpha = 0.15f)
                                ZoneStatus.RESTRICTED -> Color(0xFFD18014).copy(alpha = 0.2f)
                            }
                            val borderColor = when (zone.status) {
                                ZoneStatus.ACTIVE -> Color(0xFF14B840)
                                ZoneStatus.DANGEROUS -> Color(0xFFD13838)
                                ZoneStatus.CLEARED -> Color(0xFF1AAD8C)
                                ZoneStatus.STANDBY -> Color(0xFFB8941F)
                                ZoneStatus.RESTRICTED -> Color(0xFFD18014)
                            }

                            drawRect(fillColor, Offset(x, y), Size(w, h))
                            drawRect(borderColor, Offset(x, y), Size(w, h), style = Stroke(width = 2f))

                            // Hazard marker
                            if (zone.hazards.isNotEmpty()) {
                                drawCircle(Color(0xFFD13838), radius = 6f, center = Offset(x + w - 10f, y + 10f))
                            }

                            // Personnel dots
                            val assigned = personnel.count { it.assignedZone == zone.name }
                            for (p in 0 until assigned.coerceAtMost(5)) {
                                drawCircle(
                                    Color(0xFF4066B8),
                                    radius = 4f,
                                    center = Offset(x + 12f + p * 12f, y + h - 12f)
                                )
                            }
                        }
                    }
                    // Zone name overlay
                    val cols = kotlin.math.ceil(kotlin.math.sqrt(zones.size.toDouble())).toInt().coerceAtLeast(1)
                    zones.forEachIndexed { idx, zone ->
                        val col = idx % cols
                        val rows2 = kotlin.math.ceil(zones.size.toDouble() / cols).toInt()
                        val row = idx / cols
                        val fracX = col.toFloat() / cols
                        val fracY = row.toFloat() / rows2
                        val fracW = 1f / cols
                        val fracH = 1f / rows2
                        Box(
                            modifier = Modifier
                                .fillMaxWidth(fracW)
                                .fillMaxHeight(fracH)
                                .offset(
                                    x = (fracX * 500).dp.times(0f), // approximate overlay
                                    y = (fracY * 180).dp.times(0f)
                                ),
                            contentAlignment = Alignment.Center
                        ) {
                            // Handled by Canvas drawing; names shown in card list below
                        }
                    }
                }
            }
        }

        if (zones.isEmpty()) {
            item {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(48.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Icon(Icons.Default.Map, contentDescription = null,
                        modifier = Modifier.size(48.dp), tint = NV.textSecondary)
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(stringResource(R.string.no_zones), color = NV.textSecondary, fontSize = 16.sp)
                    Text(stringResource(R.string.tap_add_zone), color = NV.textSecondary, fontSize = 12.sp)
                }
            }
        } else {
            items(zones, key = { it.id }) { zone ->
                val assignedPersonnel = personnel.filter { it.assignedZone == zone.name }
                val isEditing = editingZoneId == zone.id
                SectionCard(zone.name) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        // 狀態標籤
                        Text(
                            zone.status.label, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                            color = zone.status.color,
                            modifier = Modifier
                                .background(zone.status.color.copy(alpha = 0.15f), RoundedCornerShape(4.dp))
                                .padding(horizontal = 8.dp, vertical = 3.dp)
                        )
                        Text(stringResource(R.string.n_persons, assignedPersonnel.size), color = NV.textSecondary, fontSize = 12.sp)
                    }

                    // 危險標記
                    if (zone.hazards.isNotEmpty()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.horizontalScroll(rememberScrollState())) {
                            zone.hazards.forEach { hazard ->
                                Text(
                                    "${hazard.icon} ${hazard.label}", fontSize = 10.sp, color = NV.danger,
                                    modifier = Modifier
                                        .background(NV.danger.copy(alpha = 0.1f), RoundedCornerShape(4.dp))
                                        .padding(horizontal = 4.dp, vertical = 2.dp)
                                )
                            }
                        }
                    }

                    if (zone.note.isNotEmpty()) {
                        Text(zone.note, color = NV.textSecondary, fontSize = 12.sp)
                    }

                    // Assigned personnel names
                    if (assignedPersonnel.isNotEmpty()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.horizontalScroll(rememberScrollState())) {
                            assignedPersonnel.forEach { p ->
                                Text(
                                    "${p.role.icon} ${p.name}", fontSize = 10.sp, color = NV.info,
                                    modifier = Modifier
                                        .background(NV.info.copy(alpha = 0.1f), RoundedCornerShape(4.dp))
                                        .padding(horizontal = 4.dp, vertical = 2.dp)
                                )
                            }
                        }
                    }

                    // 操作按鈕
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        ZoneStatus.entries.filter { it != zone.status }.take(3).forEach { status ->
                            TextButton(
                                onClick = { viewModel.updateZoneStatus(zone.id, status) },
                                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp)
                            ) {
                                Text(status.label, fontSize = 11.sp, color = status.color)
                            }
                        }
                        Spacer(modifier = Modifier.weight(1f))
                        IconButton(
                            onClick = { editingZoneId = if (isEditing) null else zone.id },
                            modifier = Modifier.size(32.dp)
                        ) {
                            Icon(Icons.Default.Edit, contentDescription = null, tint = NV.info, modifier = Modifier.size(16.dp))
                        }
                        IconButton(onClick = { viewModel.removeZone(zone.id) }, modifier = Modifier.size(32.dp)) {
                            Icon(Icons.Default.Delete, contentDescription = stringResource(R.string.cd_delete), tint = NV.danger, modifier = Modifier.size(16.dp))
                        }
                    }

                    // Expanded editing panel
                    if (isEditing) {
                        Divider(color = NV.cardBorder.copy(alpha = 0.5f))
                        Text(stringResource(R.string.zone_hazard), color = NV.textSecondary, fontSize = 11.sp)
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            modifier = Modifier.horizontalScroll(rememberScrollState())
                        ) {
                            HazardType.entries.forEach { hazard ->
                                FilterChip(
                                    selected = zone.hazards.contains(hazard),
                                    onClick = { viewModel.toggleZoneHazard(zone.id, hazard) },
                                    label = { Text("${hazard.icon} ${hazard.label}", fontSize = 9.sp) },
                                    colors = FilterChipDefaults.filterChipColors(
                                        selectedContainerColor = NV.danger.copy(alpha = 0.3f),
                                        selectedLabelColor = NV.danger,
                                        labelColor = NV.textSecondary
                                    )
                                )
                            }
                        }
                        var editNote by remember(zone.id) { mutableStateOf(zone.note) }
                        OutlinedTextField(
                            value = editNote, onValueChange = { editNote = it },
                            label = { Text(stringResource(R.string.zone_note_hint)) },
                            modifier = Modifier.fillMaxWidth(), colors = fieldColors(), singleLine = true
                        )
                        TextButton(onClick = { viewModel.updateZoneNote(zone.id, editNote); editingZoneId = null }) {
                            Text(stringResource(R.string.btn_confirm), color = NV.command, fontSize = 11.sp)
                        }
                    }
                }
            }
        }
    }

    // 新增分區 Dialog
    if (showAddDialog) {
        AlertDialog(
            onDismissRequest = { showAddDialog = false },
            title = { Text(stringResource(R.string.add_rescue_zone), fontWeight = FontWeight.Bold) },
            text = {
                OutlinedTextField(
                    value = newZoneName,
                    onValueChange = { newZoneName = it },
                    label = { Text(stringResource(R.string.label_zone_name)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors()
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (newZoneName.isNotBlank()) {
                            viewModel.addZone(newZoneName.trim())
                            newZoneName = ""
                            showAddDialog = false
                        }
                    }
                ) { Text(stringResource(R.string.btn_add), color = NV.green) }
            },
            dismissButton = {
                TextButton(onClick = { showAddDialog = false }) { Text(stringResource(R.string.btn_cancel)) }
            },
            containerColor = NV.card
        )
    }
}

@Composable
private fun ZoneStatCard(label: String, value: String, color: Color, modifier: Modifier = Modifier) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
            .background(NV.card, NVShape.card)
            .border(1.dp, NV.cardBorder, NVShape.card)
            .padding(vertical = 10.dp, horizontal = 8.dp)
    ) {
        Text(value, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = color)
        Text(label, fontSize = 10.sp, color = NV.textSecondary)
    }
}

// =====================================================
//  會報儀表板 Tab
// =====================================================

@Composable
fun HQReportsTab(viewModel: HQViewModel) {
    val reports by viewModel.radioReports.collectAsState()

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(stringResource(R.string.report_dashboard), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white)
                Text(stringResource(R.string.n_reports, reports.size), color = NV.textSecondary, fontSize = 12.sp,
                    modifier = Modifier
                        .background(NV.textSecondary.copy(alpha = 0.1f), RoundedCornerShape(8.dp))
                        .padding(horizontal = 10.dp, vertical = 4.dp))
            }
        }

        if (reports.isEmpty()) {
            item {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(48.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Icon(Icons.Default.Description, contentDescription = null,
                        modifier = Modifier.size(48.dp), tint = NV.textSecondary.copy(alpha = 0.3f))
                    Spacer(modifier = Modifier.height(12.dp))
                    Text(stringResource(R.string.no_reports), color = NV.textSecondary, fontSize = 16.sp)
                    Text(stringResource(R.string.reports_hint), color = NV.textSecondary, fontSize = 12.sp)
                }
            }
        } else {
            items(reports, key = { it.id }) { report ->
                ReportCard(report)
            }
        }
    }
}

@Composable
private fun ReportCard(report: RadioReport) {
    var expanded by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(NV.card, NVShape.card)
            .border(1.dp, NV.cardBorder, NVShape.card)
            .clickable { expanded = !expanded }
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Mic, contentDescription = null, tint = NV.command, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(6.dp))
                Text(report.senderName, color = NV.white, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            }
            Text(report.timeText, color = NV.textSecondary, fontSize = 11.sp)
        }

        if (report.senderDeviceID.isNotEmpty()) {
            Text(stringResource(R.string.device_prefix, report.senderDeviceID), color = NV.textSecondary, fontSize = 11.sp)
        }

        if (report.transcription.isNotEmpty()) {
            Text(
                if (expanded) report.transcription else report.transcription.take(80) + if (report.transcription.length > 80) "..." else "",
                color = NV.white.copy(alpha = 0.8f), fontSize = 13.sp
            )
            if (report.transcription.length > 80) {
                Text(if (expanded) stringResource(R.string.collapse_text) else stringResource(R.string.expand_text), color = NV.blue, fontSize = 11.sp)
            }
        }
    }
}

// =====================================================
//  統計儀表板 Tab
// =====================================================

@Composable
fun HQStatsDashboardTab(viewModel: HQViewModel) {
    val fieldUnits by viewModel.server.fieldUnits.collectAsState()
    val allVictims = viewModel.server.allVictims
    val allTeam = viewModel.server.allTeamMembers

    val totalUnits = fieldUnits.size
    val onlineUnits = fieldUnits.count { it.isOnline }
    val totalVictims = allVictims.size
    val sosVictims = allVictims.count { it.isSOS }
    val onlineVictims = allVictims.count { it.isOnline }
    val totalTeam = allTeam.size
    val onlineTeam = allTeam.count { it.isOnline }
    val totalSOS = viewModel.server.totalSOSCount

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text(stringResource(R.string.stats_dashboard), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white)
        }

        // 總覽數據卡
        item {
            SectionCard(stringResource(R.string.realtime_data)) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    StatItem(stringResource(R.string.stat_field_unit_count), "$onlineUnits / $totalUnits", NV.blue)
                    StatItem(stringResource(R.string.stat_victim_count), "$totalVictims", NV.warning)
                    StatItem("SOS", "$totalSOS", NV.danger)
                }
                Spacer(modifier = Modifier.height(8.dp))
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    StatItem(stringResource(R.string.stat_online_victims), "$onlineVictims", NV.green)
                    StatItem(stringResource(R.string.stat_team_members), "$onlineTeam / $totalTeam", NV.blue)
                    StatItem(stringResource(R.string.stat_sos_victims), "$sosVictims", NV.danger)
                }
            }
        }

        // 外勤單位狀態表
        item {
            SectionCard(stringResource(R.string.field_unit_status)) {
                if (fieldUnits.isEmpty()) {
                    Text(stringResource(R.string.no_connected_units), color = NV.textSecondary, fontSize = 13.sp)
                } else {
                    fieldUnits.forEach { unit ->
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Icon(
                                    Icons.Default.Circle,
                                    contentDescription = null,
                                    tint = if (unit.isOnline) NV.green else Color.Gray,
                                    modifier = Modifier.size(8.dp)
                                )
                            Text(unit.deptCode, color = NV.white, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                            }
                            Text(stringResource(R.string.unit_stats_format, unit.victims.size, unit.sosCount, unit.battery),
                                color = NV.textSecondary, fontSize = 11.sp)
                        }
                        Divider(color = NV.cardBorder.copy(alpha = 0.3f))
                    }
                }
            }
        }
    }
}

@Composable
private fun StatItem(label: String, value: String, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = color)
        Text(label, fontSize = 11.sp, color = NV.textSecondary)
    }
}

// =====================================================
//  資源管理 Tab
// =====================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HQResourceTab(viewModel: HQViewModel) {
    val fieldUnits by viewModel.server.fieldUnits.collectAsState()
    val resourceItems by viewModel.resourceItems.collectAsState()
    var waterNote by remember { mutableStateOf("") }
    var medicalNote by remember { mutableStateOf("") }
    var equipmentNote by remember { mutableStateOf("") }
    var showAddDialog by remember { mutableStateOf(false) }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text(stringResource(R.string.resource_management), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white)
        }

        // 人力資源概況
        item {
            SectionCard(stringResource(R.string.human_resources)) {
                val totalTeam = viewModel.server.allTeamMembers.size
                val onlineTeam = viewModel.server.allTeamMembers.count { it.isOnline }
                val onlineUnits = fieldUnits.count { it.isOnline }

                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    StatItem(stringResource(R.string.stat_field_teams), "$onlineUnits", NV.blue)
                    StatItem(stringResource(R.string.stat_team_online), "$onlineTeam / $totalTeam", NV.green)
                }
            }
        }

        // 電量監控
        item {
            SectionCard(stringResource(R.string.battery_monitor)) {
                if (fieldUnits.isEmpty()) {
                    Text(stringResource(R.string.no_connected_units), color = NV.textSecondary, fontSize = 13.sp)
                } else {
                    fieldUnits.forEach { unit ->
                        val batteryColor = when {
                            unit.battery > 50 -> NV.green
                            unit.battery > 20 -> NV.warning
                            else -> NV.danger
                        }
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text("${unit.deptCode} (${unit.deviceID.takeLast(4)})",
                                color = NV.white, fontSize = 13.sp)
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                LinearProgressIndicator(
                                    progress = unit.battery / 100f,
                                    modifier = Modifier.width(80.dp).height(8.dp),
                                    color = batteryColor,
                                    trackColor = NV.cardBorder.copy(alpha = 0.3f)
                                )
                                Text("${unit.battery}%", color = batteryColor, fontSize = 11.sp)
                            }
                        }
                    }
                }
            }
        }

        // 物資清單 (Resource Inventory CRUD)
        item {
            SectionCard(stringResource(R.string.resource_inventory)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(stringResource(R.string.resource_inventory), fontWeight = FontWeight.SemiBold, color = NV.white, fontSize = 14.sp)
                    IconButton(onClick = { showAddDialog = true }, modifier = Modifier.size(28.dp)) {
                        Icon(Icons.Default.Add, contentDescription = stringResource(R.string.add_resource), tint = NV.green, modifier = Modifier.size(18.dp))
                    }
                }

                if (resourceItems.isEmpty()) {
                    Text(stringResource(R.string.no_resources), color = NV.textSecondary, fontSize = 13.sp,
                        modifier = Modifier.padding(vertical = 12.dp))
                } else {
                    resourceItems.forEach { item ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp)
                                .background(NV.surface, RoundedCornerShape(8.dp))
                                .padding(horizontal = 10.dp, vertical = 8.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(item.name, color = NV.white, fontWeight = FontWeight.Medium, fontSize = 13.sp)
                                val ratio = if (item.total > 0) item.available.toFloat() / item.total else 0f
                                val ratioColor = when {
                                    ratio > 0.5f -> NV.green
                                    ratio > 0.2f -> NV.warning
                                    else -> NV.danger
                                }
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    LinearProgressIndicator(
                                        progress = ratio.coerceIn(0f, 1f),
                                        modifier = Modifier.width(80.dp).height(6.dp),
                                        color = ratioColor,
                                        trackColor = NV.cardBorder.copy(alpha = 0.3f)
                                    )
                                    Text(
                                        stringResource(R.string.resource_ratio, item.available, item.total),
                                        color = ratioColor, fontSize = 11.sp
                                    )
                                }
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                                // Decrease available
                                IconButton(
                                    onClick = {
                                        if (item.available > 0) viewModel.updateResourceItem(item.id, item.total, item.available - 1)
                                    },
                                    modifier = Modifier.size(28.dp)
                                ) {
                                    Icon(Icons.Default.Remove, contentDescription = null, tint = NV.warning, modifier = Modifier.size(14.dp))
                                }
                                // Increase available
                                IconButton(
                                    onClick = {
                                        if (item.available < item.total) viewModel.updateResourceItem(item.id, item.total, item.available + 1)
                                    },
                                    modifier = Modifier.size(28.dp)
                                ) {
                                    Icon(Icons.Default.Add, contentDescription = null, tint = NV.green, modifier = Modifier.size(14.dp))
                                }
                                IconButton(
                                    onClick = { viewModel.removeResourceItem(item.id) },
                                    modifier = Modifier.size(28.dp)
                                ) {
                                    Icon(Icons.Default.Delete, contentDescription = stringResource(R.string.btn_delete), tint = NV.danger, modifier = Modifier.size(14.dp))
                                }
                            }
                        }
                    }
                }
            }
        }

        // 物資備註
        item {
            SectionCard(stringResource(R.string.supply_records)) {
                OutlinedTextField(value = waterNote, onValueChange = { waterNote = it },
                    label = { Text(stringResource(R.string.label_water_food)) }, modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors())
                Spacer(modifier = Modifier.height(8.dp))
                OutlinedTextField(value = medicalNote, onValueChange = { medicalNote = it },
                    label = { Text(stringResource(R.string.label_medical)) }, modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors())
                Spacer(modifier = Modifier.height(8.dp))
                OutlinedTextField(value = equipmentNote, onValueChange = { equipmentNote = it },
                    label = { Text(stringResource(R.string.label_equipment)) }, modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors())
            }
        }
    }

    // Add resource dialog
    if (showAddDialog) {
        var resName by remember { mutableStateOf("") }
        var resTotal by remember { mutableStateOf("") }
        var resAvail by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showAddDialog = false },
            title = { Text(stringResource(R.string.add_resource), fontWeight = FontWeight.Bold) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = resName, onValueChange = { resName = it },
                        label = { Text(stringResource(R.string.resource_item_name)) },
                        singleLine = true, modifier = Modifier.fillMaxWidth(), colors = fieldColors()
                    )
                    OutlinedTextField(
                        value = resTotal, onValueChange = { resTotal = it.filter { c -> c.isDigit() } },
                        label = { Text(stringResource(R.string.resource_total)) },
                        singleLine = true, modifier = Modifier.fillMaxWidth(), colors = fieldColors()
                    )
                    OutlinedTextField(
                        value = resAvail, onValueChange = { resAvail = it.filter { c -> c.isDigit() } },
                        label = { Text(stringResource(R.string.resource_available)) },
                        singleLine = true, modifier = Modifier.fillMaxWidth(), colors = fieldColors()
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val total = resTotal.toIntOrNull() ?: 0
                        val avail = (resAvail.toIntOrNull() ?: total).coerceAtMost(total)
                        if (resName.isNotBlank() && total > 0) {
                            viewModel.addResourceItem(resName.trim(), total, avail)
                            showAddDialog = false
                        }
                    }
                ) { Text(stringResource(R.string.btn_add), color = NV.green) }
            },
            dismissButton = {
                TextButton(onClick = { showAddDialog = false }) { Text(stringResource(R.string.btn_cancel)) }
            },
            containerColor = NV.card
        )
    }
}

// =====================================================
//  照片牆 Tab
// =====================================================

@Composable
fun HQPhotoWallTab(viewModel: HQViewModel) {
    val fieldUnits by viewModel.server.fieldUnits.collectAsState()
    val isBackendConnected by viewModel.isBackendConnected.collectAsState()
    val photoAlerts by viewModel.photoAlerts.collectAsState()
    var selectedPhoto by remember { mutableStateOf<PhotoAlert?>(null) }

    Box(modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.photo_wall), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white)
                    Spacer(modifier = Modifier.weight(1f))
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Default.Circle, contentDescription = null,
                            tint = if (isBackendConnected) NV.green else Color.Gray,
                            modifier = Modifier.size(8.dp))
                        Text(if (isBackendConnected) stringResource(R.string.status_connected) else stringResource(R.string.status_disconnected),
                            color = if (isBackendConnected) NV.green else NV.textSecondary, fontSize = 11.sp)
                    }
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(stringResource(R.string.n_photos, photoAlerts.size), color = NV.textSecondary, fontSize = 11.sp)
                }
            }

            if (photoAlerts.isEmpty()) {
                item {
                    Box(modifier = Modifier.fillMaxWidth().padding(vertical = 60.dp), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(Icons.Default.PhotoLibrary, contentDescription = null, tint = NV.textSecondary, modifier = Modifier.size(48.dp))
                            Text(stringResource(R.string.no_photos), color = NV.textSecondary)
                            Text(stringResource(R.string.photos_hint),
                                color = NV.textSecondary, fontSize = 12.sp)
                        }
                    }
                }
            } else {
                // Photo grid - 2 columns
                val rows = photoAlerts.chunked(2)
                items(rows, key = { it.first().id }) { row ->
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEach { photo ->
                            Column(
                                modifier = Modifier
                                    .weight(1f)
                                    .background(NV.card, RoundedCornerShape(8.dp))
                                    .border(1.dp, NV.cardBorder, RoundedCornerShape(8.dp))
                                    .clickable { selectedPhoto = photo }
                                    .padding(8.dp),
                                verticalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                // Thumbnail
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(120.dp)
                                        .background(NV.surface, RoundedCornerShape(6.dp))
                                        .clip(RoundedCornerShape(6.dp)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    if (photo.thumbnailUrl.isNotEmpty()) {
                                        AsyncImage(
                                            model = photo.thumbnailUrl,
                                            contentDescription = photo.caption.ifEmpty { photo.photoID },
                                            contentScale = ContentScale.Crop,
                                            modifier = Modifier.fillMaxSize()
                                        )
                                    } else {
                                        Icon(Icons.Default.BrokenImage, contentDescription = null, tint = NV.textSecondary, modifier = Modifier.size(32.dp))
                                    }
                                }
                                Text(photo.senderName.ifEmpty { photo.senderID.takeLast(6) },
                                    color = NV.white, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                if (photo.caption.isNotEmpty()) {
                                    Text(photo.caption, color = NV.textSecondary, fontSize = 10.sp, maxLines = 2)
                                }
                                val sdf = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
                                Text(sdf.format(java.util.Date(photo.timestamp)),
                                    color = NV.textSecondary, fontSize = 9.sp)
                            }
                        }
                        if (row.size == 1) {
                            Spacer(modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
        }

        // Photo detail dialog
        selectedPhoto?.let { photo ->
            AlertDialog(
                onDismissRequest = { selectedPhoto = null },
                confirmButton = {
                    TextButton(onClick = { selectedPhoto = null }) { Text(stringResource(R.string.btn_close)) }
                },
                title = { Text(stringResource(R.string.photo_detail), color = NV.white) },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (photo.fullUrl.isNotEmpty()) {
                            AsyncImage(
                                model = photo.fullUrl,
                                contentDescription = photo.caption,
                                contentScale = ContentScale.FillWidth,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .heightIn(max = 300.dp)
                                    .clip(RoundedCornerShape(8.dp))
                            )
                        } else if (photo.thumbnailUrl.isNotEmpty()) {
                            AsyncImage(
                                model = photo.thumbnailUrl,
                                contentDescription = photo.caption,
                                contentScale = ContentScale.FillWidth,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .heightIn(max = 300.dp)
                                    .clip(RoundedCornerShape(8.dp))
                            )
                        }
                        Text(stringResource(R.string.photographer_prefix, photo.senderName.ifEmpty { photo.senderID }), color = NV.white, fontSize = 13.sp)
                        if (photo.caption.isNotEmpty())
                            Text(stringResource(R.string.caption_prefix, photo.caption), color = NV.textSecondary, fontSize = 13.sp)
                        if (photo.lat != 0.0 || photo.lon != 0.0)
                            Text("GPS: ${String.format("%.5f", photo.lat)}, ${String.format("%.5f", photo.lon)}",
                                color = NV.textSecondary, fontSize = 12.sp)
                        if (photo.fullUrl.isNotEmpty())
                            Text("URL: ${photo.fullUrl}", color = NV.blue, fontSize = 11.sp)
                        val sdf = java.text.SimpleDateFormat("yyyy/MM/dd HH:mm:ss", java.util.Locale.getDefault())
                        Text(stringResource(R.string.time_prefix, sdf.format(java.util.Date(photo.timestamp))),
                            color = NV.textSecondary, fontSize = 12.sp)
                    }
                },
                containerColor = NV.card
            )
        }
    }
}

// =====================================================
//  任務指派 Tab
// =====================================================

@Composable
fun HQTaskAssignmentTab(viewModel: HQViewModel) {
    val tasks by viewModel.taskAssignments.collectAsState()
    val fieldUnits by viewModel.server.fieldUnits.collectAsState()
    var showCreateDialog by remember { mutableStateOf(false) }

    // Create dialog state
    var taskTitle by remember { mutableStateOf("") }
    var taskDetail by remember { mutableStateOf("") }
    var selectedDeviceID by remember { mutableStateOf("") }
    var selectedName by remember { mutableStateOf("") }
    var selectedPriority by remember { mutableStateOf(CommandPriority.ROUTINE) }

    Box(modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.task_assignment), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white)
                    Spacer(modifier = Modifier.weight(1f))
                    Text(stringResource(R.string.n_tasks, tasks.size), color = NV.textSecondary, fontSize = 12.sp)
                }
            }

            if (tasks.isEmpty()) {
                item {
                    Box(modifier = Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Icon(Icons.Default.Assignment, contentDescription = null, tint = NV.textSecondary, modifier = Modifier.size(48.dp))
                            Text(stringResource(R.string.no_tasks), color = NV.textSecondary)
                        }
                    }
                }
            }

            items(tasks, key = { it.id }) { task ->
                SectionCard(task.title) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        // Status chip
                        Box(
                            modifier = Modifier
                                .background(task.status.color.copy(alpha = 0.2f), RoundedCornerShape(4.dp))
                                .padding(horizontal = 8.dp, vertical = 2.dp)
                        ) {
                            Text(task.status.label, color = task.status.color, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        }
                        // Priority chip
                        Box(
                            modifier = Modifier
                                .background(task.priority.color.copy(alpha = 0.2f), RoundedCornerShape(4.dp))
                                .padding(horizontal = 8.dp, vertical = 2.dp)
                        ) {
                            Text(task.priority.label, color = task.priority.color, fontSize = 11.sp)
                        }
                    }
                    if (task.detail.isNotEmpty()) {
                        Text(task.detail, color = NV.textSecondary, fontSize = 12.sp)
                    }
                    Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                        Text("→ ${task.assignedName.ifEmpty { task.assignedDeviceID.takeLast(6) }}",
                            color = NV.blue, fontSize = 11.sp)
                        Text(task.timeText, color = NV.textSecondary, fontSize = 10.sp)
                    }
                }
            }
        }

        // FAB
        FloatingActionButton(
            onClick = { showCreateDialog = true },
            modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp),
            containerColor = NV.command
        ) {
            Icon(Icons.Default.Add, contentDescription = "Add", tint = Color.White)
        }

        // Create task dialog
        if (showCreateDialog) {
            AlertDialog(
                onDismissRequest = { showCreateDialog = false },
                title = { Text(stringResource(R.string.add_task), color = NV.white) },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(value = taskTitle, onValueChange = { taskTitle = it },
                            label = { Text(stringResource(R.string.label_task_title)) }, modifier = Modifier.fillMaxWidth(),
                            colors = fieldColors())
                        OutlinedTextField(value = taskDetail, onValueChange = { taskDetail = it },
                            label = { Text(stringResource(R.string.label_task_content)) }, modifier = Modifier.fillMaxWidth(),
                            colors = fieldColors(), minLines = 2)
                        // Device picker
                        Text(stringResource(R.string.label_assign_target), color = NV.textSecondary, fontSize = 12.sp)
                        if (fieldUnits.isEmpty()) {
                            Text(stringResource(R.string.no_online_units), color = NV.textSecondary, fontSize = 11.sp)
                        } else {
                            fieldUnits.filter { it.isOnline }.forEach { unit ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable { selectedDeviceID = unit.deviceID; selectedName = unit.deptCode }
                                        .background(
                                            if (selectedDeviceID == unit.deviceID) NV.command.copy(alpha = 0.2f)
                                            else Color.Transparent, RoundedCornerShape(6.dp)
                                        )
                                        .padding(8.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Icon(Icons.Default.Person, contentDescription = null, tint = NV.green, modifier = Modifier.size(16.dp))
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text("${unit.deptCode} (${unit.deviceID.takeLast(4)})", color = NV.white, fontSize = 12.sp)
                                }
                            }
                        }
                        // Priority
                        Text(stringResource(R.string.label_priority), color = NV.textSecondary, fontSize = 12.sp)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            CommandPriority.entries.forEach { p ->
                                FilterChip(
                                    selected = selectedPriority == p,
                                    onClick = { selectedPriority = p },
                                    label = { Text(p.localizedLabel(), fontSize = 11.sp) },
                                    colors = FilterChipDefaults.filterChipColors(
                                        selectedContainerColor = p.color.copy(alpha = 0.3f),
                                        selectedLabelColor = p.color
                                    )
                                )
                            }
                        }
                    }
                },
                confirmButton = {
                    TextButton(
                        onClick = {
                            if (taskTitle.isNotBlank()) {
                                viewModel.sendTaskAssignment(taskTitle, taskDetail, selectedDeviceID, selectedName, selectedPriority)
                                taskTitle = ""; taskDetail = ""; selectedDeviceID = ""; selectedName = ""
                                selectedPriority = CommandPriority.ROUTINE
                                showCreateDialog = false
                            }
                        }
                    ) { Text(stringResource(R.string.btn_assign), color = NV.command) }
                },
                dismissButton = {
                    TextButton(onClick = { showCreateDialog = false }) { Text(stringResource(R.string.btn_cancel), color = NV.textSecondary) }
                },
                containerColor = NV.card
            )
        }
    }
}

// =====================================================
//  文字廣播 Tab（含已讀回條）
// =====================================================

@Composable
fun HQBroadcastTab(viewModel: HQViewModel) {
    val broadcasts by viewModel.textBroadcasts.collectAsState()
    var broadcastMessage by remember { mutableStateOf("") }
    var selectedPriority by remember { mutableStateOf("normal") }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.text_broadcast), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white)
                Spacer(modifier = Modifier.weight(1f))
                Text(stringResource(R.string.n_broadcasts, broadcasts.size), color = NV.textSecondary, fontSize = 12.sp)
            }
        }

        // Send area
        item {
            SectionCard(stringResource(R.string.send_new_broadcast)) {
                // Priority
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.priority_prefix), color = NV.textSecondary, fontSize = 13.sp)
                    FilterChip(
                        selected = selectedPriority == "normal",
                        onClick = { selectedPriority = "normal" },
                        label = { Text(stringResource(R.string.priority_normal), fontSize = 12.sp) },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = NV.command.copy(alpha = 0.3f),
                            selectedLabelColor = NV.command
                        )
                    )
                    FilterChip(
                        selected = selectedPriority == "urgent",
                        onClick = { selectedPriority = "urgent" },
                        label = { Text(stringResource(R.string.priority_urgent), fontSize = 12.sp) },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = NV.danger.copy(alpha = 0.3f),
                            selectedLabelColor = NV.danger
                        )
                    )
                }
                // Message input
                OutlinedTextField(
                    value = broadcastMessage, onValueChange = { broadcastMessage = it },
                    label = { Text(stringResource(R.string.label_broadcast_message)) }, modifier = Modifier.fillMaxWidth(),
                    colors = fieldColors(), minLines = 3
                )
                // Send button
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    Button(
                        onClick = {
                            if (broadcastMessage.isNotBlank()) {
                                viewModel.sendTextBroadcast(broadcastMessage.trim(), selectedPriority)
                                broadcastMessage = ""
                            }
                        },
                        enabled = broadcastMessage.isNotBlank(),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (selectedPriority == "urgent") NV.danger else NV.command
                        )
                    ) {
                        Icon(Icons.Default.Campaign, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(stringResource(R.string.btn_send_broadcast))
                    }
                }
            }
        }

        // History
        if (broadcasts.isEmpty()) {
            item {
                Box(modifier = Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Default.Campaign, contentDescription = null, tint = NV.textSecondary, modifier = Modifier.size(48.dp))
                        Text(stringResource(R.string.no_broadcasts), color = NV.textSecondary)
                    }
                }
            }
        }

        items(broadcasts, key = { it.id }) { broadcast ->
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(NV.card, NVShape.card)
                    .border(
                        1.dp,
                        if (broadcast.priority == "urgent") NV.danger.copy(alpha = 0.5f) else NV.cardBorder,
                        NVShape.card
                    )
                    .padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (broadcast.priority == "urgent") {
                        Icon(Icons.Default.Warning, contentDescription = null, tint = NV.danger, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(stringResource(R.string.priority_urgent), color = NV.danger, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        Spacer(modifier = Modifier.width(8.dp))
                    }
                    Text(broadcast.senderName, color = NV.white, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.weight(1f))
                    Text(broadcast.timeText, color = NV.textSecondary, fontSize = 10.sp)
                }
                Text(broadcast.message, color = NV.white, fontSize = 13.sp)
                // Read receipts
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Default.DoneAll, contentDescription = null, tint = NV.green, modifier = Modifier.size(14.dp))
                    val readCount = broadcast.readBy.size
                    val fieldUnits by viewModel.server.fieldUnits.collectAsState()
                    val total = fieldUnits.count { it.isOnline }
                    Text(stringResource(R.string.read_receipt, readCount, total), color = NV.textSecondary, fontSize = 11.sp)
                    if (total > 0) {
                        LinearProgressIndicator(
                            progress = if (total > 0) readCount.toFloat() / total else 0f,
                            modifier = Modifier.width(80.dp).height(4.dp),
                            color = NV.green,
                            trackColor = NV.cardBorder.copy(alpha = 0.3f)
                        )
                    }
                }
            }
        }
    }
}

// =====================================================
//  電台監聽 Tab
// =====================================================

@Composable
fun HQRadioTab(viewModel: HQViewModel) {
    val activeBroadcaster by viewModel.activeBroadcaster.collectAsState()
    val radioReports by viewModel.hqRadioReports.collectAsState()
    val isActive = activeBroadcaster != null

    // Voice recording states
    val isRecording by viewModel.isRecording.collectAsState()
    val isTranscribing by viewModel.isTranscribing.collectAsState()
    val lastTranscription by viewModel.lastTranscription.collectAsState()
    val voiceError by viewModel.voiceError.collectAsState()
    val recordingDurationMs by viewModel.recordingDurationMs.collectAsState()
    val isBackendConnected by viewModel.isBackendConnected.collectAsState()

    // Ripple animation
    val infiniteTransition = rememberInfiniteTransition(label = "radio_ripple")
    val rippleAlpha by infiniteTransition.animateFloat(
        initialValue = 0.6f, targetValue = 0f, animationSpec = infiniteRepeatable(
            animation = tween(1500, easing = LinearEasing), repeatMode = RepeatMode.Restart
        ), label = "ripple_alpha"
    )
    val rippleSize by infiniteTransition.animateFloat(
        initialValue = 30f, targetValue = 80f, animationSpec = infiniteRepeatable(
            animation = tween(1500, easing = LinearEasing), repeatMode = RepeatMode.Restart
        ), label = "ripple_size"
    )

    Row(modifier = Modifier.fillMaxSize()) {
        // Left panel: live status + voice recording
        Column(
            modifier = Modifier
                .width(320.dp)
                .fillMaxHeight()
                .background(NV.surface.copy(alpha = 0.5f))
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(stringResource(R.string.radio_monitor), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white)

            // Broadcaster card with ripple
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(NV.card, NVShape.card)
                    .border(1.dp, if (isActive) NV.green.copy(alpha = 0.5f) else NV.cardBorder, NVShape.card)
                    .padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box(contentAlignment = Alignment.Center, modifier = Modifier.size(100.dp)) {
                    if (isActive) {
                        // Animated ripples
                        Canvas(modifier = Modifier.size(100.dp)) {
                            drawCircle(
                                color = NV.green.copy(alpha = rippleAlpha * 0.3f),
                                radius = rippleSize,
                                style = Stroke(width = 2f)
                            )
                            drawCircle(
                                color = NV.green.copy(alpha = rippleAlpha * 0.2f),
                                radius = rippleSize * 1.3f,
                                style = Stroke(width = 1.5f)
                            )
                        }
                    }
                    Box(
                        modifier = Modifier
                            .size(56.dp)
                            .clip(CircleShape)
                            .background(if (isActive) NV.green else NV.greenDim),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            if (isActive) Icons.Default.Mic else Icons.Default.MicOff,
                            contentDescription = null, tint = Color.White, modifier = Modifier.size(28.dp)
                        )
                    }
                }

                if (isActive) {
                    Text(activeBroadcaster?.senderName ?: stringResource(R.string.field_device),
                        color = NV.green, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    Text(stringResource(R.string.broadcasting), color = NV.green.copy(alpha = 0.7f), fontSize = 12.sp)
                } else {
                    Text(stringResource(R.string.standby), color = NV.textSecondary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    Text(stringResource(R.string.waiting_ptt), color = NV.textSecondary.copy(alpha = 0.7f), fontSize = 12.sp)
                }
            }

            // === HQ 語音錄製 + Whisper 上傳 ===
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(NV.card, NVShape.card)
                    .border(1.dp, if (isRecording) Color(0xFFD13838).copy(alpha = 0.5f) else NV.cardBorder, NVShape.card)
                    .padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(stringResource(R.string.hq_voice_transcription), fontSize = 14.sp, fontWeight = FontWeight.Bold, color = NV.white)

                // Recording duration
                if (isRecording) {
                    val secs = recordingDurationMs / 1000
                    val mins = secs / 60
                    val remainSecs = secs % 60
                    Text(
                        String.format("%02d:%02d", mins, remainSecs),
                        fontSize = 24.sp, fontWeight = FontWeight.Bold,
                        color = Color(0xFFD13838)
                    )
                }

                // Record button
                Box(
                    modifier = Modifier
                        .size(64.dp)
                        .clip(CircleShape)
                        .background(
                            when {
                                isRecording -> Color(0xFFD13838)
                                isTranscribing -> NV.command
                                else -> NV.green
                            }
                        )
                        .clickable(enabled = !isTranscribing) {
                            if (isRecording) viewModel.stopVoiceRecording()
                            else viewModel.startVoiceRecording()
                        },
                    contentAlignment = Alignment.Center
                ) {
                    if (isTranscribing) {
                        CircularProgressIndicator(
                            color = Color.White,
                            modifier = Modifier.size(28.dp),
                            strokeWidth = 2.dp
                        )
                    } else {
                        Icon(
                            if (isRecording) Icons.Default.Stop else Icons.Default.Mic,
                            contentDescription = if (isRecording) "Stop" else "Record",
                            tint = Color.White,
                            modifier = Modifier.size(28.dp)
                        )
                    }
                }

                Text(
                    when {
                        isRecording -> stringResource(R.string.recording_press_stop)
                        isTranscribing -> stringResource(R.string.whisper_transcribing)
                        else -> stringResource(R.string.press_to_transcribe)
                    },
                    color = NV.textSecondary, fontSize = 11.sp
                )

                if (!isBackendConnected) {
                    Text(stringResource(R.string.backend_not_connected), color = NV.danger, fontSize = 10.sp)
                }

                // Show error
                voiceError?.let { err ->
                    Text(err, color = NV.danger, fontSize = 10.sp, maxLines = 2)
                }

                // Show last transcription
                lastTranscription?.let { result ->
                    if (result.text.isNotEmpty()) {
                        Box(modifier = Modifier.fillMaxWidth().height(0.5.dp).background(NV.cardBorder))
                        Text(stringResource(R.string.latest_transcription), color = NV.textSecondary, fontSize = 10.sp)
                        Text(
                            result.text,
                            color = NV.white, fontSize = 12.sp, maxLines = 3,
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(NV.surface, RoundedCornerShape(6.dp))
                                .padding(8.dp)
                        )
                    }
                }
            }
        }

        // Right panel: transcription log
        Column(
            modifier = Modifier.weight(1f).fillMaxHeight().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.TextSnippet, contentDescription = null, tint = NV.blue, modifier = Modifier.size(20.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text(stringResource(R.string.voice_transcription_log), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = NV.white)
                Spacer(modifier = Modifier.weight(1f))
                Text(stringResource(R.string.n_entries, radioReports.size), color = NV.textSecondary, fontSize = 11.sp)
            }

            if (radioReports.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Default.Radio, contentDescription = null, tint = NV.textSecondary, modifier = Modifier.size(48.dp))
                        Text(stringResource(R.string.no_transcription_log), color = NV.textSecondary)
                    }
                }
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(radioReports, key = { it.id }) { report ->
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(NV.card, RoundedCornerShape(8.dp))
                                .border(1.dp, NV.cardBorder, RoundedCornerShape(8.dp))
                                .padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Default.RecordVoiceOver, contentDescription = null,
                                    tint = NV.green, modifier = Modifier.size(14.dp))
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(report.senderName, color = NV.green, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                Spacer(modifier = Modifier.width(8.dp))
                                Box(
                                    modifier = Modifier
                                        .background(report.sourceType.let {
                                            if (it == RadioSourceType.LIVE) NV.green.copy(alpha = 0.2f)
                                            else NV.blue.copy(alpha = 0.2f)
                                        }, RoundedCornerShape(4.dp))
                                        .padding(horizontal = 6.dp, vertical = 1.dp)
                                ) {
                                    Text(report.sourceType.label, fontSize = 9.sp,
                                        color = if (report.sourceType == RadioSourceType.LIVE) NV.green else NV.blue)
                                }
                                Spacer(modifier = Modifier.weight(1f))
                                Text(report.timeText, color = NV.textSecondary, fontSize = 10.sp)
                            }
                            if (report.transcription.isNotEmpty()) {
                                Text(report.transcription, color = NV.white, fontSize = 13.sp)
                            }
                        }
                    }
                }
            }
        }
    }
}

// =====================================================
//  傷患警告 Tab
// =====================================================

@Composable
fun HQPatientWarningTab(viewModel: HQViewModel) {
    val warnings by viewModel.patientWarnings.collectAsState()
    val urgentCount = warnings.count { it.triageLevel.uppercase() == "RED" }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.patient_warning), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white)
                Spacer(modifier = Modifier.weight(1f))
                if (urgentCount > 0) {
                    Icon(Icons.Default.Warning, contentDescription = null, tint = NV.danger, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(stringResource(R.string.n_critical, urgentCount), color = NV.danger, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.width(12.dp))
                }
                Text(stringResource(R.string.n_warnings, warnings.size), color = NV.textSecondary, fontSize = 12.sp)
            }
        }

        if (warnings.isEmpty()) {
            item {
                Box(modifier = Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Default.MonitorHeart, contentDescription = null, tint = NV.textSecondary, modifier = Modifier.size(48.dp))
                        Text(stringResource(R.string.no_patient_warnings), color = NV.textSecondary)
                    }
                }
            }
        }

        items(warnings, key = { it.id }) { warning ->
            val levelColor = warning.triageColor
            val levelText = when (warning.triageLevel.uppercase()) {
                "RED" -> stringResource(R.string.level_critical)
                "YELLOW" -> stringResource(R.string.level_moderate)
                "GREEN" -> stringResource(R.string.level_mild)
                "BLACK" -> stringResource(R.string.level_deceased)
                else -> warning.triageLevel
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(NV.card, NVShape.card)
                    .border(1.dp, levelColor.copy(alpha = 0.4f), NVShape.card)
                    .padding(12.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                // Severity bar
                Box(
                    modifier = Modifier
                        .width(6.dp)
                        .height(60.dp)
                        .background(levelColor, RoundedCornerShape(3.dp))
                )
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Default.Favorite, contentDescription = null, tint = levelColor, modifier = Modifier.size(16.dp))
                        Text("Patient ${warning.patientID.takeLast(6)}", color = NV.white, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                        Box(
                            modifier = Modifier
                                .background(levelColor.copy(alpha = 0.2f), RoundedCornerShape(4.dp))
                                .padding(horizontal = 8.dp, vertical = 2.dp)
                        ) {
                            Text(levelText, color = levelColor, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                    if (warning.deviceID.isNotEmpty()) {
                        Text(stringResource(R.string.source_prefix, warning.deviceID.takeLast(8)), color = NV.textSecondary, fontSize = 11.sp)
                    }
                    Text(warning.timeText, color = NV.textSecondary, fontSize = 10.sp)
                }
            }
        }
    }
}
