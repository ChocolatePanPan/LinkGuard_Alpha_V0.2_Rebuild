package com.linkguard.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.linkguard.app.ui.theme.NV
import com.linkguard.app.ui.theme.NVShape

// =====================================================
//  NVCard — 統一卡片元件系統
// =====================================================

/**
 * 標準卡片容器（取代散落各處的 CardContainer）。
 * - 24dp 圓角（NVShape.card）
 * - 漸變背景（card → 深色）
 * - 色彩邊框帶漸變
 * - 6dp 陰影
 */
@Composable
fun NVCard(
    modifier: Modifier = Modifier,
    borderColor: Color = NV.cardBorder,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .shadow(
                6.dp, NVShape.card,
                ambientColor = Color.Black.copy(alpha = 0.5f),
                spotColor = Color.Black.copy(alpha = 0.3f)
            )
            .clip(NVShape.card)
            .background(
                Brush.verticalGradient(
                    colors = listOf(NV.card, Color(0xFF131920))
                )
            )
            .border(
                width = 1.dp,
                brush = Brush.verticalGradient(
                    colors = listOf(
                        borderColor.copy(alpha = 0.6f),
                        borderColor.copy(alpha = 0.2f)
                    )
                ),
                shape = NVShape.card
            )
            .padding(16.dp),
        content = content
    )
}

/**
 * 警示卡片 — 左側色彩條表示嚴重程度。
 */
@Composable
fun NVAlertCard(
    modifier: Modifier = Modifier,
    accentColor: Color = NV.danger,
    accentWidth: Dp = 4.dp,
    content: @Composable RowScope.() -> Unit
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .shadow(
                6.dp, NVShape.card,
                ambientColor = Color.Black.copy(alpha = 0.5f),
                spotColor = Color.Black.copy(alpha = 0.3f)
            )
            .clip(NVShape.card)
            .background(
                Brush.verticalGradient(
                    colors = listOf(NV.card, Color(0xFF131920))
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
    ) {
        // 左側色彩條
        Box(
            modifier = Modifier
                .width(accentWidth)
                .fillMaxHeight()
                .background(accentColor)
        )
        Row(
            modifier = Modifier
                .weight(1f)
                .padding(16.dp),
            content = content
        )
    }
}

/**
 * 統計卡片 — Dashboard 用大數字 + 標籤 + 圖示。
 * 升級版：56dp 最小觸控高度、更大字體。
 */
@Composable
fun NVStatCard(
    label: String,
    value: String,
    color: Color,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    onClick: (() -> Unit)? = null
) {
    Column(
        modifier = modifier
            .defaultMinSize(minHeight = 56.dp)
            .shadow(
                8.dp, NVShape.card,
                ambientColor = color.copy(alpha = 0.15f),
                spotColor = color.copy(alpha = 0.1f)
            )
            .clip(NVShape.card)
            .background(
                Brush.verticalGradient(
                    colors = listOf(NV.card, Color(0xFF131920))
                )
            )
            .drawBehind { drawRect(color = color.copy(alpha = 0.07f)) }
            .border(
                width = 1.dp,
                brush = Brush.verticalGradient(
                    colors = listOf(
                        color.copy(alpha = 0.25f),
                        color.copy(alpha = 0.08f)
                    )
                ),
                shape = NVShape.card
            )
            .then(
                if (onClick != null) Modifier.clickable { onClick() } else Modifier
            )
            .padding(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = label, tint = color.copy(alpha = 0.6f), modifier = Modifier.size(24.dp))
            Spacer(modifier = Modifier.height(6.dp))
        }
        Text(value, color = color, fontSize = 26.sp, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(4.dp))
        Text(label, color = NV.textSecondary, fontSize = 13.sp)
    }
}

/**
 * 空狀態卡片 — 資料為空時顯示的佔位元件。
 */
@Composable
fun NVEmptyState(
    icon: ImageVector,
    title: String,
    subtitle: String = "",
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            icon, contentDescription = null,
            tint = NV.textSecondary.copy(alpha = 0.5f),
            modifier = Modifier.size(64.dp)
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(title, color = NV.textSecondary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        if (subtitle.isNotEmpty()) {
            Spacer(modifier = Modifier.height(4.dp))
            Text(subtitle, color = NV.textSecondary.copy(alpha = 0.7f), fontSize = 13.sp)
        }
        if (actionLabel != null && onAction != null) {
            Spacer(modifier = Modifier.height(16.dp))
            androidx.compose.material3.Button(
                onClick = onAction,
                colors = androidx.compose.material3.ButtonDefaults.buttonColors(containerColor = NV.blue),
                shape = NVShape.pill,
                modifier = Modifier.defaultMinSize(minHeight = 56.dp)
            ) {
                Text(actionLabel, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
