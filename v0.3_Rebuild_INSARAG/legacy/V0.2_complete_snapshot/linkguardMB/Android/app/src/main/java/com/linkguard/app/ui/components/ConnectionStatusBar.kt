package com.linkguard.app.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
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
import com.linkguard.app.ui.theme.NV
import com.linkguard.app.viewmodel.LinkGuardViewModel

// =====================================================
//  ConnectionStatusBar — 持續顯示的連線狀態列
// =====================================================

/**
 * 薄型連線狀態列，顯示 BLE / WiFi / GPS 三個狀態指示。
 * 點擊可展開詳細資訊 + 重試按鈕。
 */
@Composable
fun ConnectionStatusBar(
    viewModel: LinkGuardViewModel,
    modifier: Modifier = Modifier
) {
    val bleConnected by viewModel.bluetoothManager.isConnected.collectAsState()
    val wifiConnected by viewModel.commandClient.isConnected.collectAsState()
    val nodeStatus by viewModel.nodeStatus.collectAsState()
    var expanded by remember { mutableStateOf(false) }

    Column(modifier = modifier.fillMaxWidth()) {
        // 薄型狀態列
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(NV.surface)
                .clickable { expanded = !expanded }
                .padding(horizontal = 16.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                StatusDot(
                    label = "BLE",
                    connected = bleConnected,
                    color = if (bleConnected) NV.green else NV.danger
                )
                StatusDot(
                    label = "HQ",
                    connected = wifiConnected,
                    color = if (wifiConnected) NV.green else NV.warning
                )
                StatusDot(
                    label = "GPS",
                    connected = nodeStatus.gpsLat != 0.0,
                    color = if (nodeStatus.gpsLat != 0.0) NV.green else NV.textSecondary
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    nodeStatus.nodeID,
                    color = NV.textSecondary,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Spacer(modifier = Modifier.width(4.dp))
                Icon(
                    if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    contentDescription = null,
                    tint = NV.textSecondary,
                    modifier = Modifier.size(16.dp)
                )
            }
        }

        // 展開詳細
        AnimatedVisibility(
            visible = expanded,
            enter = expandVertically(),
            exit = shrinkVertically()
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(NV.card)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                // BLE 詳細
                ConnectionDetailRow(
                    icon = Icons.Default.Bluetooth,
                    label = "BLE",
                    status = if (bleConnected) "Connected" else "Disconnected",
                    connected = bleConnected,
                    onRetry = if (!bleConnected) {{ viewModel.scanForDevices() }} else null
                )
                // WiFi 詳細
                ConnectionDetailRow(
                    icon = Icons.Default.Wifi,
                    label = "HQ WiFi",
                    status = if (wifiConnected) "Connected" else "Searching...",
                    connected = wifiConnected,
                    onRetry = null
                )
                // GPS 詳細
                val hasGPS = nodeStatus.gpsLat != 0.0
                ConnectionDetailRow(
                    icon = Icons.Default.LocationOn,
                    label = "GPS",
                    status = if (hasGPS) "%.5f, %.5f".format(nodeStatus.gpsLat, nodeStatus.gpsLon) else "No fix",
                    connected = hasGPS,
                    onRetry = null
                )
                // Node info
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text("Dept: ${nodeStatus.deptCode}", color = NV.textSecondary, fontSize = 12.sp)
                    Text("BAT: ${nodeStatus.battery}%", color = NV.textSecondary, fontSize = 12.sp)
                    Text("LoRa: ${nodeStatus.loraProfile.label}", color = NV.textSecondary, fontSize = 12.sp)
                }
            }
        }
    }
}

@Composable
private fun StatusDot(label: String, connected: Boolean, color: Color) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(color)
        )
        Text(
            label,
            color = if (connected) NV.textPrimary else NV.textSecondary,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
private fun ConnectionDetailRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    status: String,
    connected: Boolean,
    onRetry: (() -> Unit)?
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(
                icon, contentDescription = null,
                tint = if (connected) NV.green else NV.textSecondary,
                modifier = Modifier.size(20.dp)
            )
            Column {
                Text(label, color = NV.white, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                Text(status, color = NV.textSecondary, fontSize = 11.sp)
            }
        }
        if (onRetry != null) {
            TextButton(
                onClick = onRetry,
                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)
            ) {
                Text("Retry", color = NV.blue, fontSize = 12.sp)
            }
        } else {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(if (connected) NV.green else NV.textSecondary)
            )
        }
    }
}
