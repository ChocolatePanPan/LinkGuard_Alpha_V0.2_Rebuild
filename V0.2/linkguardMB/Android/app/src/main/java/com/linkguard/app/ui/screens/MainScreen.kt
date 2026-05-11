package com.linkguard.app.ui.screens

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material3.windowsizeclass.WindowSizeClass
import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import com.linkguard.app.model.*
import com.linkguard.app.ui.components.ConnectionStatusBar
import com.linkguard.app.ui.components.TacticalBackdrop
import com.linkguard.app.ui.theme.NV
import com.linkguard.app.ui.theme.NVShape
import com.linkguard.app.viewmodel.LinkGuardViewModel

// =====================================================
//  導航定義 — 對齊 iOS TabView 結構（5 個底部分頁）
//  順序：總覽 / 電台 / 通訊 / 指揮命令 / More
// =====================================================

private data class NavGroup(
    val label: String,
    val icon: ImageVector,
    val color: Color,
    val screenIndex: Int   // 主分頁直接對應的 screenIndex；More=-1 (顯示 MoreMenuScreen)
)

private const val SCREEN_MORE_MENU = -1

private val navGroups = listOf(
    NavGroup("總覽",     Icons.Default.Dashboard,      NV.green,       0),
    NavGroup("電台",     Icons.Default.SettingsRemote, NV.groupComms,  9),
    NavGroup("通訊",     Icons.Default.Chat,           NV.groupComms,  4),
    NavGroup("指揮命令", Icons.Default.Campaign,       NV.command,     7),
    NavGroup("More",     Icons.Default.MoreHoriz,      NV.info,        SCREEN_MORE_MENU)
)

private const val MORE_GROUP_INDEX = 4

// More 列表項目（對齊 iOS More 分頁，僅包含 Android 已實作畫面）
@Composable
private fun buildMoreItems(
    pendingRF: Int,
    unreadNotifications: Int,
    unacknowledgedSOS: Int
): List<MoreMenuItem> = listOf(
    MoreMenuItem("災情",       Icons.Default.Domain,        NV.warning,    3),
    MoreMenuItem("SOS",        Icons.Default.Warning,       NV.danger,     2, badge = unacknowledgedSOS),
    MoreMenuItem("受困者",     Icons.Default.People,        NV.green,      1),
    MoreMenuItem("增援",       Icons.Default.Shield,        NV.reinforce,  5, badge = pendingRF),
    MoreMenuItem("團隊",       Icons.Default.Groups,        NV.team,       6),
    MoreMenuItem("AI 決策",    Icons.Default.Psychology,    NV.simulation, 11),
    MoreMenuItem("通知",       Icons.Default.Notifications, NV.command,    8, badge = unreadNotifications),
    MoreMenuItem("傷員回報",   Icons.Default.LocalHospital, NV.heartRate,  10),
    MoreMenuItem("翻譯",       Icons.Default.Translate,     NV.info,       12),
    MoreMenuItem("照片",       Icons.Default.PhotoCamera,   NV.green,      13),
    MoreMenuItem("連線",       Icons.Default.Bluetooth,     NV.blue,       14),
    MoreMenuItem("外觀",       Icons.Default.Palette,       NV.info,       15)
)

// =====================================================
//  主畫面 — 群組式底部導航
// =====================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(viewModel: LinkGuardViewModel, windowSizeClass: WindowSizeClass? = null) {
    val useRail = windowSizeClass?.widthSizeClass != WindowWidthSizeClass.Compact
    var selectedGroup by remember { mutableIntStateOf(0) }
    // More 子畫面選擇：null 表顯示 More 列表；非 null 表進入子畫面（顯示返回列）
    var moreSelection by remember { mutableStateOf<Int?>(null) }
    var cameFromDashboard by remember { mutableStateOf(false) }

    val sosVictim by viewModel.latestSOSVictim.collectAsState()
    val criticalCommand by viewModel.latestCriticalCommand.collectAsState()
    val reinforcementReq by viewModel.latestReinforcementRequest.collectAsState()
    val incomingTCPSOS by viewModel.incomingTCPSOS.collectAsState()
    val tcpSOSActive by viewModel.tcpSOSActive.collectAsState()
    val isConnected by viewModel.commandClient.isConnected.collectAsState()
    val urgentBroadcast by viewModel.urgentBroadcast.collectAsState()
    val activePatientWarning by viewModel.activePatientWarning.collectAsState()
    val unacknowledgedSOS = viewModel.unacknowledgedSOSCount
    val unreadCommands = viewModel.unreadCommandCount
    val pendingRF = viewModel.pendingReinforcementCount
    val unreadNotifications by viewModel.unreadNotificationCount.collectAsState()

    val moreItems = buildMoreItems(
        pendingRF = pendingRF,
        unreadNotifications = unreadNotifications,
        unacknowledgedSOS = unacknowledgedSOS
    )
    val moreBadgeTotal = moreItems.sumOf { it.badge }

    // 計算當前螢幕索引
    val currentScreenIndex: Int = when {
        selectedGroup != MORE_GROUP_INDEX -> navGroups[selectedGroup].screenIndex
        moreSelection != null -> moreSelection!!
        else -> SCREEN_MORE_MENU
    }

    // 底部分頁徽章計算（對齊 iOS badge）
    fun groupBadge(groupIndex: Int): Int = when (navGroups[groupIndex].screenIndex) {
        4 -> viewModel.unreadChatMessageCount  // 通訊
        7 -> unreadCommands                     // 指揮命令
        SCREEN_MORE_MENU -> moreBadgeTotal      // More
        else -> 0
    }

    // 導航到指定螢幕索引（供 Dashboard 點擊使用）
    fun navigateToScreen(screenIndex: Int) {
        val mainIdx = navGroups.indexOfFirst { it.screenIndex == screenIndex }
        if (mainIdx >= 0) {
            selectedGroup = mainIdx
            moreSelection = null
            cameFromDashboard = mainIdx != 0
            return
        }
        // 落在 More 列表中
        if (moreItems.any { it.screenIndex == screenIndex }) {
            selectedGroup = MORE_GROUP_INDEX
            moreSelection = screenIndex
            cameFromDashboard = true
        }
    }

    // 共用的 content 區
    @Composable
    fun ScreenContent(modifier: Modifier = Modifier) {
        Box(modifier = modifier) {
            when (currentScreenIndex) {
                SCREEN_MORE_MENU -> MoreMenuScreen(items = moreItems) { idx ->
                    moreSelection = idx
                }
                0 -> DashboardScreen(viewModel) { index -> navigateToScreen(index) }
                1 -> VictimListScreen(viewModel)
                2 -> SOSRecordScreen(viewModel)
                3 -> FieldDisasterScreen(viewModel)
                4 -> FieldChatScreen(viewModel)
                5 -> ReinforcementScreen(viewModel)
                6 -> TeamScreen(viewModel)
                7 -> CommandListScreen(viewModel)
                8 -> FieldNotificationScreen(viewModel)
                9 -> RadioScreen(viewModel)
                10 -> PatientFormScreen(viewModel)
                11 -> DecisionScreen(viewModel)
                12 -> TranslatorScreen(viewModel)
                13 -> PhotoReportScreen(viewModel)
                14 -> ConnectionScreen(viewModel)
                15 -> AppearanceSettingsScreen(viewModel)
            }
        }
    }

    Box(modifier = Modifier.fillMaxSize().background(NV.bg)) {
        TacticalBackdrop()
        if (useRail) {
            // === 平板佈局: NavigationRail (5 主分頁) + Content ===
            Row(modifier = Modifier.fillMaxSize()) {
                Surface(
                    color = NV.surface,
                    shadowElevation = 6.dp,
                    tonalElevation = 2.dp
                ) {
                    NavigationRail(
                        containerColor = Color.Transparent,
                        contentColor = NV.blue,
                        modifier = Modifier.fillMaxHeight()
                    ) {
                        navGroups.forEachIndexed { gi, group ->
                            val badge = groupBadge(gi)
                            NavigationRailItem(
                                selected = selectedGroup == gi,
                                onClick = {
                                    selectedGroup = gi
                                    moreSelection = null
                                    if (gi == 0) cameFromDashboard = false
                                },
                                icon = {
                                    if (badge > 0) {
                                        BadgedBox(badge = { Badge { Text("$badge") } }) {
                                            Icon(group.icon, contentDescription = group.label, modifier = Modifier.size(24.dp))
                                        }
                                    } else {
                                        Icon(group.icon, contentDescription = group.label, modifier = Modifier.size(24.dp))
                                    }
                                },
                                label = { Text(group.label, fontSize = 11.sp, maxLines = 1, fontWeight = FontWeight.SemiBold) },
                                alwaysShowLabel = true,
                                colors = NavigationRailItemDefaults.colors(
                                    selectedIconColor = group.color,
                                    selectedTextColor = group.color,
                                    unselectedIconColor = NV.textSecondary,
                                    unselectedTextColor = NV.textSecondary,
                                    indicatorColor = group.color.copy(alpha = 0.15f)
                                )
                            )
                        }
                    }
                }
                Column(modifier = Modifier.weight(1f).fillMaxHeight()) {
                    ScreenContent(modifier = Modifier.weight(1f))
                }
            }
        } else {
            // === 手機佈局: 底部 5 主分頁（單層，無頂部子分頁） ===
            Scaffold(
                containerColor = Color.Transparent,
                bottomBar = {
                    Surface(
                        color = NV.surface,
                        shadowElevation = 12.dp,
                        tonalElevation = 2.dp
                    ) {
                        NavigationBar(
                            containerColor = Color.Transparent,
                            tonalElevation = 0.dp
                        ) {
                            navGroups.forEachIndexed { gi, group ->
                                val badge = groupBadge(gi)
                                NavigationBarItem(
                                    selected = selectedGroup == gi,
                                    onClick = {
                                        selectedGroup = gi
                                        moreSelection = null
                                        if (gi == 0) cameFromDashboard = false
                                    },
                                    icon = {
                                        if (badge > 0) {
                                            BadgedBox(badge = { Badge { Text("$badge") } }) {
                                                Icon(group.icon, contentDescription = group.label, modifier = Modifier.size(22.dp))
                                            }
                                        } else {
                                            Icon(group.icon, contentDescription = group.label, modifier = Modifier.size(22.dp))
                                        }
                                    },
                                    label = { Text(group.label, fontSize = 11.sp, fontWeight = FontWeight.SemiBold) },
                                    colors = NavigationBarItemDefaults.colors(
                                        selectedIconColor = group.color,
                                        selectedTextColor = group.color,
                                        unselectedIconColor = NV.textSecondary,
                                        unselectedTextColor = NV.textSecondary,
                                        indicatorColor = Color.Transparent
                                    )
                                )
                            }
                        }
                    }
                }
            ) { padding ->
                Column(modifier = Modifier.padding(padding)) {
                    // 螢幕內容（帶交叉淡入動畫）
                    AnimatedContent(
                        targetState = currentScreenIndex,
                        transitionSpec = {
                            fadeIn(animationSpec = tween(300)) togetherWith
                                fadeOut(animationSpec = tween(200))
                        },
                        label = "screen_transition",
                        modifier = Modifier.weight(1f)
                    ) { screenIdx ->
                        Box(modifier = Modifier.fillMaxSize()) {
                            when (screenIdx) {
                                SCREEN_MORE_MENU -> MoreMenuScreen(items = moreItems) { idx ->
                                    moreSelection = idx
                                }
                                0 -> DashboardScreen(viewModel) { index -> navigateToScreen(index) }
                                1 -> VictimListScreen(viewModel)
                                2 -> SOSRecordScreen(viewModel)
                                3 -> FieldDisasterScreen(viewModel)
                                4 -> FieldChatScreen(viewModel)
                                5 -> ReinforcementScreen(viewModel)
                                6 -> TeamScreen(viewModel)
                                7 -> CommandListScreen(viewModel)
                                8 -> FieldNotificationScreen(viewModel)
                                9 -> RadioScreen(viewModel)
                                10 -> PatientFormScreen(viewModel)
                                11 -> DecisionScreen(viewModel)
                                12 -> TranslatorScreen(viewModel)
                                13 -> PhotoReportScreen(viewModel)
                                14 -> ConnectionScreen(viewModel)
                                15 -> AppearanceSettingsScreen(viewModel)
                            }
                        }
                    }
                }
            }
        }

        // 返回列：More 子畫面 → 顯示「← More」；其他從 Dashboard 進入 → 「← Dashboard」
        val showMoreBack = selectedGroup == MORE_GROUP_INDEX && moreSelection != null
        val showDashboardBack = currentScreenIndex != 0 && cameFromDashboard && !showMoreBack
        if (showMoreBack || showDashboardBack) {
            val (label, color, onBack) = if (showMoreBack) {
                Triple("More", NV.info) {
                    moreSelection = null
                    cameFromDashboard = false
                }
            } else {
                Triple("Dashboard", NV.green) {
                    selectedGroup = 0
                    moreSelection = null
                    cameFromDashboard = false
                }
            }
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(top = 8.dp, start = 16.dp),
                contentAlignment = Alignment.TopStart
            ) {
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(color.copy(alpha = 0.2f))
                        .border(1.dp, color.copy(alpha = 0.4f), RoundedCornerShape(50))
                        .clickable { onBack() }
                        .padding(horizontal = 14.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(Icons.Default.KeyboardArrowLeft, contentDescription = "Back", tint = color, modifier = Modifier.size(20.dp))
                    Text(label, color = color, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                }
            }
        }

        // 全螢幕指揮命令覆蓋層
        criticalCommand?.let { command ->
            CommandAlertOverlay(command = command, onDismiss = { viewModel.dismissCommandAlert() })
        }

        // SOS 全螢幕警報覆蓋層
        sosVictim?.let { victim ->
            SOSAlertOverlay(victim = victim, onDismiss = { viewModel.dismissSOSAlert() })
        }

        // 增援請求全螢幕覆蓋層
        reinforcementReq?.let { req ->
            if (!req.isFromSelf) {
                ReinforcementAlertOverlay(
                    request = req,
                    onAccept = { viewModel.acceptReinforcement(req); viewModel.dismissReinforcementAlert() },
                    onDecline = { viewModel.declineReinforcement(req); viewModel.dismissReinforcementAlert() }
                )
            }
        }

        // TCP SOS 收到別人求救
        incomingTCPSOS?.let { sos ->
            IncomingSOSOverlay(alert = sos, onDismiss = { viewModel.dismissIncomingTCPSOS() })
        }

        // 緊急文字廣播覆蓋層
        urgentBroadcast?.let { broadcast ->
            UrgentBroadcastOverlay(broadcast = broadcast, onDismiss = { viewModel.dismissUrgentBroadcast() })
        }

        // 傷患惡化預警覆蓋層
        activePatientWarning?.let { warning ->
            PatientWarningOverlay(warning = warning, onDismiss = { viewModel.dismissPatientWarning() })
        }

        // SOS 浮動按鈕（右下角，更大觸控目標 72dp）
        var showSOSConfirm by remember { mutableStateOf(false) }
        var sosFailedMsg by remember { mutableStateOf<String?>(null) }
        Box(
            modifier = Modifier.fillMaxSize().padding(end = 20.dp, bottom = 150.dp),
            contentAlignment = Alignment.BottomEnd
        ) {
            val pulseAnim = rememberInfiniteTransition(label = "sos_pulse")
            val scale by pulseAnim.animateFloat(
                initialValue = 1f, targetValue = if (tcpSOSActive) 1.15f else 1f,
                animationSpec = infiniteRepeatable(tween(600), RepeatMode.Reverse), label = "sos_scale"
            )
            FloatingActionButton(
                onClick = {
                    if (tcpSOSActive) viewModel.cancelTCPSOS()
                    else showSOSConfirm = true
                },
                containerColor = if (tcpSOSActive) NV.danger else NV.danger.copy(alpha = 0.9f),
                modifier = Modifier.size(72.dp).graphicsLayer(scaleX = scale, scaleY = scale)
            ) {
                if (tcpSOSActive) {
                    Icon(Icons.Default.Close, contentDescription = "Cancel SOS", tint = Color.White, modifier = Modifier.size(28.dp))
                } else {
                    Text("SOS", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 18.sp)
                }
            }
        }
        if (showSOSConfirm) {
            AlertDialog(
                onDismissRequest = { showSOSConfirm = false },
                title = { Text("發送 SOS 緊急呼叫？") },
                text = { Text("將向所有連線裝置與指揮中心發送緊急求救訊號。") },
                confirmButton = {
                    TextButton(
                        onClick = {
                            val sent = viewModel.sendTCPSOS()
                            showSOSConfirm = false
                            if (!sent) {
                                sosFailedMsg = "SOS 發送失敗：未連線到指揮中心"
                            }
                        },
                        modifier = Modifier.defaultMinSize(minHeight = 56.dp)
                    ) { Text("發送 SOS", color = NV.danger, fontSize = 16.sp, fontWeight = FontWeight.Bold) }
                },
                dismissButton = {
                    TextButton(
                        onClick = { showSOSConfirm = false },
                        modifier = Modifier.defaultMinSize(minHeight = 56.dp)
                    ) { Text("取消", fontSize = 16.sp) }
                }
            )
        }
        // SOS 發送失敗提示
        sosFailedMsg?.let { msg ->
            AlertDialog(
                onDismissRequest = { sosFailedMsg = null },
                title = { Text("⚠️ SOS 發送失敗", color = NV.danger) },
                text = { Text(msg, color = NV.white) },
                confirmButton = {
                    TextButton(onClick = { sosFailedMsg = null }) {
                        Text("確定", color = NV.danger)
                    }
                },
                containerColor = NV.bg
            )
        }
    }
}

// =====================================================
//  總覽（Dashboard）
// =====================================================

@Composable
fun DashboardScreen(viewModel: LinkGuardViewModel, onNavigate: (Int) -> Unit) {
    val victims by viewModel.victims.collectAsState()
    val nodeStatus by viewModel.nodeStatus.collectAsState()
    val uptime by viewModel.uptimeSeconds.collectAsState()
    val isSimulating by viewModel.isSimulating.collectAsState()
    val countdownTimers by viewModel.countdownTimers.collectAsState()
    val tasks by viewModel.tasks.collectAsState()
    val hazardReports by viewModel.hazardReports.collectAsState()
    var showHandoverSummary by remember { mutableStateOf(false) }

    val onlineCount = victims.count { it.isOnline }
    val sosCount = victims.count { it.isSOS && it.isOnline }
    val (statusText, statusColor) = viewModel.systemStatus()

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .drawBehind {
                // 頂部微光暈 — 增加深度感
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            Color(0xFF4B8BEC).copy(alpha = 0.06f),
                            Color.Transparent
                        ),
                        center = Offset(size.width * 0.5f, 0f),
                        radius = size.width * 0.9f
                    ),
                    radius = size.width * 0.9f,
                    center = Offset(size.width * 0.5f, 0f)
                )
            }
            .padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // ... (保持原本的系統狀態和節點狀態列)
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text("LinkGuard", color = NV.blue, fontSize = 28.sp, fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.height(2.dp))
                    Text("地震救援指揮系統", color = NV.textSecondary, fontSize = 14.sp)
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(modifier = Modifier.size(10.dp).clip(CircleShape).background(statusColor))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(statusText, color = statusColor, fontSize = 12.sp)
                }
            }
        }

        // 連線狀態列（BLE / HQ / GPS）— 對齊 iOS 節點狀態列
        item {
            val bleConnected by viewModel.bluetoothManager.isConnected.collectAsState()
            val wifiConnected by viewModel.commandClient.isConnected.collectAsState()
            val hasGPS = nodeStatus.gpsLat != 0.0

            CardContainer {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // BLE
                    Icon(
                        Icons.Default.Bluetooth,
                        contentDescription = null,
                        tint = if (bleConnected) NV.green else NV.textSecondary,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            if (bleConnected) "已連接：${nodeStatus.nodeID}" else "藍牙未連接",
                            color = NV.white, fontSize = 12.sp
                        )
                        Text("LoRa ${nodeStatus.loraProfile.label}", color = NV.textSecondary, fontSize = 11.sp)
                    }
                    // HQ WiFi dot
                    Spacer(modifier = Modifier.width(8.dp))
                    Box(modifier = Modifier.size(8.dp).clip(CircleShape)
                        .background(if (wifiConnected) NV.green else NV.textSecondary))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("HQ", color = if (wifiConnected) NV.white else NV.textSecondary, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                    // GPS dot
                    Spacer(modifier = Modifier.width(10.dp))
                    Icon(
                        Icons.Default.LocationOn,
                        contentDescription = null,
                        tint = if (hasGPS) NV.green else NV.textSecondary,
                        modifier = Modifier.size(14.dp)
                    )
                    Spacer(modifier = Modifier.width(2.dp))
                    Text(
                        if (hasGPS) "GPS" else "No GPS",
                        color = if (hasGPS) NV.white else NV.textSecondary,
                        fontSize = 11.sp, fontWeight = FontWeight.SemiBold
                    )
                }
                // Simulation badge
                if (isSimulating) {
                    Spacer(modifier = Modifier.height(6.dp))
                    Text("模擬模式", color = NV.simulation, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .background(NV.simulation.copy(alpha = 0.15f), RoundedCornerShape(4.dp))
                            .padding(horizontal = 6.dp, vertical = 2.dp)
                    )
                }
            }
        }

        // 統計卡片 (兩列三欄 1:1 模仿 iOS)
        item {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatCard("受困者", "$onlineCount/${victims.size}", NV.green, Modifier.weight(1f), Icons.Default.People) { onNavigate(1) }
                    StatCard("SOS", "$sosCount", if (sosCount > 0) NV.danger else NV.textSecondary, Modifier.weight(1f), Icons.Default.Warning) { onNavigate(2) }
                    StatCard("團隊", "${viewModel.onlineTeamCount}/${viewModel.teamMembers.value.size}", NV.team, Modifier.weight(1f), Icons.Default.Groups) { onNavigate(6) }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatCard("增援", "${viewModel.pendingReinforcementCount}", NV.reinforce, Modifier.weight(1f), Icons.Default.SupportAgent) { onNavigate(5) }
                    StatCard("訊息", "${viewModel.chatMessages.value.size}", if (viewModel.chatMessages.value.isNotEmpty()) NV.green else NV.textSecondary, Modifier.weight(1f), Icons.Default.Chat) { onNavigate(4) }
                    StatCard("命令", "${viewModel.unreadCommandCount}", NV.command, Modifier.weight(1f), Icons.Default.Campaign) { onNavigate(7) }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    StatCard("任務", "${viewModel.activeTaskCount}", NV.warning, Modifier.weight(1f), Icons.Default.Checklist) {}
                    Spacer(modifier = Modifier.weight(2f))
                }
            }
        }

        // 快速狀態回報
        item {
            SectionHeader("快速狀態回報", NV.green)
        }
        item {
            val wifiConnected by viewModel.commandClient.isConnected.collectAsState()
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    QuickStatusType.entries.take(2).forEach { type ->
                        Button(
                            onClick = { viewModel.sendQuickStatus(type) },
                            enabled = wifiConnected,
                            colors = ButtonDefaults.buttonColors(containerColor = type.color),
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(8.dp)
                        ) {
                            Text("${type.icon} ${type.label}", fontSize = 13.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    QuickStatusType.entries.drop(2).forEach { type ->
                        Button(
                            onClick = { viewModel.sendQuickStatus(type) },
                            enabled = wifiConnected,
                            colors = ButtonDefaults.buttonColors(containerColor = type.color),
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(8.dp)
                        ) {
                            Text("${type.icon} ${type.label}", fontSize = 13.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }

        // 倒數計時器
        if (countdownTimers.isNotEmpty()) {
            item {
                SectionHeader("倒數計時器", NV.warning)
            }
            items(countdownTimers, key = { it.id }) { timer ->
                CardContainer(borderColor = if (timer.remainingSeconds < 60) NV.danger else NV.warning) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.Timer, contentDescription = null,
                            tint = if (timer.remainingSeconds < 60) NV.danger else NV.warning,
                            modifier = Modifier.size(20.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(timer.title, color = NV.white, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                            Text(
                                if (timer.isExpired) "已到期" else "剩餘 ${timer.remainingText}",
                                color = if (timer.isExpired) NV.danger else NV.textSecondary, fontSize = 12.sp
                            )
                        }
                        Text(timer.remainingText, color = if (timer.remainingSeconds < 60) NV.danger else NV.warning,
                            fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }

        // 待處理任務
        val activeTasks = tasks.filter { it.isActive }
        if (activeTasks.isNotEmpty()) {
            item {
                SectionHeader("待處理任務 (${viewModel.activeTaskCount})", NV.command)
            }
            items(activeTasks, key = { it.id }) { task ->
                CardContainer {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(task.taskStatus.color))
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(task.title, color = NV.white, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                            }
                            if (task.detail.isNotEmpty()) {
                                Text(task.detail, color = NV.textSecondary, fontSize = 12.sp, maxLines = 2)
                            }
                            Text("${task.taskStatus.label} · ${task.timeText}", color = NV.textSecondary, fontSize = 11.sp)
                        }
                        if (task.taskStatus == TaskStatus.PENDING) {
                            Button(
                                onClick = { viewModel.updateTaskStatus(task.id, TaskStatus.ACCEPTED) },
                                colors = ButtonDefaults.buttonColors(containerColor = NV.green),
                                shape = RoundedCornerShape(8.dp),
                                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp)
                            ) {
                                Text("接受", fontSize = 12.sp)
                            }
                        }
                    }
                }
            }
        }

        // 危險標記
        if (hazardReports.isNotEmpty()) {
            item {
                SectionHeader("危險標記 (${hazardReports.size})", NV.danger)
            }
            items(hazardReports.take(3), key = { it.id }) { hazard ->
                CardContainer(borderColor = hazard.severityLevel.color) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Warning, contentDescription = null, tint = hazard.severityLevel.color, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(hazard.hazard?.label ?: hazard.hazardType, color = NV.white, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                            if (hazard.description.isNotEmpty()) {
                                Text(hazard.description, color = NV.textSecondary, fontSize = 12.sp, maxLines = 1)
                            }
                            Text("${hazard.reporterName} · ${if (hazard.zone.isEmpty()) "未知區域" else hazard.zone} · ${hazard.timeText}",
                                color = NV.textSecondary, fontSize = 11.sp)
                        }
                        Text(hazard.severityLevel.label, color = hazard.severityLevel.color, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                            modifier = Modifier.background(hazard.severityLevel.color.copy(alpha = 0.15f), RoundedCornerShape(4.dp))
                                .padding(horizontal = 6.dp, vertical = 2.dp))
                    }
                }
            }
        }

        // 交班摘要按鈕
        item {
            CardContainer {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { showHandoverSummary = true },
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.Assignment, contentDescription = null, tint = NV.green, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("產生交班摘要", color = NV.white, fontSize = 14.sp, fontWeight = FontWeight.Bold,
                        modifier = Modifier.weight(1f))
                    Icon(Icons.Default.ChevronRight, contentDescription = null, tint = NV.textSecondary)
                }
            }
        }

        // 運行時間
        item {
            CardContainer {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text("運行時間", color = NV.textSecondary, fontSize = 12.sp)
                    Text(viewModel.uptimeText(), color = NV.white, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                }
            }
        }

        // 受困者快速列表
        item {
            SectionHeader("受困者")
        }

        if (victims.isEmpty()) {
            item {
                CardContainer {
                    Text("掃描中...", color = NV.textSecondary, modifier = Modifier.padding(8.dp))
                }
            }
        } else {
            items(victims, key = { it.id }) { victim ->
                VictimRow(victim)
            }
        }
    }

    // 交班摘要 Dialog
    if (showHandoverSummary) {
        AlertDialog(
            onDismissRequest = { showHandoverSummary = false },
            title = { Text("交班摘要", fontWeight = FontWeight.Bold) },
            text = {
                val summary = remember { viewModel.generateHandoverSummary() }
                Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                    Text(summary, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, fontSize = 12.sp, color = NV.white)
                }
            },
            confirmButton = {
                val clipboardManager = LocalClipboardManager.current
                val summary = remember { viewModel.generateHandoverSummary() }
                TextButton(onClick = {
                    clipboardManager.setText(AnnotatedString(summary))
                }) { Text("複製", color = NV.green) }
            },
            dismissButton = {
                TextButton(onClick = { showHandoverSummary = false }) { Text("關閉", color = NV.textSecondary) }
            },
            containerColor = NV.card
        )
    }
}

// =====================================================
//  受困者列表
// =====================================================

@Composable
fun VictimListScreen(viewModel: LinkGuardViewModel) {
    val victims by viewModel.victims.collectAsState()
    var showAddDialog by remember { mutableStateOf(false) }

    Box(modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item {
                Spacer(modifier = Modifier.height(12.dp))
                Text("受困者列表", color = NV.blue, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(8.dp))
            }

            if (victims.isEmpty()) {
                item {
                    CardContainer {
                        Text("尚未偵測到受困者", color = NV.textSecondary, modifier = Modifier.padding(16.dp))
                    }
                }
            } else {
                items(victims, key = { it.id }) { victim ->
                    VictimDetailCard(victim)
                }
            }
        }

        // 新增受困者 FAB
        FloatingActionButton(
            onClick = { showAddDialog = true },
            containerColor = NV.green,
            contentColor = NV.white,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(24.dp)
        ) {
            Icon(Icons.Default.PersonAdd, contentDescription = "新增受困者")
        }
    }

    // 新增受困者 Dialog
    if (showAddDialog) {
        AddVictimDialog(
            onDismiss = { showAddDialog = false },
            onConfirm = { id, hr, bat ->
                viewModel.addManualVictim(id, hr, bat)
                showAddDialog = false
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddVictimDialog(
    onDismiss: () -> Unit,
    onConfirm: (id: String, heartRate: Int, battery: Int) -> Unit
) {
    var victimId by remember { mutableStateOf("") }
    var heartRate by remember { mutableStateOf("") }
    var battery by remember { mutableStateOf("100") }

    val dialogFieldColors = OutlinedTextFieldDefaults.colors(
        focusedTextColor = NV.white,
        unfocusedTextColor = NV.white,
        focusedBorderColor = NV.green,
        unfocusedBorderColor = NV.cardBorder,
        focusedLabelColor = NV.green,
        unfocusedLabelColor = NV.textSecondary
    )

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = NV.card,
        title = { Text("手動新增受困者", color = NV.green, fontWeight = FontWeight.Bold) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = victimId,
                    onValueChange = { victimId = it.uppercase() },
                    label = { Text("受困者 ID") },
                    placeholder = { Text("例：V-001", color = NV.textSecondary.copy(alpha = 0.6f)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    colors = dialogFieldColors
                )
                OutlinedTextField(
                    value = heartRate,
                    onValueChange = { heartRate = it.filter { c -> c.isDigit() } },
                    label = { Text("心率 (bpm)") },
                    placeholder = { Text("選填，例：72", color = NV.textSecondary.copy(alpha = 0.6f)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    colors = dialogFieldColors,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                )
                OutlinedTextField(
                    value = battery,
                    onValueChange = { battery = it.filter { c -> c.isDigit() } },
                    label = { Text("電量 (%)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    colors = dialogFieldColors,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    onConfirm(
                        victimId.trim(),
                        heartRate.toIntOrNull() ?: 0,
                        battery.toIntOrNull()?.coerceIn(0, 100) ?: 100
                    )
                },
                enabled = victimId.trim().isNotEmpty(),
                colors = ButtonDefaults.buttonColors(containerColor = NV.green)
            ) { Text("新增", color = NV.white) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消", color = NV.textSecondary) }
        }
    )
}

@Composable
fun VictimDetailCard(victim: VictimNode) {
    CardContainer(
        borderColor = if (victim.isSOS) NV.danger else NV.cardBorder
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            // 標題列
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(if (victim.isOnline) NV.green else NV.textSecondary)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(victim.id, color = NV.white, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                }
                if (victim.isSOS) {
                    Text("SOS", color = NV.danger, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                }
            }

            // 資訊列
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                InfoChip("♡", victim.heartRateText)
                InfoChip("dBm", "${victim.rssi.toInt()}")
                InfoChip("m", victim.distanceText)
                InfoChip("BAT", "${victim.battery}%")
            }

            // 最後更新
            Text(victim.lastSeenText, color = NV.textSecondary, fontSize = 11.sp)
        }
    }
}

// =====================================================
//  SOS 紀錄
// =====================================================

@Composable
fun SOSRecordScreen(viewModel: LinkGuardViewModel) {
    val records by viewModel.sosRecords.collectAsState()

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            Spacer(modifier = Modifier.height(12.dp))
            Text("SOS 警報紀錄", color = NV.danger, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.height(8.dp))
        }

        if (records.isEmpty()) {
            item {
                CardContainer {
                    Text("目前無 SOS 紀錄", color = NV.textSecondary, modifier = Modifier.padding(16.dp))
                }
            }
        } else {
            items(records, key = { it.id }) { record ->
                SOSRecordRow(record, onAcknowledge = { viewModel.acknowledgeRecord(record) })
            }
        }
    }
}

@Composable
fun SOSRecordRow(record: SOSRecord, onAcknowledge: () -> Unit) {
    CardContainer(borderColor = if (record.isAcknowledged) NV.cardBorder else NV.danger) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(record.victimID, color = NV.white, fontWeight = FontWeight.Bold)
                Text(
                    "♡ ${if (record.heartRate > 0) "${record.heartRate} bpm" else "--"} · ${record.distance} · ${record.rssi.toInt()} dBm",
                    color = NV.textSecondary, fontSize = 12.sp
                )
                Text(record.timeText, color = NV.textSecondary, fontSize = 11.sp)
            }
            if (!record.isAcknowledged) {
                Button(
                    onClick = onAcknowledge,
                    colors = ButtonDefaults.buttonColors(containerColor = NV.danger),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)
                ) {
                    Text("確認", fontSize = 12.sp)
                }
            } else {
                Text("已確認", color = NV.greenFaint, fontSize = 12.sp)
            }
        }
    }
}

// =====================================================
//  連線管理
// =====================================================

@Composable
fun ConnectionScreen(viewModel: LinkGuardViewModel) {
    val isConnected by viewModel.bluetoothManager.isConnected.collectAsState()
    val isScanning by viewModel.bluetoothManager.isScanning.collectAsState()
    val devices by viewModel.bluetoothManager.discoveredDevices.collectAsState()
    val deviceName by viewModel.bluetoothManager.connectedDeviceName.collectAsState()
    val nodeStatus by viewModel.nodeStatus.collectAsState()
    var pairInput by remember { mutableStateOf("") }
    var deptInput by remember { mutableStateOf("") }
    var nodeIDInput by remember { mutableStateOf("") }

    LaunchedEffect(nodeStatus.pairCode) {
        pairInput = nodeStatus.pairCode
    }
    LaunchedEffect(nodeStatus.deptCode) {
        deptInput = nodeStatus.deptCode
    }
    LaunchedEffect(nodeStatus.nodeID) {
        nodeIDInput = nodeStatus.nodeID
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Text("連線管理", color = NV.blue, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.height(8.dp))
        }

        // 連線狀態卡
        item {
            CardContainer {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Default.Bluetooth,
                            contentDescription = null,
                            tint = if (isConnected) NV.green else NV.textSecondary
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            if (isConnected) "已連線" else "未連線",
                            color = if (isConnected) NV.green else NV.textSecondary,
                            fontWeight = FontWeight.Bold
                        )
                    }
                    if (isConnected) {
                        Text("裝置: ${deviceName ?: "--"}", color = NV.textSecondary, fontSize = 13.sp)
                        Text("節點 ID: ${nodeStatus.nodeID}", color = NV.textSecondary, fontSize = 13.sp)
                        Text("配對碼: ${nodeStatus.pairCode}", color = NV.textSecondary, fontSize = 13.sp)
                        Text("部門碼: ${nodeStatus.deptCode}", color = NV.textSecondary, fontSize = 13.sp)
                    }
                }
            }
        }

        // 操作按鈕
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (isConnected) {
                    Button(
                        onClick = { viewModel.disconnectDevice() },
                        colors = ButtonDefaults.buttonColors(containerColor = NV.danger),
                        modifier = Modifier.weight(1f)
                    ) { Text("斷開連線") }
                } else {
                    Button(
                        onClick = {
                            if (isScanning) viewModel.stopScanning() else viewModel.scanForDevices()
                        },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (isScanning) NV.warning else NV.blue
                        ),
                        modifier = Modifier.weight(1f)
                    ) { Text(if (isScanning) "停止掃描" else "掃描裝置") }
                }
            }
        }

        // 配對碼設定
        if (isConnected) {
            item {
                CardContainer {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("LoRa 配對碼", color = NV.blue, fontWeight = FontWeight.Bold)
                        Text("設定相同配對碼的裝置才能互相通訊", color = NV.textSecondary, fontSize = 12.sp)
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            OutlinedTextField(
                                value = pairInput,
                                onValueChange = { if (it.length <= 8) pairInput = it.uppercase() },
                                label = { Text("配對碼 (1-8 字元)") },
                                singleLine = true,
                                modifier = Modifier.weight(1f),
                                colors = OutlinedTextFieldDefaults.colors(
                                    focusedTextColor = NV.white,
                                    unfocusedTextColor = NV.white,
                                    focusedBorderColor = NV.blue,
                                    unfocusedBorderColor = NV.textSecondary,
                                    focusedLabelColor = NV.blue,
                                    unfocusedLabelColor = NV.textSecondary
                                )
                            )
                            Button(
                                onClick = { viewModel.changePairCode(pairInput) },
                                colors = ButtonDefaults.buttonColors(containerColor = NV.blue),
                                enabled = pairInput.isNotBlank() && pairInput != nodeStatus.pairCode
                            ) { Text("更新") }
                        }
                    }
                }
            }
        }

        // 節點 ID 設定
        item {
            CardContainer {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("節點 ID", color = NV.blue, fontWeight = FontWeight.Bold)
                    Text("自訂裝置識別碼，LoRa 連線後由韌體覆蓋", color = NV.textSecondary, fontSize = 12.sp)
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedTextField(
                            value = nodeIDInput,
                            onValueChange = { if (it.length <= 10) nodeIDInput = it.uppercase() },
                            label = { Text("節點 ID (最多 10 字元)") },
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedTextColor = NV.white,
                                unfocusedTextColor = NV.white,
                                focusedBorderColor = NV.blue,
                                unfocusedBorderColor = NV.textSecondary,
                                focusedLabelColor = NV.blue,
                                unfocusedLabelColor = NV.textSecondary
                            )
                        )
                        Button(
                            onClick = { viewModel.changeNodeID(nodeIDInput) },
                            colors = ButtonDefaults.buttonColors(containerColor = NV.blue),
                            enabled = nodeIDInput.isNotBlank() && nodeIDInput != nodeStatus.nodeID
                        ) { Text("更新") }
                    }
                }
            }
        }

        // 部門碼設定
        item {
            CardContainer {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("部門碼", color = NV.blue, fontWeight = FontWeight.Bold)
                    Text("設定所屬部門代碼 (EMT / FD / PD)", color = NV.textSecondary, fontSize = 12.sp)
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedTextField(
                            value = deptInput,
                            onValueChange = { if (it.length <= 3) deptInput = it.uppercase() },
                            label = { Text("部門碼 (1-3 字元)") },
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedTextColor = NV.white,
                                unfocusedTextColor = NV.white,
                                focusedBorderColor = NV.blue,
                                unfocusedBorderColor = NV.textSecondary,
                                focusedLabelColor = NV.blue,
                                unfocusedLabelColor = NV.textSecondary
                            )
                        )
                        Button(
                            onClick = { viewModel.changeDeptCode(deptInput) },
                            colors = ButtonDefaults.buttonColors(containerColor = NV.blue),
                            enabled = deptInput.isNotBlank() && deptInput != nodeStatus.deptCode
                        ) { Text("更新") }
                    }
                }
            }
        }

        // 已發現裝置列表
        if (!isConnected && devices.isNotEmpty()) {
            item {
                SectionHeader("已發現裝置")
            }
            items(devices, key = { it.address }) { device ->
                CardContainer {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { viewModel.connectToDevice(device) },
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text(device.name, color = NV.white, fontWeight = FontWeight.Bold)
                            Text(device.address, color = NV.textSecondary, fontSize = 11.sp)
                        }
                        Text("${device.rssi} dBm", color = NV.textSecondary, fontSize = 12.sp)
                    }
                }
            }
        }

        // 語言切換
        item {
            val context = LocalContext.current
            val currentLang = remember { mutableStateOf(com.linkguard.app.util.LocaleHelper.getLanguage(context)) }
            CardContainer {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("語言 / Language", color = NV.blue, fontWeight = FontWeight.Bold)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        listOf("zh" to "中文", "en" to "EN").forEach { (code, label) ->
                            Button(
                                onClick = {
                                    if (currentLang.value != code) {
                                        com.linkguard.app.util.LocaleHelper.setLanguage(context, code)
                                        (context as? android.app.Activity)?.recreate()
                                    }
                                },
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = if (currentLang.value == code) NV.blue else NV.card
                                ),
                                modifier = Modifier.weight(1f)
                            ) { Text(label, color = NV.white) }
                        }
                    }
                }
            }
        }

        // 模擬模式
        item {
            val isSimulating by viewModel.isSimulating.collectAsState()
            CardContainer {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("模擬模式", color = NV.simulation, fontWeight = FontWeight.Bold)
                    Text("在沒有硬體時模擬受困者訊號、SOS 警報等即時資料變化，適用於 Demo 展示。",
                        color = NV.textSecondary, fontSize = 12.sp)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("即時模擬", color = NV.white)
                        Switch(
                            checked = isSimulating,
                            onCheckedChange = { viewModel.toggleSimulation() },
                            colors = SwitchDefaults.colors(
                                checkedThumbColor = NV.white,
                                checkedTrackColor = NV.simulation,
                                uncheckedThumbColor = NV.textSecondary,
                                uncheckedTrackColor = NV.card
                            )
                        )
                    }
                }
            }
        }

        // LoRa 檔位選擇器
        if (isConnected) {
            item {
                CardContainer {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("LoRa 檔位", color = NV.blue, fontWeight = FontWeight.Bold)
                        Text("調整 LoRa 傳輸參數以適應不同距離與環境", color = NV.textSecondary, fontSize = 12.sp)

                        var expanded by remember { mutableStateOf(false) }
                        Box {
                            Button(
                                onClick = { expanded = true },
                                colors = ButtonDefaults.buttonColors(containerColor = NV.card),
                                border = androidx.compose.foundation.BorderStroke(1.dp, NV.cardBorder),
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(nodeStatus.loraProfile.label, color = NV.white)
                                    Icon(Icons.Default.ArrowDropDown, contentDescription = null, tint = NV.textSecondary)
                                }
                            }
                            DropdownMenu(
                                expanded = expanded,
                                onDismissRequest = { expanded = false },
                                modifier = Modifier.background(NV.card)
                            ) {
                                loraProfiles.forEach { profile ->
                                    DropdownMenuItem(
                                        text = { Text(profile.label, color = if (profile.level == nodeStatus.loraLevel) NV.green else NV.white) },
                                        onClick = {
                                            viewModel.changeLoRaLevel(profile.level)
                                            expanded = false
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // WiFi 命令模式
        item {
            val isWiFiCmdMode by viewModel.isWiFiCommandMode.collectAsState()
            CardContainer {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("WiFi 命令同步", color = NV.info, fontWeight = FontWeight.Bold)
                    Text("透過 WiFi NTP 時間同步，所有連到同一網路的裝置會在相同時間點收到相同的指揮命令。不需要 LoRa 硬體。",
                        color = NV.textSecondary, fontSize = 12.sp)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("WiFi 命令同步", color = NV.white)
                        Switch(
                            checked = isWiFiCmdMode,
                            onCheckedChange = { viewModel.toggleWiFiCommandMode() },
                            colors = SwitchDefaults.colors(
                                checkedThumbColor = NV.white,
                                checkedTrackColor = NV.info,
                                uncheckedThumbColor = NV.textSecondary,
                                uncheckedTrackColor = NV.card
                            )
                        )
                    }
                }
            }
        }

        // 系統資訊
        item {
            CardContainer {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("系統資訊", color = NV.blue, fontWeight = FontWeight.Bold)
                    InfoRow("節點 ID", nodeStatus.nodeID)
                    InfoRow("配對碼", nodeStatus.pairCode)
                    InfoRow("部門碼", nodeStatus.deptCode)
                    InfoRow("節點電量", "${nodeStatus.battery}%")
                    InfoRow("LoRa 檔位", nodeStatus.loraProfile.label)
                    InfoRow("運行時間", viewModel.uptimeText())
                    val v by viewModel.victims.collectAsState()
                    InfoRow("受困者總數", "${v.size}")
                    InfoRow("線上受困者", "${v.count { it.isOnline }}")
                    InfoRow("SOS 求救中", "${v.count { it.isSOS && it.isOnline }}")
                }
            }
        }

        // 指揮中心 WiFi 連線
        item {
            val wifiConnected by viewModel.commandClient.isConnected.collectAsState()
            val wifiServer by viewModel.commandClient.serverName.collectAsState()
            var manualIP by remember { mutableStateOf("") }
            var manualPort by remember { mutableStateOf("8930") }

            CardContainer(borderColor = if (wifiConnected) NV.green else NV.cardBorder) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("指揮中心 WiFi", color = NV.command, fontWeight = FontWeight.Bold)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Default.Wifi,
                            contentDescription = null,
                            tint = if (wifiConnected) NV.green else NV.textSecondary,
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            if (wifiConnected) "已連線" else "搜尋中...",
                            color = if (wifiConnected) NV.green else NV.textSecondary,
                            fontSize = 13.sp
                        )
                    }
                    if (wifiConnected && wifiServer.isNotEmpty()) {
                        InfoRow("伺服器", wifiServer)
                    }
                    if (!wifiConnected) {
                        Spacer(modifier = Modifier.height(4.dp))
                        Text("手動連線", color = NV.textSecondary, fontSize = 12.sp)
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            OutlinedTextField(
                                value = manualIP,
                                onValueChange = { manualIP = it },
                                placeholder = { Text("指揮中心 IP", fontSize = 12.sp, color = NV.textSecondary.copy(alpha = 0.6f)) },
                                singleLine = true,
                                modifier = Modifier.weight(1f).height(48.dp),
                                textStyle = androidx.compose.ui.text.TextStyle(fontSize = 13.sp, color = NV.white),
                                colors = OutlinedTextFieldDefaults.colors(
                                    unfocusedBorderColor = NV.cardBorder,
                                    focusedBorderColor = NV.command
                                )
                            )
                            OutlinedTextField(
                                value = manualPort,
                                onValueChange = { manualPort = it },
                                placeholder = { Text("Port", fontSize = 12.sp, color = NV.textSecondary.copy(alpha = 0.6f)) },
                                singleLine = true,
                                modifier = Modifier.width(72.dp).height(48.dp),
                                textStyle = androidx.compose.ui.text.TextStyle(fontSize = 13.sp, color = NV.white),
                                colors = OutlinedTextFieldDefaults.colors(
                                    unfocusedBorderColor = NV.cardBorder,
                                    focusedBorderColor = NV.command
                                )
                            )
                            Button(
                                onClick = {
                                    val ip = manualIP.trim()
                                    val port = manualPort.toIntOrNull() ?: 8930
                                    if (ip.isNotEmpty()) {
                                        viewModel.commandClient.connectToIP(ip, port)
                                    }
                                },
                                enabled = manualIP.trim().isNotEmpty(),
                                colors = ButtonDefaults.buttonColors(containerColor = NV.command)
                            ) {
                                Text("連線", fontSize = 12.sp)
                            }
                        }
                    }
                }
            }
        }
    }
}

// =====================================================
//  SOS 全螢幕警報覆蓋層
// =====================================================

@Composable
fun SOSAlertOverlay(victim: VictimNode, onDismiss: () -> Unit) {
    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val alpha by infiniteTransition.animateFloat(
        initialValue = 0.85f, targetValue = 0.95f,
        animationSpec = infiniteRepeatable(
            animation = tween(800), repeatMode = RepeatMode.Reverse
        ), label = "pulseAlpha"
    )
    val scale by infiniteTransition.animateFloat(
        initialValue = 1.0f, targetValue = 1.15f,
        animationSpec = infiniteRepeatable(
            animation = tween(800), repeatMode = RepeatMode.Reverse
        ), label = "pulseScale"
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(NV.danger.copy(alpha = alpha)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(32.dp).widthIn(max = 500.dp)
        ) {
            Spacer(modifier = Modifier.weight(1f))

            // SOS 圖示
            Icon(Icons.Default.Warning, contentDescription = "SOS", tint = NV.textOnColor,
                modifier = Modifier.size(64.dp).graphicsLayer(scaleX = scale, scaleY = scale))
            Spacer(modifier = Modifier.height(16.dp))

            Text("SOS 求救警報", color = NV.textOnColor, fontSize = 28.sp, fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.height(24.dp))

            // 受困者資訊卡
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(NVShape.card)
                    .background(Color.White.copy(alpha = 0.15f))
                    .padding(24.dp)
            ) {
                Text(victim.id, color = NV.textOnColor, fontSize = 22.sp, fontWeight = FontWeight.Bold)

                Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Default.Favorite, contentDescription = null, tint = NV.heartRate, modifier = Modifier.size(28.dp))
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(victim.heartRateText, color = NV.textOnColor, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                    }
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Default.LocationOn, contentDescription = null, tint = NV.info, modifier = Modifier.size(28.dp))
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(victim.distanceText, color = NV.textOnColor, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                    }
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Default.SignalCellularAlt, contentDescription = null, tint = NV.green, modifier = Modifier.size(28.dp))
                        Spacer(modifier = Modifier.height(4.dp))
                        Text("${victim.rssi.toInt()} dBm", color = NV.textOnColor, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                    }
                }

                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text("BAT ${victim.battery}%", color = NV.textOnColor, fontSize = 14.sp)
                    Text(
                        if (victim.isOnline) "線上" else "離線",
                        color = if (victim.isOnline) NV.green else NV.greenFaint,
                        fontSize = 14.sp, fontWeight = FontWeight.Bold
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // 確認按鈕（白底紅字）
            Button(
                onClick = onDismiss,
                colors = ButtonDefaults.buttonColors(containerColor = NV.textOnColor),
                modifier = Modifier.fillMaxWidth().widthIn(max = 400.dp).height(56.dp),
                shape = NVShape.card
            ) {
                Icon(Icons.Default.CheckCircle, contentDescription = null, tint = NV.danger, modifier = Modifier.size(28.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("收到", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = NV.danger)
            }

            Spacer(modifier = Modifier.height(40.dp))
        }
    }
}

// =====================================================
//  指揮中心命令列表
// =====================================================

@Composable
fun CommandListScreen(viewModel: LinkGuardViewModel) {
    val orders by viewModel.commandOrders.collectAsState()

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("指揮命令", color = NV.command, fontSize = 20.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(top = 12.dp))
                if (viewModel.unreadCommandCount > 0) {
                    Button(
                        onClick = { viewModel.markAllCommandsAsRead() },
                        colors = ButtonDefaults.buttonColors(containerColor = NV.command),
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)
                    ) { Text("全部已讀", fontSize = 12.sp) }
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
        }

        if (orders.isEmpty()) {
            item {
                CardContainer {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text("等待指揮中心命令...", color = NV.textSecondary)
                    }
                }
            }
        } else {
            items(orders, key = { it.id }) { order ->
                CommandOrderRow(order = order, onMarkRead = { viewModel.markCommandAsRead(order) })
            }
        }
    }
}

@Composable
fun CommandOrderRow(order: CommandOrder, onMarkRead: () -> Unit) {
    CardContainer(borderColor = if (!order.isRead) order.priority.color else NV.cardBorder) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(order.priority.icon, fontSize = 16.sp)
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(order.title, color = NV.white, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    if (!order.isRead) {
                        Spacer(modifier = Modifier.width(6.dp))
                        Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(NV.info))
                    }
                }
                Spacer(modifier = Modifier.height(4.dp))
                Text(order.detail, color = NV.textSecondary, fontSize = 12.sp, maxLines = 2)
                Spacer(modifier = Modifier.height(4.dp))
                Row {
                    Text("${order.type.icon} ${order.type.label}", color = NV.textSecondary, fontSize = 11.sp)
                    Text(" · ", color = NV.textSecondary, fontSize = 11.sp)
                    Text(order.sender, color = NV.textSecondary, fontSize = 11.sp)
                    Text(" · ", color = NV.textSecondary, fontSize = 11.sp)
                    Text(order.timeText, color = NV.textSecondary, fontSize = 11.sp)
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    order.priority.label,
                    color = NV.textOnColor,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .background(order.priority.color, RoundedCornerShape(4.dp))
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                )
                if (!order.isRead) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Button(
                        onClick = onMarkRead,
                        colors = ButtonDefaults.buttonColors(containerColor = NV.command),
                        contentPadding = PaddingValues(horizontal = 10.dp, vertical = 2.dp)
                    ) { Text("已讀", fontSize = 11.sp) }
                }
            }
        }
    }
}

// =====================================================
//  指揮命令全螢幕警報覆蓋層
// =====================================================

@Composable
fun CommandAlertOverlay(command: CommandOrder, onDismiss: () -> Unit) {
    val infiniteTransition = rememberInfiniteTransition(label = "cmdPulse")
    val alpha by infiniteTransition.animateFloat(
        initialValue = 0.85f, targetValue = 0.95f,
        animationSpec = infiniteRepeatable(
            animation = tween(500), repeatMode = RepeatMode.Reverse
        ), label = "cmdAlpha"
    )
    val scale by infiniteTransition.animateFloat(
        initialValue = 1.0f, targetValue = 1.2f,
        animationSpec = infiniteRepeatable(
            animation = tween(500), repeatMode = RepeatMode.Reverse
        ), label = "cmdScale"
    )

    val alertColor = if (command.priority == com.linkguard.app.model.CommandPriority.CRITICAL)
        NV.danger else NV.command

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(alertColor.copy(alpha = alpha)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(32.dp).widthIn(max = 500.dp)
        ) {
            Spacer(modifier = Modifier.weight(1f))

            Text(
                if (command.priority == com.linkguard.app.model.CommandPriority.CRITICAL) "緊急" else "命令",
                fontSize = 36.sp,
                color = NV.textOnColor,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.graphicsLayer(scaleX = scale, scaleY = scale)
            )
            Spacer(modifier = Modifier.height(16.dp))

            Text(
                if (command.priority == com.linkguard.app.model.CommandPriority.CRITICAL) "緊急命令" else "指揮中心命令",
                color = NV.textOnColor,
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(24.dp))

            // 命令資訊卡（半透明材質）
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(NVShape.card)
                    .background(Color.White.copy(alpha = 0.15f))
                    .padding(24.dp)
            ) {
                Row {
                    Text(command.type.icon, fontSize = 16.sp)
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(command.type.label, color = NV.textOnColor, fontWeight = FontWeight.Bold)
                }
                Text(command.title, color = NV.textOnColor, fontSize = 20.sp, fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center)
                Text(command.detail, color = NV.textOnColor.copy(alpha = 0.8f), fontSize = 14.sp,
                    textAlign = TextAlign.Center)
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("🏢 ${command.sender}", color = NV.textOnColor.copy(alpha = 0.7f), fontSize = 13.sp)
                    Text("${command.priority.icon} ${command.priority.label}",
                        color = NV.textOnColor, fontSize = 13.sp, fontWeight = FontWeight.Bold)
                    Text(command.timeText, color = NV.textOnColor.copy(alpha = 0.7f), fontSize = 13.sp)
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // 確認按鈕（白底色字）
            Button(
                onClick = onDismiss,
                colors = ButtonDefaults.buttonColors(containerColor = NV.textOnColor),
                modifier = Modifier.fillMaxWidth().widthIn(max = 400.dp).height(56.dp),
                shape = NVShape.card
            ) {
                Icon(Icons.Default.CheckCircle, contentDescription = null, tint = alertColor, modifier = Modifier.size(28.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("收到", color = alertColor, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            }

            Spacer(modifier = Modifier.height(40.dp))
        }
    }
}

// =====================================================
//  增援請求
// =====================================================

@Composable
fun ReinforcementScreen(viewModel: LinkGuardViewModel) {
    val requests by viewModel.reinforcementRequests.collectAsState()
    var showSendDialog by remember { mutableStateOf(false) }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("增援請求", color = NV.reinforce, fontSize = 20.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(top = 12.dp))
                Button(
                    onClick = { showSendDialog = true },
                    colors = ButtonDefaults.buttonColors(containerColor = NV.reinforce),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)
                ) { Text("發送增援", fontSize = 12.sp) }
            }
            Spacer(modifier = Modifier.height(8.dp))
        }

        if (requests.isEmpty()) {
            item {
                CardContainer {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(Icons.Default.Shield, contentDescription = null, tint = NV.textSecondary, modifier = Modifier.size(36.dp))
                        Spacer(modifier = Modifier.height(8.dp))
                        Text("目前無增援請求", color = NV.textSecondary)
                    }
                }
            }
        } else {
            items(requests, key = { it.id }) { req ->
                ReinforcementRow(req, viewModel)
            }
        }
    }

    if (showSendDialog) {
        SendReinforcementDialog(
            onDismiss = { showSendDialog = false },
            onSend = { msg, loc ->
                viewModel.sendReinforcementRequest(msg, loc)
                showSendDialog = false
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SendReinforcementDialog(onDismiss: () -> Unit, onSend: (String, String) -> Unit) {
    var message by remember { mutableStateOf("") }
    var location by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = NV.card,
        title = { Text("發送增援請求", color = NV.reinforce) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = message,
                    onValueChange = { message = it },
                    label = { Text("訊息") },
                    singleLine = false,
                    maxLines = 3,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = NV.white,
                        unfocusedTextColor = NV.white,
                        focusedBorderColor = NV.warning,
                        unfocusedBorderColor = NV.textSecondary,
                        focusedLabelColor = NV.warning,
                        unfocusedLabelColor = NV.textSecondary
                    )
                )
                OutlinedTextField(
                    value = location,
                    onValueChange = { location = it },
                    label = { Text("位置描述") },
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = NV.white,
                        unfocusedTextColor = NV.white,
                        focusedBorderColor = NV.warning,
                        unfocusedBorderColor = NV.textSecondary,
                        focusedLabelColor = NV.warning,
                        unfocusedLabelColor = NV.textSecondary
                    )
                )
            }
        },
        confirmButton = {
            Button(
                onClick = { onSend(message, location) },
                enabled = message.isNotBlank(),
                colors = ButtonDefaults.buttonColors(containerColor = NV.reinforce)
            ) { Text("發送") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消", color = NV.textSecondary) }
        }
    )
}

@Composable
fun ReinforcementRow(request: ReinforcementRequest, viewModel: LinkGuardViewModel) {
    CardContainer(borderColor = request.status.color) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Shield, contentDescription = null, tint = NV.team, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(request.fromTeam, color = NV.white, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    if (request.isFromSelf) {
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("(自己)", color = NV.textSecondary, fontSize = 11.sp)
                    }
                }
                Text(
                    request.status.label,
                    color = NV.textOnColor,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .background(request.status.color, RoundedCornerShape(4.dp))
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                )
            }
            Text(request.message, color = NV.textSecondary, fontSize = 13.sp)
            if (request.location.isNotEmpty()) {
                Text("位置：${request.location}", color = NV.textSecondary, fontSize = 12.sp)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(request.timeText, color = NV.textSecondary, fontSize = 11.sp)
                if (request.respondedBy.isNotEmpty()) {
                    Text(" · 回覆: ${request.respondedBy.joinToString(", ")}", color = NV.textSecondary, fontSize = 11.sp)
                }
            }

            if (request.status == ReinforcementStatus.PENDING && !request.isFromSelf) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = { viewModel.acceptReinforcement(request) },
                        colors = ButtonDefaults.buttonColors(containerColor = NV.green),
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)
                    ) { Text("加入", fontSize = 12.sp) }
                    Button(
                        onClick = { viewModel.declineReinforcement(request) },
                        colors = ButtonDefaults.buttonColors(containerColor = NV.danger),
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)
                    ) { Text("拒絕", fontSize = 12.sp) }
                }
            }
        }
    }
}

// =====================================================
//  增援請求全螢幕覆蓋層
// =====================================================

@Composable
fun ReinforcementAlertOverlay(
    request: ReinforcementRequest,
    onAccept: () -> Unit,
    onDecline: () -> Unit
) {
    val infiniteTransition = rememberInfiniteTransition(label = "rfPulse")
    val alpha by infiniteTransition.animateFloat(
        initialValue = 0.85f, targetValue = 0.95f,
        animationSpec = infiniteRepeatable(
            animation = tween(600), repeatMode = RepeatMode.Reverse
        ), label = "rfAlpha"
    )
    val scale by infiniteTransition.animateFloat(
        initialValue = 1.0f, targetValue = 1.1f,
        animationSpec = infiniteRepeatable(
            animation = tween(600), repeatMode = RepeatMode.Reverse
        ), label = "rfScale"
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(NV.reinforce.copy(alpha = alpha)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(32.dp).widthIn(max = 500.dp)
        ) {
            Spacer(modifier = Modifier.weight(1f))

            Icon(Icons.Default.SupportAgent, contentDescription = null, tint = NV.textOnColor,
                modifier = Modifier.size(80.dp).graphicsLayer(scaleX = scale, scaleY = scale))
            Spacer(modifier = Modifier.height(16.dp))
            Text("增援請求", color = NV.textOnColor, fontSize = 28.sp, fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.height(24.dp))

            // 增援資訊卡（半透明材質）
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(NVShape.card)
                    .background(Color.White.copy(alpha = 0.15f))
                    .padding(24.dp)
            ) {
                Text("來自 ${request.fromTeam}", color = NV.textOnColor, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Text(request.message, color = NV.textOnColor.copy(alpha = 0.8f), fontSize = 14.sp, textAlign = TextAlign.Center)
                if (request.location.isNotEmpty()) {
                    Text("位置：${request.location}", color = NV.textOnColor.copy(alpha = 0.7f), fontSize = 13.sp)
                }
                Text(request.timeText, color = NV.textOnColor.copy(alpha = 0.7f), fontSize = 13.sp)
            }

            Spacer(modifier = Modifier.weight(1f))

            // 雙按鈕（白底彩字）
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Button(
                    onClick = onDecline,
                    colors = ButtonDefaults.buttonColors(containerColor = NV.textOnColor),
                    modifier = Modifier.weight(1f).height(56.dp),
                    shape = NVShape.card
                ) {
                    Icon(Icons.Default.Cancel, contentDescription = null, tint = NV.danger, modifier = Modifier.size(24.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("拒絕", color = NV.danger, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                }
                Button(
                    onClick = onAccept,
                    colors = ButtonDefaults.buttonColors(containerColor = NV.textOnColor),
                    modifier = Modifier.weight(1f).height(56.dp),
                    shape = NVShape.card
                ) {
                    Icon(Icons.Default.CheckCircle, contentDescription = null, tint = NV.green, modifier = Modifier.size(24.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("加入", color = NV.green, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                }
            }

            Spacer(modifier = Modifier.height(40.dp))
        }
    }
}

// =====================================================
//  團隊成員
// =====================================================

@Composable
fun TeamScreen(viewModel: LinkGuardViewModel) {
    val members by viewModel.teamMembers.collectAsState()
    val nodeStatus by viewModel.nodeStatus.collectAsState()

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("團隊成員", color = NV.team, fontSize = 20.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(top = 12.dp))
                Button(
                    onClick = { viewModel.sendTeamPing() },
                    colors = ButtonDefaults.buttonColors(containerColor = NV.team),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)
                ) { Text("呼叫", fontSize = 12.sp) }
            }
            Spacer(modifier = Modifier.height(8.dp))
        }

        // 自己
        item {
            CardContainer(borderColor = NV.team) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(NV.green))
                        Spacer(modifier = Modifier.width(8.dp))
                        Column {
                            Text("${nodeStatus.nodeID} (自己)", color = NV.white, fontWeight = FontWeight.Bold)
                            Text("部門: ${nodeStatus.deptCode}", color = NV.textSecondary, fontSize = 12.sp)
                        }
                    }
                    Text("BAT: ${nodeStatus.battery}%", color = NV.textSecondary, fontSize = 12.sp)
                }
            }
        }

        if (members.isEmpty()) {
            item {
                CardContainer {
                    Text("尚未發現其他團隊成員", color = NV.textSecondary, modifier = Modifier.padding(16.dp))
                }
            }
        } else {
            items(members, key = { it.id }) { member ->
                TeamMemberRow(member)
            }
        }

        // 統計
        item {
            CardContainer {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("團隊統計", color = NV.team, fontWeight = FontWeight.Bold)
                    InfoRow("在線成員", "${members.count { it.isOnline } + 1}")
                    InfoRow("總受困者覆蓋", "${members.sumOf { it.victimCount } + viewModel.onlineVictimCount}")
                }
            }
        }
    }
}

@Composable
fun TeamMemberRow(member: TeamMember) {
    CardContainer(borderColor = if (member.isOnline) NV.cardBorder else NV.textSecondary) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(if (member.isOnline) NV.green else NV.textSecondary)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Column {
                    Text(member.id, color = NV.white, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Text("部門: ${member.deptCode}", color = NV.textSecondary, fontSize = 12.sp)
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                Text("BAT: ${member.battery}%", color = NV.textSecondary, fontSize = 12.sp)
                Text("RSSI: ${member.rssi.toInt()} dBm", color = member.signalColor, fontSize = 11.sp)
                Text("受困者: ${member.victimCount}", color = NV.textSecondary, fontSize = 11.sp)
                Text(member.lastSeenText, color = NV.textSecondary, fontSize = 11.sp)
            }
        }
    }
}

// =====================================================
//  資訊列
// =====================================================

@Composable
fun InfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, color = NV.textSecondary, fontSize = 13.sp)
        Text(value, color = NV.white, fontWeight = FontWeight.Bold, fontSize = 13.sp)
    }
}

// =====================================================
//  共用元件
// =====================================================

@Composable
fun SectionHeader(title: String, accentColor: Color = NV.blue) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .width(3.dp)
                .height(16.dp)
                .clip(RoundedCornerShape(1.5.dp))
                .background(accentColor)
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(title, color = NV.textPrimary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun CardContainer(
    borderColor: Color = NV.cardBorder,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(6.dp, NVShape.card, ambientColor = Color.Black.copy(alpha = 0.5f), spotColor = Color.Black.copy(alpha = 0.3f))
            .clip(NVShape.card)
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        NV.card,
                        Color(0xFF131920)
                    )
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

// MARK: - 緊急文字廣播覆蓋層

@Composable
fun UrgentBroadcastOverlay(broadcast: TextBroadcast, onDismiss: () -> Unit) {
    Box(
        modifier = Modifier.fillMaxSize().background(NV.reinforce.copy(alpha = 0.95f)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
            modifier = Modifier.padding(40.dp)
        ) {
            Icon(Icons.Default.Warning, contentDescription = null,
                tint = NV.textOnColor, modifier = Modifier.size(60.dp))
            Text("緊急廣播", color = NV.textOnColor, fontSize = 24.sp, fontWeight = FontWeight.Bold)
            Text(broadcast.message, color = NV.textOnColor, fontSize = 20.sp,
                textAlign = TextAlign.Center)
            Text("來自: ${broadcast.senderName}", color = NV.textOnColor.copy(alpha = 0.8f), fontSize = 14.sp)
            Spacer(Modifier.height(16.dp))
            Button(onClick = onDismiss, colors = ButtonDefaults.buttonColors(
                containerColor = NV.textOnColor, contentColor = NV.reinforce
            )) {
                Text("確認")
            }
        }
    }
}

// MARK: - 傷患惡化預警覆蓋層

@Composable
fun PatientWarningOverlay(warning: PatientWarning, onDismiss: () -> Unit) {
    val levelColor = when (warning.warningLevel) {
        "high" -> NV.danger
        "medium" -> NV.warning
        else -> NV.warning.copy(alpha = 0.7f)
    }

    Box(
        modifier = Modifier.fillMaxSize().background(NV.bg.copy(alpha = 0.75f)),
        contentAlignment = Alignment.Center
    ) {
        Card(
            modifier = Modifier.padding(40.dp).fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = NV.card),
            elevation = CardDefaults.cardElevation(defaultElevation = 12.dp),
            shape = NVShape.card
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.padding(24.dp)
            ) {
                Icon(Icons.Default.MonitorHeart, contentDescription = null,
                    tint = levelColor, modifier = Modifier.size(48.dp))
                Text("傷患惡化預警", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = NV.white)
                Text("患者: ${warning.patientId}", fontSize = 14.sp, color = NV.white)
                Text("檢傷等級: ${warning.priority}", fontSize = 14.sp, color = NV.white)
                Text("位置: ${warning.location}", fontSize = 14.sp, color = NV.white)
                Text("已等候: ${warning.minutesSinceTriage} 分鐘", fontSize = 14.sp, color = NV.white)
                Text(warning.message, fontSize = 14.sp, textAlign = TextAlign.Center,
                    color = NV.textSecondary)
                Spacer(Modifier.height(8.dp))
                Button(onClick = onDismiss, colors = ButtonDefaults.buttonColors(
                    containerColor = levelColor
                )) {
                    Text("已知悉")
                }
            }
        }
    }
}

@Composable
fun StatCard(label: String, value: String, color: Color, modifier: Modifier = Modifier, icon: ImageVector? = null, onClick: (() -> Unit)? = null) {
    Column(
        modifier = modifier
            .shadow(8.dp, NVShape.card, ambientColor = color.copy(alpha = 0.15f), spotColor = color.copy(alpha = 0.1f))
            .clip(NVShape.card)
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        NV.card,
                        Color(0xFF131920)
                    )
                )
            )
            .drawBehind {
                // 色彩染色層
                drawRect(color = color.copy(alpha = 0.07f))
            }
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
            .then(if (onClick != null) Modifier.clickable { onClick() } else Modifier)
            .padding(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = color.copy(alpha = 0.6f), modifier = Modifier.size(20.dp))
            Spacer(modifier = Modifier.height(6.dp))
        }
        Text(value, color = color, fontSize = 24.sp, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(4.dp))
        Text(label, color = NV.textSecondary, fontSize = 11.sp)
    }
}

@Composable
fun VictimRow(victim: VictimNode) {
    CardContainer(borderColor = if (victim.isSOS) NV.danger else NV.cardBorder) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(if (victim.isOnline) NV.green else NV.textSecondary)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Column {
                    Text(victim.id, color = NV.white, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Text(
                        "♡ ${victim.heartRateText} · ${victim.distanceText}",
                        color = NV.textSecondary, fontSize = 12.sp
                    )
                }
            }
            if (victim.isSOS) {
                Text("SOS", color = NV.danger, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
fun InfoChip(icon: String, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(icon, fontSize = 12.sp)
        Spacer(modifier = Modifier.width(4.dp))
        Text(text, color = NV.textSecondary, fontSize = 12.sp)
    }
}

// =====================================================
//  收到 TCP SOS 全螢幕覆蓋層
// =====================================================

@Composable
fun IncomingSOSOverlay(alert: TCPSOSAlert, onDismiss: () -> Unit) {
    val pulseAnim = rememberInfiniteTransition(label = "sos_overlay")
    val scale by pulseAnim.animateFloat(
        initialValue = 1f, targetValue = 1.15f,
        animationSpec = infiniteRepeatable(tween(600), RepeatMode.Reverse), label = "pulse"
    )

    Box(
        modifier = Modifier.fillMaxSize().background(NV.bg.copy(alpha = 0.92f)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = Modifier.padding(32.dp)
        ) {
            Icon(
                Icons.Default.Warning,
                contentDescription = null,
                tint = NV.danger,
                modifier = Modifier.size(100.dp).graphicsLayer(scaleX = scale, scaleY = scale)
            )
            Spacer(modifier = Modifier.height(24.dp))
            Text("收到緊急求救", color = NV.textOnColor, fontSize = 28.sp, fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                "發送者：${alert.senderName.ifEmpty { alert.senderID }}",
                color = NV.textOnColor, fontSize = 18.sp
            )
            if (alert.message.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(alert.message, color = NV.textOnColor.copy(alpha = 0.8f))
            }
            if (alert.lat != 0.0 || alert.lon != 0.0) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "GPS: %.5f, %.5f".format(alert.lat, alert.lon),
                    color = NV.textOnColor.copy(alpha = 0.6f), fontSize = 12.sp
                )
            }
            Spacer(modifier = Modifier.height(32.dp))
            Button(
                onClick = onDismiss,
                colors = ButtonDefaults.buttonColors(containerColor = NV.danger),
                modifier = Modifier.fillMaxWidth().height(56.dp)
            ) {
                Text("確認收到", fontSize = 18.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}
