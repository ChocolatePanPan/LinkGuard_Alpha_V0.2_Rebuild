package com.linkguard.app.ui.screens

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.linkguard.app.model.NfcScanResult
import com.linkguard.app.ui.theme.NV
import com.linkguard.app.ui.theme.NVShape
import com.linkguard.app.viewmodel.LinkGuardViewModel
import java.text.SimpleDateFormat
import java.util.*

// =====================================================
//  NFC 讀取畫面 — 對齊 iOS NFCReaderView
//  讀取 NDEF 文字標籤，解析傷患資訊，可一鍵帶入傷員回報表
// =====================================================

@Composable
fun NFCReaderScreen(
    viewModel: LinkGuardViewModel,
    onFillPatientForm: () -> Unit = {}
) {
    val scanResult by viewModel.nfcScanResult.collectAsState()
    val isNfcAvailable by viewModel.isNfcAvailable.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(NV.bg)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // 標題列
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(bottom = 4.dp)
        ) {
            Icon(
                Icons.Default.Nfc,
                contentDescription = null,
                tint = NV.green,
                modifier = Modifier.size(22.dp)
            )
            Spacer(Modifier.width(8.dp))
            Text(
                "NFC 標籤讀取",
                color = NV.textPrimary,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = FontFamily.Monospace
            )
        }

        if (!isNfcAvailable) {
            NfcUnavailableCard()
        } else {
            NfcScanArea(scanResult = scanResult)
            if (scanResult != null) {
                NfcResultCard(
                    result = scanResult!!,
                    onClear = { viewModel.clearNfcScan() },
                    onFillForm = {
                        viewModel.applyNfcToPatientForm(scanResult!!)
                        onFillPatientForm()
                    }
                )
            }
            NfcInstructionCard()
        }
    }
}

@Composable
private fun NfcUnavailableCard() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(NVShape.card)
            .background(NV.card)
            .border(1.dp, NV.warning.copy(alpha = 0.5f), NVShape.card)
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(Icons.Default.NearbyError, contentDescription = null, tint = NV.warning, modifier = Modifier.size(40.dp))
        Text("此裝置不支援 NFC", color = NV.warning, fontSize = 16.sp, fontWeight = FontWeight.Bold)
        Text("NFC 功能需要具備 NFC 硬體的裝置才能使用。", color = NV.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center)
    }
}

@Composable
private fun NfcScanArea(scanResult: NfcScanResult?) {
    val pulseAnim = rememberInfiniteTransition(label = "nfc_pulse")
    val scale by pulseAnim.animateFloat(
        initialValue = 1f,
        targetValue  = 1.08f,
        animationSpec = infiniteRepeatable(
            animation = tween(900, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "scale"
    )
    val alpha by pulseAnim.animateFloat(
        initialValue = 0.5f,
        targetValue  = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(900, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "alpha"
    )

    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(Modifier.height(8.dp))
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(160.dp)
                .scale(scale)
                .clip(CircleShape)
                .background(
                    if (scanResult != null) NV.green.copy(alpha = 0.15f)
                    else NV.green.copy(alpha = alpha * 0.12f)
                )
                .border(
                    2.dp,
                    if (scanResult != null) NV.green else NV.green.copy(alpha = alpha),
                    CircleShape
                )
        ) {
            Icon(
                Icons.Default.Nfc,
                contentDescription = "NFC",
                tint = if (scanResult != null) NV.green else NV.green.copy(alpha = alpha),
                modifier = Modifier.size(72.dp)
            )
        }
        Spacer(Modifier.height(12.dp))
        Text(
            if (scanResult != null) "標籤讀取成功" else "靠近 NFC 標籤以掃描",
            color = if (scanResult != null) NV.green else NV.textSecondary,
            fontSize = 14.sp,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Medium
        )
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun NfcResultCard(
    result: NfcScanResult,
    onClear: () -> Unit,
    onFillForm: () -> Unit
) {
    val sdf = SimpleDateFormat("HH:mm:ss", Locale.getDefault())

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(NVShape.card)
            .background(NV.card)
            .border(1.dp, NV.green.copy(alpha = 0.4f), NVShape.card)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.CheckCircle, contentDescription = null, tint = NV.green, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text("掃描結果", color = NV.green, fontSize = 13.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
            Spacer(Modifier.weight(1f))
            Text(sdf.format(Date(result.scannedAt)), color = NV.textSecondary, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
        }

        Divider(color = NV.divider, thickness = 0.5.dp)

        // 原始文字
        Text(
            result.rawText,
            color = NV.textPrimary,
            fontSize = 13.sp,
            fontFamily = FontFamily.Monospace
        )

        // 解析欄位
        if (result.fields.isNotEmpty()) {
            Divider(color = NV.divider, thickness = 0.5.dp)
            Text("已解析欄位", color = NV.textSecondary, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
            result.fields.forEach { (k, v) ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(k, color = NV.textSecondary, fontSize = 12.sp)
                    Text(v, color = NV.textPrimary, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                }
            }
        }

        Spacer(Modifier.height(4.dp))

        // 操作按鈕
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedButton(
                onClick = onClear,
                modifier = Modifier.weight(1f),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = NV.textSecondary),
                border = ButtonDefaults.outlinedButtonBorder.copy(
                    brush = androidx.compose.ui.graphics.SolidColor(NV.cardBorder)
                )
            ) {
                Icon(Icons.Default.Clear, contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text("清除", fontSize = 13.sp)
            }
            Button(
                onClick = onFillForm,
                modifier = Modifier.weight(1f),
                colors = ButtonDefaults.buttonColors(containerColor = NV.green)
            ) {
                Icon(Icons.Default.LocalHospital, contentDescription = null, tint = Color.Black, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text("帶入傷員表", fontSize = 13.sp, color = Color.Black, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun NfcInstructionCard() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(NVShape.card)
            .background(NV.surface)
            .border(1.dp, NV.cardBorder, NVShape.card)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text("使用說明", color = NV.textSecondary, fontSize = 12.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
        val steps = listOf(
            "將裝置靠近傷患 NFC 識別標籤（背面）",
            "系統自動讀取 NDEF 文字記錄",
            "讀取成功後點選「帶入傷員表」可自動填寫位置與備註",
            "支援 key:value 格式（如 location:A區3F）"
        )
        steps.forEachIndexed { i, step ->
            Row(verticalAlignment = Alignment.Top) {
                Text(
                    "${i + 1}.",
                    color = NV.green,
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace,
                    modifier = Modifier.width(20.dp)
                )
                Text(step, color = NV.textSecondary, fontSize = 12.sp)
            }
        }
    }
}
