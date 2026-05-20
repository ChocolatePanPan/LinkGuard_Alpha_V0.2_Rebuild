package com.linkguard.hq.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.res.stringResource
import com.linkguard.hq.R
import com.linkguard.hq.model.*
import com.linkguard.hq.viewmodel.HQViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HQVictimOverviewTab(viewModel: HQViewModel) {
    val fieldUnits by viewModel.server.fieldUnits.collectAsState()
    val priorities by viewModel.victimPriorities.collectAsState()
    val notes by viewModel.victimNotes.collectAsState()
    val statuses by viewModel.victimStatuses.collectAsState()
    val descriptions by viewModel.victimDescriptions.collectAsState()

    var searchText by remember { mutableStateOf("") }
    var filterOnlineOnly by remember { mutableStateOf(false) }
    var filterSOSOnly by remember { mutableStateOf(false) }
    var filterPriority by remember { mutableStateOf<VictimPriority?>(null) }
    var filterStatus by remember { mutableStateOf<VictimStatus?>(null) }
    var sortBy by remember { mutableStateOf("priority") }
    var selectedVictimID by remember { mutableStateOf<String?>(null) }

    // 觸發重組用
    val _unused = fieldUnits

    val allRecords = viewModel.allVictimRecords()

    val filtered = remember(allRecords, searchText, filterOnlineOnly, filterSOSOnly, filterPriority, filterStatus, sortBy) {
        var result = allRecords.toMutableList()
        if (filterOnlineOnly) result = result.filter { it.isOnline }.toMutableList()
        if (filterSOSOnly) result = result.filter { it.isSOS }.toMutableList()
        filterPriority?.let { p -> result = result.filter { it.priority == p }.toMutableList() }
        filterStatus?.let { s -> result = result.filter { it.status == s }.toMutableList() }
        if (searchText.isNotBlank()) {
            result = result.filter {
                it.id.contains(searchText, true) ||
                    it.sourceDeviceID.contains(searchText, true) ||
                    it.sourceDeptCode.contains(searchText, true) ||
                    it.patientName.contains(searchText, true) ||
                    it.location.contains(searchText, true)
            }.toMutableList()
        }
        when (sortBy) {
            "priority" -> result.sortByDescending { it.priority.value }
            "heartRate" -> result.sortByDescending { if (it.heartRate == 0) -1 else it.heartRate }
            "signal" -> result.sortByDescending { it.rssi }
            "battery" -> result.sortBy { it.battery }
        }
        result.toList()
    }

    val selectedRecord = if (selectedVictimID != null) allRecords.find { it.id == selectedVictimID } else null

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        // Header
        item {
            Text(stringResource(R.string.victim_overview_title), color = NV.warning, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.height(4.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                VictimStat(stringResource(R.string.stat_total), "${allRecords.size}", NV.warning)
                VictimStat(stringResource(R.string.stat_online), "${allRecords.count { it.isOnline }}", NV.green)
                VictimStat("SOS", "${allRecords.count { it.isSOS }}", NV.danger)
                VictimStat(stringResource(R.string.stat_critical), "${allRecords.count { it.priority == VictimPriority.CRITICAL }}", Color.Red)
            }
        }

        // 篩選
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = searchText,
                    onValueChange = { searchText = it },
                    label = { Text(stringResource(R.string.search_victim_hint)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    colors = hqTextFieldColors()
                )
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    FilterChip(selected = filterOnlineOnly, onClick = { filterOnlineOnly = !filterOnlineOnly },
                        label = { Text(stringResource(R.string.filter_online_only), fontSize = 11.sp) })
                    FilterChip(selected = filterSOSOnly, onClick = { filterSOSOnly = !filterSOSOnly },
                        label = { Text(stringResource(R.string.filter_sos_only), fontSize = 11.sp) })
                    VictimPriority.entries.forEach { p ->
                        FilterChip(
                            selected = filterPriority == p,
                            onClick = { filterPriority = if (filterPriority == p) null else p },
                            label = { Text(p.localizedLabel(), fontSize = 11.sp) }
                        )
                    }
                }
                // 處置狀態篩選
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    VictimStatus.entries.forEach { s ->
                        FilterChip(
                            selected = filterStatus == s,
                            onClick = { filterStatus = if (filterStatus == s) null else s },
                            label = { Text(s.localizedLabel(), fontSize = 10.sp) }
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("priority" to stringResource(R.string.sort_priority), "heartRate" to stringResource(R.string.sort_heart_rate), "signal" to stringResource(R.string.sort_signal), "battery" to stringResource(R.string.sort_battery)).forEach { (key, label) ->
                        FilterChip(
                            selected = sortBy == key,
                            onClick = { sortBy = key },
                            label = { Text(label, fontSize = 11.sp) }
                        )
                    }
                }
            }
        }

        // 列表
        if (filtered.isEmpty()) {
            item {
                Text(stringResource(R.string.no_victim_data), color = NV.textSecondary, fontSize = 13.sp,
                    modifier = Modifier.padding(vertical = 20.dp))
            }
        } else {
            items(filtered, key = { it.id }) { record ->
                VictimRecordCard(
                    record = record,
                    isSelected = selectedVictimID == record.id,
                    onTap = { selectedVictimID = if (selectedVictimID == record.id) null else record.id },
                    onSetPriority = { viewModel.setVictimPriority(record.id, it) }
                )
            }
        }

        // 詳情面板（展開在列表下方）
        if (selectedRecord != null) {
            item {
                VictimDetailCard(
                    record = selectedRecord,
                    onSetPriority = { viewModel.setVictimPriority(selectedRecord.id, it) },
                    onSetStatus = { viewModel.setVictimStatus(selectedRecord.id, it) },
                    note = notes[selectedRecord.id] ?: "",
                    onNoteChange = { viewModel.setVictimNote(selectedRecord.id, it) },
                    description = descriptions[selectedRecord.id] ?: "",
                    onDescriptionChange = { viewModel.setVictimDescription(selectedRecord.id, it) }
                )
            }
        }
    }
}

@Composable
private fun VictimStat(label: String, value: String, color: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = color)
        Text(label, fontSize = 10.sp, color = NV.textSecondary)
    }
}

@Composable
private fun VictimRecordCard(
    record: HQVictimRecord,
    isSelected: Boolean,
    onTap: () -> Unit,
    onSetPriority: (VictimPriority) -> Unit
) {
    val priorityColor = when (record.priority) {
        VictimPriority.UNSET -> NV.textSecondary
        VictimPriority.LOW -> Color(0xFF4CAF50)
        VictimPriority.MEDIUM -> Color(0xFFFFEB3B)
        VictimPriority.HIGH -> Color(0xFFFF9800)
        VictimPriority.CRITICAL -> Color(0xFFF44336)
    }

    val heartColor = when {
        record.heartRate <= 0 -> NV.textSecondary
        record.heartRate < 50 || record.heartRate > 120 -> NV.danger
        record.heartRate < 60 || record.heartRate > 100 -> NV.warning
        else -> NV.green
    }

    HQCard(
        borderColor = if (isSelected) NV.command else NV.cardBorder
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { onTap() }
                .padding(6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // 優先級圓點
            Box(Modifier.size(10.dp).clip(CircleShape).background(priorityColor))

            // 上線/SOS 指示
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(24.dp)) {
                Box(Modifier.size(6.dp).clip(CircleShape).background(if (record.isOnline) NV.green else NV.textSecondary))
                if (record.isSOS) {
                    Text("SOS", fontSize = 7.sp, fontWeight = FontWeight.Black, color = NV.danger)
                }
            }

            // 主要資訊
            Column(modifier = Modifier.weight(1f)) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(record.id, fontWeight = FontWeight.Bold, fontSize = 14.sp, color = NV.white)
                    if (record.patientName.isNotEmpty()) {
                        Text(record.patientName, fontSize = 11.sp, color = NV.textSecondary)
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(record.sourceDeptCode, fontSize = 10.sp, color = NV.team,
                        modifier = Modifier.clip(RoundedCornerShape(2.dp))
                            .background(NV.team.copy(alpha = 0.2f)).padding(horizontal = 3.dp, vertical = 1.dp))
                    Text("← ${record.sourceDeviceID}", fontSize = 10.sp, color = NV.textSecondary)
                }
                // 處置狀態標籤
                val statusColor = when (record.status) {
                    VictimStatus.PENDING -> NV.textSecondary
                    VictimStatus.ON_SCENE -> Color(0xFFFF9800)
                    VictimStatus.WAITING_AMBULANCE -> Color(0xFFFFEB3B)
                    VictimStatus.EN_ROUTE -> Color(0xFF2196F3)
                    VictimStatus.HOSPITALIZED -> Color(0xFF00BCD4)
                    VictimStatus.RESCUED -> Color(0xFF4CAF50)
                    VictimStatus.DECEASED -> Color(0xFFF44336)
                }
                Text(record.status.localizedLabel(), fontSize = 9.sp, fontWeight = FontWeight.Medium,
                    color = statusColor,
                    modifier = Modifier.clip(RoundedCornerShape(2.dp))
                        .background(statusColor.copy(alpha = 0.15f))
                        .padding(horizontal = 4.dp, vertical = 1.dp))
            }

            // 生命跡象
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    if (record.heartRate > 0) "${record.heartRate} bpm" else "-- bpm",
                    fontSize = 12.sp, color = heartColor, fontWeight = FontWeight.Bold
                )
                Text("${record.battery}%", fontSize = 11.sp,
                    color = if (record.battery < 20) NV.danger else NV.textSecondary)
                Text("${record.rssi.toInt()} dBm", fontSize = 10.sp, color = NV.textSecondary)
            }

            // 優先級快速選擇
            var expanded by remember { mutableStateOf(false) }
            Box {
                IconButton(onClick = { expanded = true }, modifier = Modifier.size(28.dp)) {
                    Icon(Icons.Default.PriorityHigh, contentDescription = null,
                        tint = priorityColor, modifier = Modifier.size(18.dp))
                }
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    VictimPriority.entries.forEach { p ->
                        DropdownMenuItem(
                            text = { Text(p.localizedLabel()) },
                            onClick = { onSetPriority(p); expanded = false }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun VictimDetailCard(
    record: HQVictimRecord,
    onSetPriority: (VictimPriority) -> Unit,
    onSetStatus: (VictimStatus) -> Unit,
    note: String,
    onNoteChange: (String) -> Unit,
    description: String,
    onDescriptionChange: (String) -> Unit
) {
    val heartColor = when {
        record.heartRate <= 0 -> NV.textSecondary
        record.heartRate < 50 || record.heartRate > 120 -> NV.danger
        record.heartRate < 60 || record.heartRate > 100 -> NV.warning
        else -> NV.green
    }

    HQCard(borderColor = NV.command) {
        Column(
            modifier = Modifier.padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // 標題
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column {
                    Text(record.id, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = NV.white)
                    if (record.patientName.isNotEmpty()) {
                        Text(record.patientName, fontSize = 13.sp, color = NV.textSecondary)
                    }
                }
                Spacer(modifier = Modifier.width(8.dp))
                if (record.hasPatientReport) {
                    Text(stringResource(R.string.patient_report_badge), fontSize = 9.sp, fontWeight = FontWeight.Bold, color = Color(0xFF2196F3),
                        modifier = Modifier.clip(RoundedCornerShape(4.dp))
                            .background(Color(0xFF2196F3).copy(alpha = 0.15f))
                            .padding(horizontal = 5.dp, vertical = 2.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                }
                if (record.isSOS) {
                    Text("SOS", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = NV.danger,
                        modifier = Modifier.clip(RoundedCornerShape(4.dp))
                            .background(NV.danger.copy(alpha = 0.2f)).padding(horizontal = 6.dp, vertical = 2.dp))
                }
                Box(Modifier.size(8.dp).clip(CircleShape).background(if (record.isOnline) NV.green else NV.textSecondary))
                Text(if (record.isOnline) stringResource(R.string.status_online) else stringResource(R.string.status_offline), fontSize = 11.sp,
                    color = if (record.isOnline) NV.green else NV.textSecondary)
            }

            // 處置狀態
            Text(stringResource(R.string.treatment_status), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = NV.white)
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                VictimStatus.entries.forEach { s ->
                    val sColor = when (s) {
                        VictimStatus.PENDING -> NV.textSecondary
                        VictimStatus.ON_SCENE -> Color(0xFFFF9800)
                        VictimStatus.WAITING_AMBULANCE -> Color(0xFFFFEB3B)
                        VictimStatus.EN_ROUTE -> Color(0xFF2196F3)
                        VictimStatus.HOSPITALIZED -> Color(0xFF00BCD4)
                        VictimStatus.RESCUED -> Color(0xFF4CAF50)
                        VictimStatus.DECEASED -> Color(0xFFF44336)
                    }
                    val isActive = record.status == s
                    OutlinedButton(
                        onClick = { onSetStatus(s) },
                        modifier = Modifier.weight(1f),
                        contentPadding = PaddingValues(horizontal = 2.dp, vertical = 4.dp),
                        colors = ButtonDefaults.outlinedButtonColors(
                            containerColor = if (isActive) sColor.copy(alpha = 0.2f) else Color.Transparent
                        ),
                        border = if (isActive) androidx.compose.foundation.BorderStroke(1.dp, sColor)
                            else androidx.compose.foundation.BorderStroke(1.dp, NV.textSecondary.copy(alpha = 0.3f))
                    ) {
                        Text(s.localizedLabel(), fontSize = 9.sp, color = if (isActive) sColor else NV.textSecondary)
                    }
                }
            }

            // 生命跡象
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                MetricBox(stringResource(R.string.sort_heart_rate), if (record.heartRate > 0) "${record.heartRate} bpm" else "--", heartColor)
                MetricBox(stringResource(R.string.sort_battery), "${record.battery}%", if (record.battery < 20) NV.danger else NV.green)
                MetricBox(stringResource(R.string.sort_signal), "${record.rssi.toInt()} dBm",
                    if (record.rssi > -70) NV.green else if (record.rssi > -90) NV.warning else NV.danger)
            }

            // 來源 & 位置
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.report_device), fontSize = 12.sp, color = NV.textSecondary)
                Text(record.sourceDeviceID, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = NV.white)
                Text(record.sourceDeptCode, fontSize = 10.sp, color = NV.team,
                    modifier = Modifier.clip(RoundedCornerShape(2.dp))
                        .background(NV.team.copy(alpha = 0.2f)).padding(horizontal = 4.dp, vertical = 1.dp))
            }
            if (record.location.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.label_location_colon), fontSize = 12.sp, color = NV.textSecondary)
                    Text(record.location, fontSize = 12.sp, color = NV.white)
                }
            }

            // 優先級選擇
            Text(stringResource(R.string.label_priority), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = NV.white)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                VictimPriority.entries.forEach { p ->
                    val pColor = when (p) {
                        VictimPriority.UNSET -> NV.textSecondary
                        VictimPriority.LOW -> Color(0xFF4CAF50)
                        VictimPriority.MEDIUM -> Color(0xFFFFEB3B)
                        VictimPriority.HIGH -> Color(0xFFFF9800)
                        VictimPriority.CRITICAL -> Color(0xFFF44336)
                    }
                    val isActive = record.priority == p
                    OutlinedButton(
                        onClick = { onSetPriority(p) },
                        modifier = Modifier.weight(1f),
                        colors = ButtonDefaults.outlinedButtonColors(
                            containerColor = if (isActive) pColor.copy(alpha = 0.2f) else Color.Transparent
                        ),
                        border = if (isActive) androidx.compose.foundation.BorderStroke(1.dp, pColor)
                            else androidx.compose.foundation.BorderStroke(1.dp, NV.textSecondary.copy(alpha = 0.3f))
                    ) {
                        Text(p.localizedLabel(), fontSize = 11.sp, color = if (isActive) pColor else NV.textSecondary)
                    }
                }
            }

            // 描述
            var editingDesc by remember(record.id) { mutableStateOf(description) }
            OutlinedTextField(
                value = editingDesc,
                onValueChange = { editingDesc = it },
                label = { Text(stringResource(R.string.description_record)) },
                modifier = Modifier.fillMaxWidth(),
                colors = hqTextFieldColors(),
                maxLines = 5
            )
            Button(
                onClick = { onDescriptionChange(editingDesc) },
                colors = ButtonDefaults.buttonColors(containerColor = NV.command),
                modifier = Modifier.align(Alignment.End)
            ) {
                Text(stringResource(R.string.save_description), fontSize = 12.sp)
            }

            // 備註
            var editingNote by remember(record.id) { mutableStateOf(note) }
            OutlinedTextField(
                value = editingNote,
                onValueChange = { editingNote = it },
                label = { Text(stringResource(R.string.label_notes)) },
                modifier = Modifier.fillMaxWidth(),
                colors = hqTextFieldColors(),
                maxLines = 3
            )
            Button(
                onClick = { onNoteChange(editingNote) },
                colors = ButtonDefaults.buttonColors(containerColor = NV.command),
                modifier = Modifier.align(Alignment.End)
            ) {
                Text(stringResource(R.string.save_note), fontSize = 12.sp)
            }
        }
    }
}

@Composable
private fun MetricBox(label: String, value: String, color: Color) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(color.copy(alpha = 0.08f))
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        Text(value, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = color)
        Text(label, fontSize = 10.sp, color = NV.textSecondary)
    }
}
