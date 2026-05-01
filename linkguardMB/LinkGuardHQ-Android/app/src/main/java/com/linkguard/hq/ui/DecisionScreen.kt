package com.linkguard.hq.ui

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.ui.res.stringResource
import com.linkguard.hq.R
import com.linkguard.hq.model.HQDecision
import com.linkguard.hq.model.PatientDecisionEntry
import com.linkguard.hq.viewmodel.HQViewModel

// =====================================================
//  指揮決策顯示頁
// =====================================================

@Composable
fun DecisionTab(viewModel: HQViewModel) {
    val decisions by viewModel.decisions.collectAsState()
    val isRequestingAI by viewModel.isRequestingAI.collectAsState()
    val isBackendConnected by viewModel.isBackendConnected.collectAsState()
    val context = LocalContext.current
    var aiContextText by remember { mutableStateOf("") }

    // AI 決策結果自動填入
    val latestAI by viewModel.latestAIDecision.collectAsState()
    LaunchedEffect(latestAI?.receivedAt) {
        latestAI?.let { aiContextText = "" }
    }

    // 偵測新增決策時震動
    val previousCount = remember { mutableIntStateOf(decisions.size) }
    LaunchedEffect(decisions.size) {
        if (decisions.size > previousCount.intValue) {
            vibrateDevice(context)
        }
        previousCount.intValue = decisions.size
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // AI 決策建議區塊
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = NV.card),
                shape = RoundedCornerShape(12.dp)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        stringResource(R.string.ai_decision_suggest),
                        color = NV.command,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold
                    )

                    OutlinedTextField(
                        value = aiContextText,
                        onValueChange = { aiContextText = it },
                        label = { Text(stringResource(R.string.ai_context_hint)) },
                        modifier = Modifier.fillMaxWidth(),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = NV.white,
                            unfocusedTextColor = NV.white,
                            focusedBorderColor = NV.command,
                            unfocusedBorderColor = NV.cardBorder,
                            focusedLabelColor = NV.command,
                            unfocusedLabelColor = NV.textSecondary
                        ),
                        maxLines = 3,
                        enabled = !isRequestingAI
                    )

                    Button(
                        onClick = { viewModel.requestAIDecision(aiContextText) },
                        enabled = isBackendConnected && !isRequestingAI,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = NV.command,
                            disabledContainerColor = NV.cardBorder
                        ),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        if (isRequestingAI) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                color = NV.white,
                                strokeWidth = 2.dp
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(stringResource(R.string.ai_analyzing), color = NV.white)
                        } else {
                            Icon(Icons.Default.AutoAwesome, null, tint = NV.white)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                if (isBackendConnected) stringResource(R.string.request_ai_decision) else stringResource(R.string.backend_not_connected_plain),
                                color = NV.white
                            )
                        }
                    }
                }
            }
        }

        // 標題
        item {
            Text(
                stringResource(R.string.command_decision),
                color = NV.command,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                if (decisions.isEmpty()) stringResource(R.string.no_decisions)
                else stringResource(R.string.decision_count, decisions.size),
                color = NV.textSecondary,
                fontSize = 12.sp
            )
        }

        if (decisions.isEmpty()) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 48.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(stringResource(R.string.waiting_decisions),
                        color = NV.textSecondary, fontSize = 14.sp)
                }
            }
        }

        items(decisions) { decision ->
            DecisionCard(decision)
        }
    }
}

@Composable
private fun DecisionCard(decision: HQDecision) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = NV.card),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // 標頭：觸發來源 + 時間戳
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        stringResource(R.string.label_decision),
                        color = NV.command,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    val triggerLabel = when (decision.trigger) {
                        "patient" -> stringResource(R.string.trigger_patient)
                        "voice" -> stringResource(R.string.trigger_voice)
                        "manual" -> stringResource(R.string.trigger_manual)
                        "hq_request" -> stringResource(R.string.trigger_hq_request)
                        "llm", "ai" -> stringResource(R.string.trigger_ai)
                        else -> if (decision.trigger.isNotEmpty()) stringResource(R.string.trigger_prefix, decision.trigger) else ""
                    }
                    if (triggerLabel.isNotEmpty()) {
                        Text(
                            triggerLabel,
                            fontSize = 10.sp,
                            color = NV.info,
                            modifier = Modifier
                                .background(NV.info.copy(alpha = 0.15f), RoundedCornerShape(8.dp))
                                .padding(horizontal = 6.dp, vertical = 1.dp)
                        )
                    }
                    if (decision.model.isNotEmpty()) {
                        Text(
                            decision.model,
                            fontSize = 10.sp,
                            color = if (decision.escalated) NV.warning else NV.green,
                            modifier = Modifier
                                .background(
                                    (if (decision.escalated) NV.warning else NV.green).copy(alpha = 0.15f),
                                    RoundedCornerShape(8.dp)
                                )
                                .padding(horizontal = 6.dp, vertical = 1.dp)
                        )
                    }
                    if (decision.escalated) {
                        Text(
                            "⬆ 升級",
                            fontSize = 10.sp,
                            color = NV.warning,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier
                                .background(NV.warning.copy(alpha = 0.15f), RoundedCornerShape(8.dp))
                                .padding(horizontal = 6.dp, vertical = 1.dp)
                        )
                    }
                }
                Text(
                    decision.timestamp,
                    color = NV.textSecondary,
                    fontSize = 11.sp
                )
            }

            // 決策文字（大字體）
            Text(
                decision.decision,
                color = NV.white,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                lineHeight = 26.sp
            )

            // 傷員列表
            if (decision.patients.isNotEmpty()) {
                @Suppress("DEPRECATION")
                Divider(color = NV.cardBorder, thickness = 1.dp)
                Text(
                    stringResource(R.string.patient_list, decision.patients.size),
                    color = NV.textSecondary,
                    fontSize = 12.sp
                )
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    decision.patients.forEach { patient ->
                        PatientEntryCard(patient)
                    }
                }
            }
        }
    }
}

@Composable
private fun PatientEntryCard(patient: PatientDecisionEntry) {
    val priorityColor = when (patient.priority.lowercase()) {
        "red"    -> Color.Red
        "black"  -> Color(0xFF222222)
        "green"  -> Color.Green
        "yellow" -> Color.Yellow
        else     -> NV.textSecondary
    }
    val priorityLabel = when (patient.priority.lowercase()) {
        "red"    -> stringResource(R.string.priority_red)
        "black"  -> stringResource(R.string.priority_black)
        "green"  -> stringResource(R.string.priority_green)
        "yellow" -> stringResource(R.string.priority_yellow)
        else     -> stringResource(R.string.priority_unclassified)
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = priorityColor.copy(alpha = 0.15f)),
        shape = RoundedCornerShape(8.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // 優先級色塊
            Box(
                modifier = Modifier
                    .size(width = 4.dp, height = 36.dp)
                    .background(priorityColor, RoundedCornerShape(2.dp))
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    "ID: ${patient.id}",
                    color = NV.white,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium
                )
                if (patient.location.isNotBlank()) {
                    Text(
                        patient.location,
                        color = NV.textSecondary,
                        fontSize = 12.sp
                    )
                }
            }
            // 優先級標籤
            Text(
                priorityLabel,
                color = priorityColor,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold
            )
        }
    }
}

// =====================================================
//  震動輔助函式
// =====================================================

private fun vibrateDevice(context: Context) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
        vibratorManager?.defaultVibrator?.vibrate(
            VibrationEffect.createOneShot(400, VibrationEffect.DEFAULT_AMPLITUDE)
        )
    } else {
        @Suppress("DEPRECATION")
        val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createOneShot(400, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(400)
        }
    }
}
