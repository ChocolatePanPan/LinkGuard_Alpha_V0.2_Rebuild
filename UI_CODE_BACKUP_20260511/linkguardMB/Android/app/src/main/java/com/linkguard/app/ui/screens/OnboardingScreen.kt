package com.linkguard.app.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.linkguard.app.ui.theme.NV
import com.linkguard.app.ui.theme.NVShape
import kotlinx.coroutines.launch

// =====================================================
//  首次啟動引導頁面
// =====================================================

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun OnboardingScreen(
    onComplete: (role: String, deptCode: String) -> Unit
) {
    val pagerState = rememberPagerState(pageCount = { 4 })
    val scope = rememberCoroutineScope()
    var selectedRole by remember { mutableStateOf("RESCUE") }
    var deptCode by remember { mutableStateOf("EMT") }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(NV.bg)
    ) {
        HorizontalPager(
            state = pagerState,
            modifier = Modifier.fillMaxSize()
        ) { page ->
            when (page) {
                0 -> WelcomePage()
                1 -> RoleSelectionPage(
                    selectedRole = selectedRole,
                    onRoleSelected = { selectedRole = it },
                    deptCode = deptCode,
                    onDeptCodeChanged = { deptCode = it }
                )
                2 -> FeatureTourPage()
                3 -> ReadyPage()
            }
        }

        // 底部導航
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // 分頁指示點
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                repeat(4) { index ->
                    Box(
                        modifier = Modifier
                            .size(if (pagerState.currentPage == index) 10.dp else 8.dp)
                            .clip(CircleShape)
                            .background(
                                if (pagerState.currentPage == index) NV.green
                                else NV.textSecondary.copy(alpha = 0.4f)
                            )
                    )
                }
            }

            // 按鈕列
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // 跳過按鈕
                if (pagerState.currentPage < 3) {
                    TextButton(
                        onClick = { onComplete(selectedRole, deptCode) },
                        modifier = Modifier.defaultMinSize(minHeight = 56.dp)
                    ) {
                        Text("Skip", color = NV.textSecondary, fontSize = 16.sp)
                    }
                } else {
                    Spacer(modifier = Modifier.width(80.dp))
                }

                // 下一步 / 開始按鈕
                if (pagerState.currentPage < 3) {
                    Button(
                        onClick = {
                            scope.launch {
                                pagerState.animateScrollToPage(pagerState.currentPage + 1)
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = NV.green),
                        shape = NVShape.card,
                        modifier = Modifier.defaultMinSize(minHeight = 56.dp, minWidth = 140.dp)
                    ) {
                        Text("Next", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                        Spacer(modifier = Modifier.width(4.dp))
                        Icon(Icons.Default.ArrowForward, contentDescription = null, modifier = Modifier.size(20.dp))
                    }
                } else {
                    Button(
                        onClick = { onComplete(selectedRole, deptCode) },
                        colors = ButtonDefaults.buttonColors(containerColor = NV.green),
                        shape = NVShape.card,
                        modifier = Modifier.defaultMinSize(minHeight = 56.dp, minWidth = 180.dp)
                    ) {
                        Icon(Icons.Default.RocketLaunch, contentDescription = null, modifier = Modifier.size(20.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Start LinkGuard", fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

// =====================================================
//  Page 1: Welcome
// =====================================================

@Composable
private fun WelcomePage() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text("⛑", fontSize = 80.sp)
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            "LinkGuard",
            color = NV.green,
            fontSize = 36.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "Earthquake Search & Rescue\nCommand System",
            color = NV.textSecondary,
            fontSize = 16.sp,
            textAlign = TextAlign.Center,
            lineHeight = 24.sp
        )
        Spacer(modifier = Modifier.height(40.dp))
        // Feature highlights
        OnboardingFeatureRow(Icons.Default.People, NV.green, "Track trapped persons via BLE mesh")
        Spacer(modifier = Modifier.height(12.dp))
        OnboardingFeatureRow(Icons.Default.Chat, NV.command, "Real-time team communication")
        Spacer(modifier = Modifier.height(12.dp))
        OnboardingFeatureRow(Icons.Default.Warning, NV.danger, "SOS alerts with one tap")
        Spacer(modifier = Modifier.height(12.dp))
        OnboardingFeatureRow(Icons.Default.SettingsRemote, NV.info, "LoRa long-range radio mesh")
    }
}

// =====================================================
//  Page 2: Role Selection
// =====================================================

@Composable
private fun RoleSelectionPage(
    selectedRole: String,
    onRoleSelected: (String) -> Unit,
    deptCode: String,
    onDeptCodeChanged: (String) -> Unit
) {
    val roles = listOf(
        Triple("SEARCH", "Search", Icons.Default.Search),
        Triple("RESCUE", "Rescue", Icons.Default.Shield),
        Triple("MEDICAL", "Medical", Icons.Default.LocalHospital),
        Triple("LOGISTICS", "Logistics", Icons.Default.Inventory),
        Triple("COMMANDER", "Commander", Icons.Default.Gavel)
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            "Select Your Role",
            color = NV.white,
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            "This helps customize your dashboard",
            color = NV.textSecondary,
            fontSize = 14.sp
        )
        Spacer(modifier = Modifier.height(32.dp))

        // Role grid
        roles.forEach { (roleId, roleName, icon) ->
            val isSelected = selectedRole == roleId
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(NVShape.card)
                    .background(if (isSelected) NV.green.copy(alpha = 0.15f) else NV.card)
                    .border(
                        width = if (isSelected) 2.dp else 1.dp,
                        color = if (isSelected) NV.green else NV.cardBorder,
                        shape = NVShape.card
                    )
                    .clickable { onRoleSelected(roleId) }
                    .padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(icon, contentDescription = null, tint = if (isSelected) NV.green else NV.textSecondary, modifier = Modifier.size(28.dp))
                Text(roleName, color = NV.white, fontSize = 16.sp, fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal)
                Spacer(modifier = Modifier.weight(1f))
                if (isSelected) {
                    Icon(Icons.Default.CheckCircle, contentDescription = null, tint = NV.green, modifier = Modifier.size(24.dp))
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Department code
        OutlinedTextField(
            value = deptCode,
            onValueChange = { if (it.length <= 3) onDeptCodeChanged(it.uppercase()) },
            label = { Text("Department Code") },
            placeholder = { Text("EMT / FD / PD") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = NV.white,
                unfocusedTextColor = NV.white,
                focusedBorderColor = NV.green,
                unfocusedBorderColor = NV.cardBorder,
                focusedLabelColor = NV.green,
                unfocusedLabelColor = NV.textSecondary
            )
        )
    }
}

// =====================================================
//  Page 3: Feature Tour
// =====================================================

@Composable
private fun FeatureTourPage() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            "Quick Tour",
            color = NV.white,
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(32.dp))

        FeatureTourCard(
            icon = Icons.Default.Warning,
            color = NV.groupOps,
            title = "Ops",
            description = "Dashboard, SOS alerts, disaster info, and trapped person tracking"
        )
        Spacer(modifier = Modifier.height(12.dp))
        FeatureTourCard(
            icon = Icons.Default.Chat,
            color = NV.groupComms,
            title = "Comms",
            description = "Team chat, radio broadcasts, HQ commands, and notifications"
        )
        Spacer(modifier = Modifier.height(12.dp))
        FeatureTourCard(
            icon = Icons.Default.Groups,
            color = NV.groupSupport,
            title = "Support",
            description = "Team roster, reinforcement requests, patient forms, and decisions"
        )
        Spacer(modifier = Modifier.height(12.dp))
        FeatureTourCard(
            icon = Icons.Default.Build,
            color = NV.groupTools,
            title = "Tools",
            description = "Translator, photo reports, and device connection management"
        )
        Spacer(modifier = Modifier.height(24.dp))

        // SOS FAB explanation
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(NVShape.card)
                .background(NV.danger.copy(alpha = 0.1f))
                .border(1.dp, NV.danger.copy(alpha = 0.3f), NVShape.card)
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(NV.danger),
                contentAlignment = Alignment.Center
            ) {
                Text("SOS", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            }
            Column {
                Text("Emergency SOS", color = NV.danger, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                Text("Always available at bottom-right corner", color = NV.textSecondary, fontSize = 12.sp)
            }
        }
    }
}

// =====================================================
//  Page 4: Ready
// =====================================================

@Composable
private fun ReadyPage() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            Icons.Default.CheckCircle,
            contentDescription = null,
            tint = NV.green,
            modifier = Modifier.size(80.dp)
        )
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            "Ready to Deploy",
            color = NV.green,
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            "Connect to a LoRa device or\njoin a WiFi command network\nto start receiving live data.",
            color = NV.textSecondary,
            fontSize = 16.sp,
            textAlign = TextAlign.Center,
            lineHeight = 24.sp
        )
        Spacer(modifier = Modifier.height(40.dp))

        // Permission reminders
        PermissionReminder(Icons.Default.Bluetooth, "Bluetooth", "Required for BLE mesh")
        Spacer(modifier = Modifier.height(8.dp))
        PermissionReminder(Icons.Default.LocationOn, "Location", "Required for BLE scanning & GPS")
        Spacer(modifier = Modifier.height(8.dp))
        PermissionReminder(Icons.Default.Notifications, "Notifications", "For SOS and command alerts")
        Spacer(modifier = Modifier.height(8.dp))
        PermissionReminder(Icons.Default.PhotoCamera, "Camera", "For photo reports")
    }
}

// =====================================================
//  Helper Composables
// =====================================================

@Composable
private fun OnboardingFeatureRow(icon: ImageVector, color: Color, text: String) {
    Row(
        modifier = Modifier.fillMaxWidth(0.85f),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(24.dp))
        Text(text, color = NV.textPrimary, fontSize = 15.sp)
    }
}

@Composable
private fun FeatureTourCard(
    icon: ImageVector,
    color: Color,
    title: String,
    description: String
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(NVShape.card)
            .background(color.copy(alpha = 0.08f))
            .border(1.dp, color.copy(alpha = 0.2f), NVShape.card)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(32.dp))
        Column {
            Text(title, color = color, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            Text(description, color = NV.textSecondary, fontSize = 13.sp)
        }
    }
}

@Composable
private fun PermissionReminder(icon: ImageVector, name: String, reason: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(NV.card)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(icon, contentDescription = null, tint = NV.textSecondary, modifier = Modifier.size(20.dp))
        Column {
            Text(name, color = NV.white, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            Text(reason, color = NV.textSecondary, fontSize = 12.sp)
        }
    }
}
