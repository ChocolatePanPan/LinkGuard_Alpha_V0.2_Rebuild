package com.linkguard.hq.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalContext
import com.linkguard.hq.R
import com.linkguard.hq.model.PatientReport
import com.linkguard.hq.viewmodel.HQViewModel

// =====================================================
//  傷員回報表單
// =====================================================

@Composable
fun PatientFormTab(viewModel: HQViewModel) {
    var location by remember { mutableStateOf("") }
    var breathingRateText by remember { mutableStateOf("") }
    var capillaryRefillText by remember { mutableStateOf("") }
    var canFollowCommands by remember { mutableStateOf(false) }
    var showSnackbar by remember { mutableStateOf(false) }
    var snackbarMessage by remember { mutableStateOf("") }

    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(showSnackbar) {
        if (showSnackbar) {
            snackbarHostState.showSnackbar(snackbarMessage)
            showSnackbar = false
        }
    }

    Scaffold(
        containerColor = NV.bg,
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                stringResource(R.string.patient_report),
                color = NV.danger,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold
            )

            Text(
                stringResource(R.string.patient_id_auto),
                color = NV.textSecondary,
                fontSize = 12.sp
            )

            // 位置
            OutlinedTextField(
                value = location,
                onValueChange = { location = it },
                label = { Text(stringResource(R.string.label_location)) },
                placeholder = { Text(stringResource(R.string.location_hint), color = NV.textSecondary) },
                modifier = Modifier.fillMaxWidth(),
                colors = hqTextFieldColors()
            )

            // 呼吸頻率
            OutlinedTextField(
                value = breathingRateText,
                onValueChange = { breathingRateText = it.filter { c -> c.isDigit() || c == '-' } },
                label = { Text(stringResource(R.string.label_breathing_rate)) },
                placeholder = { Text(stringResource(R.string.breathing_rate_hint), color = NV.textSecondary) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth(),
                colors = hqTextFieldColors()
            )

            // 微血管回充時間
            OutlinedTextField(
                value = capillaryRefillText,
                onValueChange = { capillaryRefillText = it.filter { c -> c.isDigit() || c == '.' || c == '-' } },
                label = { Text(stringResource(R.string.label_capillary_refill)) },
                placeholder = { Text(stringResource(R.string.capillary_refill_hint), color = NV.textSecondary) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                modifier = Modifier.fillMaxWidth(),
                colors = hqTextFieldColors()
            )

            // 能否遵從指令
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Column {
                    Text(stringResource(R.string.can_follow_commands), color = NV.white, fontSize = 14.sp)
                    Text(
                        if (canFollowCommands) stringResource(R.string.yes_text) else stringResource(R.string.no_text),
                        color = if (canFollowCommands) NV.green else NV.danger,
                        fontSize = 12.sp
                    )
                }
                Switch(
                    checked = canFollowCommands,
                    onCheckedChange = { canFollowCommands = it },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = NV.green,
                        checkedTrackColor = NV.green.copy(alpha = 0.4f),
                        uncheckedThumbColor = NV.danger,
                        uncheckedTrackColor = NV.danger.copy(alpha = 0.3f)
                    )
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            // 送出按鈕
            Button(
                onClick = {
                    val breathingRate = breathingRateText.toIntOrNull() ?: -1
                    val capillaryRefill = capillaryRefillText.toDoubleOrNull() ?: -1.0
                    if (location.isBlank()) {
                        snackbarMessage = context.getString(R.string.fill_location_error)
                        showSnackbar = true
                        return@Button
                    }
                    val report = PatientReport(
                        location = location.trim(),
                        breathing_rate = breathingRate,
                        capillary_refill = capillaryRefill,
                        can_follow_commands = canFollowCommands
                    )
                    viewModel.sendPatientReport(report)
                    snackbarMessage = context.getString(R.string.patient_submitted, report.patient_id.take(14))
                    showSnackbar = true
                    // 清除表單
                    location = ""
                    breathingRateText = ""
                    capillaryRefillText = ""
                    canFollowCommands = false
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                colors = ButtonDefaults.buttonColors(containerColor = NV.danger)
            ) {
                Text(stringResource(R.string.submit_patient), fontWeight = FontWeight.Bold, fontSize = 16.sp)
            }
        }
    }
}
