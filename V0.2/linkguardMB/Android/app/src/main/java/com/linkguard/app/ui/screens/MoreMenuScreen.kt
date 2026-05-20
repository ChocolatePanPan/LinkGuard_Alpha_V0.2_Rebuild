package com.linkguard.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.linkguard.app.ui.theme.NV

// =====================================================
//  MoreMenuScreen — 對齊 iOS「More」分頁
//  圖示 + 標題 + 右側 chevron + 細分隔線
// =====================================================

internal data class MoreMenuItem(
    val label: String,
    val icon: ImageVector,
    val color: Color,
    val screenIndex: Int,
    val badge: Int = 0
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MoreMenuScreen(
    items: List<MoreMenuItem>,
    onSelect: (Int) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Transparent)
    ) {
        // 標題列（iOS 風格置中）
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 16.dp, bottom = 8.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                "More",
                color = NV.textPrimary,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold
            )
        }
        Divider(color = NV.divider, thickness = 0.5.dp)

        LazyColumn(
            modifier = Modifier.fillMaxSize()
        ) {
            items(items) { item ->
                MoreMenuRow(item = item, onClick = { onSelect(item.screenIndex) })
                Divider(
                    color = NV.divider,
                    thickness = 0.5.dp,
                    modifier = Modifier.padding(start = 64.dp)
                )
            }
            item { Spacer(Modifier.height(96.dp)) } // 預留底部 nav 空間
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MoreMenuRow(item: MoreMenuItem, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .padding(horizontal = 20.dp, vertical = 14.dp)
            .defaultMinSize(minHeight = 44.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = item.icon,
            contentDescription = item.label,
            tint = item.color,
            modifier = Modifier.size(26.dp)
        )
        Spacer(Modifier.width(18.dp))
        Text(
            text = item.label,
            color = NV.textPrimary,
            fontSize = 16.sp,
            fontWeight = FontWeight.Normal,
            modifier = Modifier.weight(1f)
        )
        if (item.badge > 0) {
            Badge(
                containerColor = NV.danger,
                contentColor = Color.White,
                modifier = Modifier.padding(end = 8.dp)
            ) {
                Text(
                    text = if (item.badge > 99) "99+" else item.badge.toString(),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
        Icon(
            imageVector = Icons.Default.ChevronRight,
            contentDescription = null,
            tint = NV.textSecondary.copy(alpha = 0.6f),
            modifier = Modifier.size(20.dp)
        )
    }
}
