package com.linkguard.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Brightness6
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.linkguard.app.ui.theme.NV
import com.linkguard.app.ui.theme.NVShape
import com.linkguard.app.ui.theme.ThemeMode
import com.linkguard.app.viewmodel.LinkGuardViewModel

/**
 * 外觀設定 — 三段切換：跟隨系統 / 淺色 / 深色。
 *
 * 設計依 EightShapes《Light & Dark Color Modes in Design Systems》：
 *   - 使用語義 token（NV.card / NV.cardBorder / NV.textPrimary / NV.textSecondary）
 *   - 卡片在淺色 canvas 上以 1dp 邊框分隔層次
 *   - 群組標題放在第一張卡片上方（iOS 風格）
 */
@Composable
fun AppearanceSettingsScreen(viewModel: LinkGuardViewModel) {
    val current by viewModel.themeMode.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(NV.bg)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = "外觀",
            color = NV.textPrimary,
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp, bottom = 8.dp),
        )

        Text(
            text = "選擇要使用的主題模式。「跟隨系統」會依系統設定自動切換淺色與深色。",
            color = NV.textSecondary,
            fontSize = 13.sp,
            modifier = Modifier.padding(bottom = 8.dp)
        )

        // 三選一 group
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(NVShape.card)
                .background(NV.card)
                .border(width = 1.dp, color = NV.cardBorder, shape = NVShape.card)
        ) {
            ThemeOptionRow(
                label   = "跟隨系統",
                desc    = "依裝置外觀自動切換",
                icon    = Icons.Default.PhoneAndroid,
                selected = current == ThemeMode.System,
                showDivider = true,
                onClick = { viewModel.setThemeMode(ThemeMode.System) }
            )
            ThemeOptionRow(
                label   = "淺色",
                desc    = "永遠使用淺色主題",
                icon    = Icons.Default.LightMode,
                selected = current == ThemeMode.Light,
                showDivider = true,
                onClick = { viewModel.setThemeMode(ThemeMode.Light) }
            )
            ThemeOptionRow(
                label   = "深色",
                desc    = "永遠使用深色主題",
                icon    = Icons.Default.DarkMode,
                selected = current == ThemeMode.Dark,
                showDivider = false,
                onClick = { viewModel.setThemeMode(ThemeMode.Dark) }
            )
        }
    }
}

@Composable
private fun ThemeOptionRow(
    label: String,
    desc: String,
    icon: ImageVector,
    selected: Boolean,
    showDivider: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = NV.textSecondary,
            modifier = Modifier.size(24.dp)
        )
        Spacer(Modifier.width(16.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = label,
                color = NV.textPrimary,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = desc,
                color = NV.textSecondary,
                fontSize = 12.sp
            )
        }
        RadioButton(
            selected = selected,
            onClick  = onClick,
            colors = RadioButtonDefaults.colors(
                selectedColor   = NV.green,
                unselectedColor = NV.textSecondary
            )
        )
    }
    if (showDivider) {
        androidx.compose.material3.Divider(
            color = NV.divider,
            thickness = 0.5.dp,
            modifier = Modifier.padding(start = 56.dp)
        )
    }
}
