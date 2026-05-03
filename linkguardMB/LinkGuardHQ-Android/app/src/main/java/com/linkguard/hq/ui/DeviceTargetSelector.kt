package com.linkguard.hq.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.res.stringResource
import com.linkguard.hq.R
import com.linkguard.hq.model.ConnectedFieldUnit
import com.linkguard.hq.viewmodel.HQViewModel

/**
 * PADOS 多裝置目標選擇器
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DeviceTargetSelector(
    targetMode: HQViewModel.TargetMode,
    selectedIDs: Set<String>,
    fieldUnits: List<ConnectedFieldUnit>,
    onModeChange: (HQViewModel.TargetMode) -> Unit,
    onToggleDevice: (String) -> Unit,
    onSelectAll: () -> Unit,
    onDeselectAll: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(NVShape.card)
            .background(NV.card)
            .padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        // 模式切換
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            HQViewModel.TargetMode.entries.forEach { mode ->
                val label = if (mode == HQViewModel.TargetMode.BROADCAST) stringResource(R.string.mode_broadcast) else stringResource(R.string.mode_selected)
                FilterChip(
                    selected = targetMode == mode,
                    onClick = { onModeChange(mode) },
                    label = { Text(label, fontSize = 12.sp) },
                    modifier = Modifier.weight(1f)
                )
            }
        }

        if (targetMode == HQViewModel.TargetMode.SELECTED) {
            if (fieldUnits.isEmpty()) {
                Text(
                    stringResource(R.string.no_connected_devices),
                    fontSize = 12.sp,
                    color = NV.textSecondary
                )
            } else {
                // 全選 / 取消
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        stringResource(R.string.selected_count, selectedIDs.size, fieldUnits.size),
                        fontSize = 12.sp,
                        color = NV.textSecondary
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(onClick = onSelectAll) {
                            Text(stringResource(R.string.select_all), fontSize = 12.sp)
                        }
                        TextButton(onClick = onDeselectAll) {
                            Text(stringResource(R.string.deselect_all), fontSize = 12.sp)
                        }
                    }
                }

                LazyColumn(
                    modifier = Modifier.heightIn(max = 160.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    items(fieldUnits, key = { it.id }) { unit ->
                        val isSelected = selectedIDs.contains(unit.deviceID)
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(6.dp))
                                .background(if (isSelected) NV.green.copy(alpha = 0.08f) else NV.bg)
                                .clickable { onToggleDevice(unit.deviceID) }
                                .padding(horizontal = 8.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Checkbox(
                                checked = isSelected,
                                onCheckedChange = { onToggleDevice(unit.deviceID) },
                                modifier = Modifier.size(20.dp)
                            )

                            // 上線指示燈
                            Box(
                                modifier = Modifier
                                    .size(6.dp)
                                    .clip(CircleShape)
                                    .background(if (unit.isOnline) NV.green else NV.textSecondary)
                            )

                            Text(
                                unit.deviceID,
                                fontSize = 13.sp,
                                fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                                color = NV.white
                            )

                            Text(
                                unit.deptCode,
                                fontSize = 11.sp,
                                color = NV.team,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(2.dp))
                                    .background(NV.team.copy(alpha = 0.2f))
                                    .padding(horizontal = 4.dp, vertical = 1.dp)
                            )

                            Spacer(modifier = Modifier.weight(1f))

                            Text(
                                "${unit.battery}%",
                                fontSize = 11.sp,
                                color = if (unit.battery < 20) NV.danger else NV.textSecondary
                            )
                        }
                    }
                }
            }
        }
    }
}
