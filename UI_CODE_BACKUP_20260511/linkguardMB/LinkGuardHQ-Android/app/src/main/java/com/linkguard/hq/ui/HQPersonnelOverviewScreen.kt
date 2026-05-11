package com.linkguard.hq.ui

import androidx.compose.foundation.background
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.res.stringResource
import com.linkguard.hq.R
import com.linkguard.hq.model.*
import com.linkguard.hq.viewmodel.HQViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HQPersonnelOverviewTab(viewModel: HQViewModel) {
    val fieldUnits by viewModel.server.fieldUnits.collectAsState()
    val personnelAssignments by viewModel.personnelAssignments.collectAsState()
    var searchText by remember { mutableStateOf("") }
    var filterOnlineOnly by remember { mutableStateOf(false) }

    val allTeamMembers = remember(fieldUnits) {
        val seen = mutableSetOf<String>()
        fieldUnits.flatMap { unit ->
            unit.teamMembers.filter { seen.add(it.id) }.map { it to unit.deviceID }
        }
    }

    val onlineCount = fieldUnits.count { it.isOnline }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Header
        item {
            Text(stringResource(R.string.personnel_overview), color = NV.team, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.height(4.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                OverviewStat(stringResource(R.string.stat_field_devices), "${fieldUnits.size}", NV.team)
                OverviewStat(stringResource(R.string.stat_online), "$onlineCount", NV.green)
                OverviewStat(stringResource(R.string.stat_team_members_label), "${allTeamMembers.size}", NV.info)
                OverviewStat(stringResource(R.string.stat_assignment), "${personnelAssignments.size}", NV.command)
            }
        }

        // 搜尋 & 篩選
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField(
                    value = searchText,
                    onValueChange = { searchText = it },
                    label = { Text(stringResource(R.string.search_personnel_hint)) },
                    singleLine = true,
                    modifier = Modifier.weight(1f),
                    colors = hqTextFieldColors()
                )
                FilterChip(
                    selected = filterOnlineOnly,
                    onClick = { filterOnlineOnly = !filterOnlineOnly },
                    label = { Text(stringResource(R.string.filter_online_only), fontSize = 11.sp) }
                )
            }
        }

        // 外勤裝置區段
        item {
            Text(stringResource(R.string.section_field_devices), color = NV.team, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        }

        val filteredUnits = fieldUnits.filter { unit ->
            (!filterOnlineOnly || unit.isOnline) &&
            (searchText.isBlank() || unit.deviceID.contains(searchText, true) || unit.deptCode.contains(searchText, true))
        }
        if (filteredUnits.isEmpty()) {
            item {
                Text(stringResource(R.string.no_matching_devices), color = NV.textSecondary, fontSize = 12.sp)
            }
        } else {
            items(filteredUnits, key = { it.id }) { unit ->
                FieldUnitOverviewCard(unit)
            }
        }

        // 團隊成員區段
        item {
            Spacer(modifier = Modifier.height(8.dp))
            Text(stringResource(R.string.section_team_lora), color = NV.info, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        }

        val filteredTeam = allTeamMembers.filter { (member, sourceDevice) ->
            (!filterOnlineOnly || member.isOnline) &&
            (searchText.isBlank() || member.id.contains(searchText, true) ||
                member.deptCode.contains(searchText, true) || sourceDevice.contains(searchText, true))
        }
        if (filteredTeam.isEmpty()) {
            item {
                Text(stringResource(R.string.no_matching_team), color = NV.textSecondary, fontSize = 12.sp)
            }
        } else {
            items(filteredTeam, key = { it.first.id }) { (member, sourceDevice) ->
                TeamMemberOverviewCard(member, sourceDevice)
            }
        }

        // 人員配置區段
        item {
            Spacer(modifier = Modifier.height(8.dp))
            Text(stringResource(R.string.section_assignment), color = NV.command, fontSize = 14.sp, fontWeight = FontWeight.Bold)
        }

        val filteredAssignments = personnelAssignments.filter { a ->
            searchText.isBlank() || a.name.contains(searchText, true) ||
                a.role.label.contains(searchText, true) || a.assignedZone.contains(searchText, true)
        }
        if (filteredAssignments.isEmpty()) {
            item {
                Text(stringResource(R.string.no_assignment), color = NV.textSecondary, fontSize = 12.sp)
            }
        } else {
            items(filteredAssignments, key = { it.id }) { assignment ->
                PersonnelAssignmentOverviewCard(assignment)
            }
        }
    }
}

@Composable
private fun OverviewStat(label: String, value: String, color: androidx.compose.ui.graphics.Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = color)
        Text(label, fontSize = 10.sp, color = NV.textSecondary)
    }
}

@Composable
private fun FieldUnitOverviewCard(unit: ConnectedFieldUnit) {
    HQCard {
        Row(
            modifier = Modifier.fillMaxWidth().padding(4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Box(
                Modifier.size(8.dp).clip(CircleShape)
                    .background(if (unit.isOnline) NV.green else NV.textSecondary)
            )
            Column(modifier = Modifier.weight(1f)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(unit.deviceID, fontWeight = FontWeight.Bold, fontSize = 14.sp, color = NV.white)
                    Text(
                        unit.deptCode, fontSize = 10.sp, color = NV.team,
                        modifier = Modifier.clip(RoundedCornerShape(2.dp))
                            .background(NV.team.copy(alpha = 0.2f)).padding(horizontal = 4.dp, vertical = 1.dp)
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("${unit.battery}%", fontSize = 11.sp, color = if (unit.battery < 20) NV.danger else NV.textSecondary)
                    Text(stringResource(R.string.n_victims, unit.victims.size), fontSize = 11.sp, color = NV.textSecondary)
                    Text(stringResource(R.string.n_team_members, unit.teamMembers.size), fontSize = 11.sp, color = NV.textSecondary)
                    if (unit.sosCount > 0) {
                        Text("SOS:${unit.sosCount}", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = NV.danger)
                    }
                }
            }
        }
    }
}

@Composable
private fun TeamMemberOverviewCard(member: TeamSummary, sourceDevice: String) {
    HQCard {
        Row(
            modifier = Modifier.fillMaxWidth().padding(4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Box(
                Modifier.size(6.dp).clip(CircleShape)
                    .background(if (member.isOnline) NV.green else NV.textSecondary)
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(member.id, fontWeight = FontWeight.Bold, fontSize = 13.sp, color = NV.white)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        member.deptCode, fontSize = 10.sp, color = NV.team,
                        modifier = Modifier.clip(RoundedCornerShape(2.dp))
                            .background(NV.team.copy(alpha = 0.2f)).padding(horizontal = 4.dp, vertical = 1.dp)
                    )
                    Text("← $sourceDevice", fontSize = 10.sp, color = NV.textSecondary)
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                Text("${member.battery}%", fontSize = 11.sp, color = if (member.battery < 20) NV.danger else NV.textSecondary)
                Text(stringResource(R.string.n_victims, member.victimCount), fontSize = 10.sp, color = NV.textSecondary)
            }
        }
    }
}

@Composable
private fun PersonnelAssignmentOverviewCard(assignment: PersonnelAssignment) {
    val isFieldSynced = assignment.id.startsWith("field-")
    HQCard {
        Row(
            modifier = Modifier.fillMaxWidth().padding(4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(assignment.role.icon, fontSize = 16.sp)
            Column(modifier = Modifier.weight(1f)) {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(assignment.name, fontWeight = FontWeight.Bold, fontSize = 13.sp, color = NV.white)
                    if (isFieldSynced) {
                        Text(
                            "外勤", fontSize = 9.sp, color = NV.team,
                            modifier = Modifier.clip(RoundedCornerShape(2.dp))
                                .background(NV.team.copy(alpha = 0.2f)).padding(horizontal = 4.dp, vertical = 1.dp)
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        assignment.role.localizedLabel(), fontSize = 10.sp, color = NV.command,
                        modifier = Modifier.clip(RoundedCornerShape(2.dp))
                            .background(NV.command.copy(alpha = 0.2f)).padding(horizontal = 4.dp, vertical = 1.dp)
                    )
                    if (assignment.assignedZone.isNotBlank()) {
                        Text(assignment.assignedZone, fontSize = 10.sp, color = NV.textSecondary)
                    }
                    if (assignment.assignedFloor.isNotBlank()) {
                        Text(assignment.assignedFloor, fontSize = 10.sp, color = NV.textSecondary)
                    }
                }
            }
        }
    }
}
