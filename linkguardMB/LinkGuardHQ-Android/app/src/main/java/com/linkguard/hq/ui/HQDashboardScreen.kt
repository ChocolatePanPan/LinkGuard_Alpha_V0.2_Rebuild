package com.linkguard.hq.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.windowsizeclass.WindowSizeClass
import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.linkguard.hq.R
import com.linkguard.hq.model.*
import com.linkguard.hq.net.DiscoveredHQServer
import com.linkguard.hq.viewmodel.HQViewModel

// =====================================================
//  HQ Dashboard — 主畫面
// =====================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HQDashboardScreen(viewModel: HQViewModel, windowSizeClass: WindowSizeClass? = null) {
    val useSidebar = windowSizeClass?.widthSizeClass != WindowWidthSizeClass.Compact
    var selectedTab by remember { mutableIntStateOf(0) }
    val tabs = listOf(
        stringResource(R.string.tab_overview), stringResource(R.string.tab_command), stringResource(R.string.tab_field_units),
        stringResource(R.string.tab_personnel_overview), stringResource(R.string.tab_victims), stringResource(R.string.tab_disaster),
        stringResource(R.string.tab_chat), stringResource(R.string.tab_personnel), stringResource(R.string.tab_pws),
        stringResource(R.string.tab_briefing), stringResource(R.string.tab_notification), stringResource(R.string.tab_patient_report),
        stringResource(R.string.tab_decision), stringResource(R.string.tab_timeline), stringResource(R.string.tab_zone_map),
        stringResource(R.string.tab_reports), stringResource(R.string.tab_stats), stringResource(R.string.tab_resources),
        stringResource(R.string.tab_photo_wall), stringResource(R.string.tab_task_assign), stringResource(R.string.tab_broadcast),
        stringResource(R.string.tab_radio), stringResource(R.string.tab_patient_warning),
        stringResource(R.string.tab_ai_chat)
    )
    val tabIcons = listOf(
        Icons.Default.Dashboard, Icons.Default.Campaign, Icons.Default.Groups,
        Icons.Default.People, Icons.Default.PersonSearch, Icons.Default.Domain,
        Icons.Default.Chat, Icons.Default.Badge, Icons.Default.Warning,
        Icons.Default.Summarize, Icons.Default.Notifications, Icons.Default.LocalHospital,
        Icons.Default.Gavel, Icons.Default.Schedule, Icons.Default.Map, Icons.Default.Description,
        Icons.Default.BarChart, Icons.Default.Inventory, Icons.Default.PhotoLibrary,
        Icons.Default.Assignment, Icons.Default.CellTower, Icons.Default.Radio, Icons.Default.MonitorHeart,
        Icons.Default.AutoAwesome
    )

    // SOS 全螢幕覆蓋
    val showSOS by viewModel.showSOSOverlay.collectAsState()
    val sosAlerts by viewModel.sosAlerts.collectAsState()

    // 共用 content
    @Composable
    fun HQTabContent(modifier: Modifier = Modifier) {
        Box(modifier = modifier) {
            when (selectedTab) {
                0 -> OverviewTab(viewModel)
                1 -> CommandTab(viewModel)
                2 -> FieldUnitsTab(viewModel)
                3 -> HQPersonnelOverviewTab(viewModel)
                4 -> HQVictimOverviewTab(viewModel)
                5 -> HQDisasterTab(viewModel)
                6 -> HQChatTab(viewModel)
                7 -> HQPersonnelTab(viewModel)
                8 -> HQPWSTab(viewModel)
                9  -> HQBriefingTab(viewModel)
                10 -> HQNotificationTab(viewModel)
                11 -> PatientFormTab(viewModel)
                12 -> DecisionTab(viewModel)
                13 -> HQTimelineTab(viewModel)
                14 -> HQZoneMapTab(viewModel)
                15 -> HQReportsTab(viewModel)
                16 -> HQStatsDashboardTab(viewModel)
                17 -> HQResourceTab(viewModel)
                18 -> HQPhotoWallTab(viewModel)
                19 -> HQTaskAssignmentTab(viewModel)
                20 -> HQBroadcastTab(viewModel)
                21 -> HQRadioTab(viewModel)
                22 -> HQPatientWarningTab(viewModel)
                23 -> HQAITab(viewModel)
            }
        }
    }

    // 共用 TopBar
    @Composable
    fun HQTopBar() {
        TopAppBar(
            title = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("LinkGuard HQ", color = NV.blue, fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.width(12.dp))
                    val isRunning by viewModel.isHQActive.collectAsState()
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .clip(CircleShape)
                            .background(if (isRunning) NV.green else Color.Gray)
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        stringResource(if (isRunning) R.string.server_running else R.string.server_stopped),
                        color = if (isRunning) NV.green else NV.textSecondary,
                        fontSize = 12.sp
                    )
                }
            },
            actions = {
                val hqRole by viewModel.hqRole.collectAsState()
                if (hqRole == HQViewModel.HQRole.SERVER) {
                    val isRunning by viewModel.server.isRunning.collectAsState()
                    IconButton(onClick = { viewModel.toggleServer() }) {
                        Icon(
                            if (isRunning) Icons.Default.Stop else Icons.Default.PlayArrow,
                            contentDescription = "Toggle Server",
                            tint = if (isRunning) NV.danger else NV.green
                        )
                    }
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = NV.card)
        )
    }

    if (useSidebar) {
        // === 平板佈局: TopBar + 側邊欄 + Content ===
        Box(modifier = Modifier.fillMaxSize()) {
        HQTacticalBackdrop()
        Scaffold(containerColor = Color.Transparent, topBar = { HQTopBar() }) { padding ->
            Row(modifier = Modifier.padding(padding).fillMaxSize()) {
                // 可滾動側邊欄
                Column(
                    modifier = Modifier
                        .width(72.dp)
                        .fillMaxHeight()
                        .background(NV.card)
                        .verticalScroll(rememberScrollState()),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Spacer(modifier = Modifier.height(8.dp))
                    tabs.forEachIndexed { index, title ->
                        val selected = selectedTab == index
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { selectedTab = index }
                                .background(if (selected) NV.blue.copy(alpha = 0.15f) else Color.Transparent)
                                .padding(vertical = 10.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Icon(
                                tabIcons[index], contentDescription = title,
                                tint = if (selected) NV.blue else NV.textSecondary,
                                modifier = Modifier.size(22.dp)
                            )
                            Spacer(modifier = Modifier.height(2.dp))
                            Text(
                                title, fontSize = 9.sp, maxLines = 1,
                                color = if (selected) NV.blue else NV.textSecondary,
                                textAlign = TextAlign.Center
                            )
                        }
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                }
                HQTabContent(modifier = Modifier.weight(1f).fillMaxHeight())
            }
        }
        }
    } else {
        // === 手機佈局: 底部 ScrollableTabRow ===
        Box(modifier = Modifier.fillMaxSize()) {
        HQTacticalBackdrop()
        Scaffold(
            containerColor = Color.Transparent,
            topBar = { HQTopBar() },
            bottomBar = {
                Column(
                    modifier = Modifier
                        .background(NV.card)
                        .navigationBarsPadding()
                ) {
                    ScrollableTabRow(
                        selectedTabIndex = selectedTab,
                        containerColor = NV.card,
                        contentColor = NV.blue,
                        edgePadding = 8.dp
                    ) {
                        tabs.forEachIndexed { index, title ->
                            Tab(
                                selected = selectedTab == index,
                                onClick = { selectedTab = index },
                                text = { Text(title, fontSize = 11.sp) },
                                selectedContentColor = NV.blue,
                                unselectedContentColor = NV.textSecondary
                            )
                        }
                    }
                }
            }
        ) { padding ->
            HQTabContent(modifier = Modifier.padding(padding))
        }
        }
    }

    // === SOS 全螢幕覆蓋 ===
    if (showSOS) {
        val unacknowledged = sosAlerts.filter { !it.isAcknowledged }
        val infiniteTransition = rememberInfiniteTransition(label = "sos")
        val flashAlpha by infiniteTransition.animateFloat(
            initialValue = 0.15f, targetValue = 0.45f,
            animationSpec = infiniteRepeatable(
                animation = tween(500, easing = LinearEasing),
                repeatMode = RepeatMode.Reverse
            ), label = "flash"
        )
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Red.copy(alpha = flashAlpha))
                .clickable { /* consume clicks */ },
            contentAlignment = Alignment.Center
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth(0.8f)
                    .background(NV.card, RoundedCornerShape(16.dp))
                    .border(2.dp, NV.danger, RoundedCornerShape(16.dp))
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(stringResource(R.string.sos_emergency), color = NV.danger, fontSize = 28.sp, fontWeight = FontWeight.Bold)
                Text(stringResource(R.string.sos_unacknowledged, unacknowledged.size), color = NV.white, fontSize = 16.sp)

                LazyColumn(
                    modifier = Modifier.heightIn(max = 300.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(unacknowledged, key = { it.id }) { alert ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(NV.danger.copy(alpha = 0.1f), RoundedCornerShape(8.dp))
                                .padding(12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column {
                                Text(alert.senderName.ifEmpty { alert.deviceID }, color = NV.white, fontWeight = FontWeight.Bold)
                                if (alert.lat != 0.0 || alert.lon != 0.0) {
                                    Text("GPS: ${alert.lat}, ${alert.lon}", color = NV.textSecondary, fontSize = 11.sp)
                                }
                                Text(alert.timeText, color = NV.textSecondary, fontSize = 11.sp)
                            }
                            Button(
                                onClick = { viewModel.acknowledgeSOSAlert(alert.id) },
                                colors = ButtonDefaults.buttonColors(containerColor = NV.warning)
                            ) {
                                Text(stringResource(R.string.btn_acknowledge), fontSize = 12.sp)
                            }
                        }
                    }
                }

                Button(
                    onClick = { viewModel.acknowledgeAllSOS() },
                    colors = ButtonDefaults.buttonColors(containerColor = NV.danger),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.btn_acknowledge_all), fontWeight = FontWeight.Bold, fontSize = 16.sp)
                }
            }
        }
    }
}

// =====================================================
//  總覽頁
// =====================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OverviewTab(viewModel: HQViewModel) {
    val fieldUnits by viewModel.server.fieldUnits.collectAsState()
    val allVictims = viewModel.server.allVictims
    val totalSOS = viewModel.server.totalSOSCount
    val onlineUnits = viewModel.server.onlineFieldUnitCount
    val isBackendConnected by viewModel.isBackendConnected.collectAsState()
    val backendHost by viewModel.backendBridge.backendHost.collectAsState()
    val backendError by viewModel.backendBridge.lastError.collectAsState()
    var backendHostInput by remember { mutableStateOf("") }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // 統計卡片
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                HQStatCard(stringResource(R.string.stat_field_units), "$onlineUnits", NV.blue, Modifier.weight(1f))
                HQStatCard(stringResource(R.string.stat_victims), "${allVictims.size}", NV.green, Modifier.weight(1f))
                HQStatCard(stringResource(R.string.stat_sos), "$totalSOS", if (totalSOS > 0) NV.danger else NV.textSecondary, Modifier.weight(1f))
            }
        }

        // 後台伺服器連線
        item {
            HQCard(borderColor = if (isBackendConnected) NV.green else NV.cardBorder) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
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
                                    .background(if (isBackendConnected) NV.green else Color.Gray)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                stringResource(R.string.backend_ai_server),
                                color = NV.white,
                                fontWeight = FontWeight.Bold,
                                fontSize = 14.sp
                            )
                        }
                        Text(
                            if (isBackendConnected) stringResource(R.string.connected_host, backendHost) else stringResource(R.string.not_connected),
                            color = if (isBackendConnected) NV.green else NV.textSecondary,
                            fontSize = 12.sp
                        )
                    }

                    if (!isBackendConnected) {
                        // NSD auto-discovery
                        val isDiscovering by viewModel.isDiscoveringBackend.collectAsState()
                        val discoveredBackends by viewModel.discoveredBackends.collectAsState()

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            OutlinedTextField(
                                value = backendHostInput,
                                onValueChange = { backendHostInput = it },
                                placeholder = { Text(stringResource(R.string.backend_ip_hint), fontSize = 12.sp) },
                                modifier = Modifier.weight(1f),
                                singleLine = true,
                                colors = OutlinedTextFieldDefaults.colors(
                                    focusedTextColor = NV.white,
                                    unfocusedTextColor = NV.white,
                                    focusedBorderColor = NV.command,
                                    unfocusedBorderColor = NV.cardBorder,
                                    focusedPlaceholderColor = NV.textSecondary,
                                    unfocusedPlaceholderColor = NV.textSecondary
                                ),
                                textStyle = LocalTextStyle.current.copy(fontSize = 13.sp)
                            )
                            Button(
                                onClick = {
                                    val host = backendHostInput.trim()
                                    if (host.isNotEmpty()) viewModel.connectBackend(host)
                                },
                                colors = ButtonDefaults.buttonColors(containerColor = NV.command),
                                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)
                            ) {
                                Text(stringResource(R.string.btn_connect), fontSize = 13.sp)
                            }
                        }

                        // Auto-discovery row
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            TextButton(
                                onClick = {
                                    if (isDiscovering) viewModel.stopBackendDiscovery()
                                    else viewModel.startBackendDiscovery()
                                },
                                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)
                            ) {
                                if (isDiscovering) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.size(12.dp),
                                        color = NV.command,
                                        strokeWidth = 1.5.dp
                                    )
                                    Spacer(modifier = Modifier.width(6.dp))
                                    Text(stringResource(R.string.searching), color = NV.command, fontSize = 11.sp)
                                } else {
                                    Text(stringResource(R.string.auto_search_backend), color = NV.command, fontSize = 11.sp)
                                }
                            }
                        }

                        // Show discovered backends
                        discoveredBackends.forEach { backend ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(NV.surface, RoundedCornerShape(6.dp))
                                    .clickable { viewModel.connectToDiscoveredBackend(backend) }
                                    .padding(horizontal = 12.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Column {
                                    Text(backend.name, color = NV.green, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                    Text("${backend.host}:${backend.port}", color = NV.textSecondary, fontSize = 10.sp)
                                }
                                Text(stringResource(R.string.connect_arrow), color = NV.command, fontSize = 11.sp)
                            }
                        }

                        backendError?.let { err ->
                            Text(stringResource(R.string.error_prefix, err), color = NV.danger, fontSize = 11.sp)
                        }
                    } else {
                        Button(
                            onClick = { viewModel.disconnectBackend() },
                            colors = ButtonDefaults.buttonColors(containerColor = NV.danger),
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)
                        ) {
                            Text(stringResource(R.string.btn_disconnect), fontSize = 13.sp)
                        }
                    }
                }
            }
        }

        // HQ 連線模式（Server / Peer）
        item {
            val hqRole by viewModel.hqRole.collectAsState()
            val isPeerConnected by viewModel.peerClient.isConnected.collectAsState()
            val peerServerName by viewModel.peerClient.connectedServerName.collectAsState()
            val discoveredHQServers by viewModel.peerClient.discoveredServers.collectAsState()

            HQCard(borderColor = when {
                hqRole == HQViewModel.HQRole.PEER && isPeerConnected -> NV.green
                hqRole == HQViewModel.HQRole.PEER -> NV.warning
                else -> NV.cardBorder
            }) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    // Header
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Lan, contentDescription = null, tint = NV.blue, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(stringResource(R.string.hq_connection), color = NV.white, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                        }
                        if (hqRole == HQViewModel.HQRole.PEER && isPeerConnected) {
                            Text(stringResource(R.string.hq_peer_connected, peerServerName), color = NV.green, fontSize = 11.sp)
                        }
                    }

                    // Role toggle
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilterChip(
                            selected = hqRole == HQViewModel.HQRole.SERVER,
                            onClick = { viewModel.switchRole(HQViewModel.HQRole.SERVER) },
                            label = { Text(stringResource(R.string.hq_role_server), fontSize = 12.sp) },
                            leadingIcon = { Icon(Icons.Default.Dns, contentDescription = null, modifier = Modifier.size(16.dp)) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = NV.blue.copy(alpha = 0.25f),
                                selectedLabelColor = NV.blue,
                                selectedLeadingIconColor = NV.blue,
                                labelColor = NV.textSecondary,
                                iconColor = NV.textSecondary
                            )
                        )
                        FilterChip(
                            selected = hqRole == HQViewModel.HQRole.PEER,
                            onClick = { viewModel.switchRole(HQViewModel.HQRole.PEER) },
                            label = { Text(stringResource(R.string.hq_role_peer), fontSize = 12.sp) },
                            leadingIcon = { Icon(Icons.Default.DeviceHub, contentDescription = null, modifier = Modifier.size(16.dp)) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = NV.command.copy(alpha = 0.25f),
                                selectedLabelColor = NV.command,
                                selectedLeadingIconColor = NV.command,
                                labelColor = NV.textSecondary,
                                iconColor = NV.textSecondary
                            )
                        )
                    }

                    // Mode description
                    Text(
                        if (hqRole == HQViewModel.HQRole.SERVER) stringResource(R.string.hq_mode_server_desc)
                        else stringResource(R.string.hq_mode_peer_desc),
                        color = NV.textSecondary, fontSize = 11.sp
                    )

                    // Peer mode: discovery + connect
                    if (hqRole == HQViewModel.HQRole.PEER) {
                        Divider(color = NV.cardBorder.copy(alpha = 0.5f))

                        if (isPeerConnected) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(NV.green))
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text(stringResource(R.string.hq_peer_connected, peerServerName), color = NV.green, fontSize = 13.sp)
                                }
                                Button(
                                    onClick = { viewModel.switchRole(HQViewModel.HQRole.SERVER) },
                                    colors = ButtonDefaults.buttonColors(containerColor = NV.danger),
                                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 6.dp)
                                ) {
                                    Text(stringResource(R.string.hq_disconnect_peer), fontSize = 12.sp)
                                }
                            }
                        } else {
                            // Not connected — show search + discovered list
                            Text(stringResource(R.string.hq_peer_not_connected), color = NV.warning, fontSize = 12.sp)

                            if (discoveredHQServers.isEmpty()) {
                                Text(stringResource(R.string.hq_no_servers_found), color = NV.textSecondary, fontSize = 11.sp,
                                    modifier = Modifier.padding(vertical = 4.dp))
                            }

                            discoveredHQServers.forEach { server ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .background(NV.surface, RoundedCornerShape(6.dp))
                                        .clickable { viewModel.connectToPeer(server) }
                                        .padding(horizontal = 12.dp, vertical = 8.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Column {
                                        Text(server.name, color = NV.green, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                                        Text("${server.host}:${server.port}", color = NV.textSecondary, fontSize = 10.sp)
                                    }
                                    Text(stringResource(R.string.connect_arrow), color = NV.command, fontSize = 11.sp)
                                }
                            }

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(12.dp),
                                    color = NV.command,
                                    strokeWidth = 1.5.dp
                                )
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(stringResource(R.string.hq_searching_servers), color = NV.command, fontSize = 11.sp)
                            }
                        }
                    }
                }
            }
        }

        // 外勤單位快速列表
        item {
            Text(stringResource(R.string.label_field_units), color = NV.textSecondary, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        }

        if (fieldUnits.isEmpty()) {
            item {
                HQCard {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text("--", fontSize = 36.sp, color = NV.textSecondary)
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(stringResource(R.string.waiting_field_units), color = NV.textSecondary)
                        Text(stringResource(R.string.ensure_same_wifi),
                            color = NV.textSecondary, fontSize = 12.sp, textAlign = TextAlign.Center)
                    }
                }
            }
        } else {
            items(fieldUnits, key = { it.id }) { unit ->
                FieldUnitRow(unit)
            }
        }

        // 受困者總覽
        if (allVictims.isNotEmpty()) {
            item {
                Spacer(modifier = Modifier.height(8.dp))
                Text(stringResource(R.string.victim_overview), color = NV.textSecondary, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }
            items(allVictims, key = { it.id }) { victim ->
                VictimSummaryRow(victim)
            }
        }

        // 語言切換
        item {
            val context = LocalContext.current
            val currentLang = remember { mutableStateOf(com.linkguard.hq.util.LocaleHelper.getLanguage(context)) }
            HQCard {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("語言 / Language", color = NV.blue, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        listOf("zh" to "中文", "en" to "EN").forEach { (code, label) ->
                            Button(
                                onClick = {
                                    if (currentLang.value != code) {
                                        com.linkguard.hq.util.LocaleHelper.setLanguage(context, code)
                                        (context as? android.app.Activity)?.recreate()
                                    }
                                },
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = if (currentLang.value == code) NV.blue else NV.card
                                ),
                                modifier = Modifier.weight(1f),
                                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)
                            ) { Text(label, color = NV.white) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun FieldUnitRow(unit: ConnectedFieldUnit) {
    HQCard(borderColor = if (unit.isOnline) NV.green else NV.textSecondary) {
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
                        .background(if (unit.isOnline) NV.green else NV.textSecondary)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Column {
                    Text("${unit.deptCode} - ${unit.deviceID}", color = NV.white, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Text(
                        "${stringResource(R.string.label_victims)}: ${unit.victims.size} · SOS: ${unit.sosCount} · BLE: ${if (unit.bleConnected) "✓" else "✗"}",
                        color = NV.textSecondary, fontSize = 12.sp
                    )
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                Text("BAT: ${unit.battery}%", color = NV.textSecondary, fontSize = 12.sp)
                Text(unit.lastReportText, color = NV.textSecondary, fontSize = 11.sp)
            }
        }
    }
}

@Composable
fun VictimSummaryRow(victim: VictimSummary) {
    HQCard(borderColor = if (victim.isSOS) NV.danger else NV.cardBorder) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier.size(8.dp).clip(CircleShape)
                        .background(if (victim.isOnline) NV.green else NV.textSecondary)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Column {
                    Text(victim.id, color = NV.white, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    Text(
                        "♡ ${if (victim.heartRate > 0) "${victim.heartRate} bpm" else "--"} · ${victim.rssi.toInt()} dBm",
                        color = NV.textSecondary, fontSize = 12.sp
                    )
                }
            }
            Row {
                if (victim.isSOS) {
                    Text("SOS", color = NV.danger, fontWeight = FontWeight.Bold)
                }
                Spacer(modifier = Modifier.width(8.dp))
                Text("BAT: ${victim.battery}%", color = NV.textSecondary, fontSize = 12.sp)
            }
        }
    }
}

// =====================================================
//  命令頁
// =====================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CommandTab(viewModel: HQViewModel) {
    val selectedType by viewModel.selectedType.collectAsState()
    val selectedPriority by viewModel.selectedPriority.collectAsState()
    val title by viewModel.commandTitle.collectAsState()
    val detail by viewModel.commandDetail.collectAsState()
    val sender by viewModel.senderName.collectAsState()
    val targetMode by viewModel.targetMode.collectAsState()
    val selectedTargetIDs by viewModel.selectedTargetDeviceIDs.collectAsState()
    val fieldUnits by viewModel.server.fieldUnits.collectAsState()
    val isRunning by viewModel.isHQActive.collectAsState()
    val onlineCount = viewModel.server.onlineFieldUnitCount
    val timers by viewModel.countdownTimers.collectAsState()

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // 自訂命令
        item {
            Text(stringResource(R.string.send_command), color = NV.command, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.height(4.dp))
            Text(stringResource(R.string.broadcast_to_units, onlineCount), color = NV.textSecondary, fontSize = 12.sp)
        }

        item {
            HQCard {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    // 命令類型
                    Text(stringResource(R.string.label_command_type), color = NV.textSecondary, fontSize = 12.sp)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        CommandType.entries.forEach { type ->
                            FilterChip(
                                selected = selectedType == type,
                                onClick = { viewModel.setSelectedType(type) },
                                label = { Text(type.label, fontSize = 11.sp) },
                                leadingIcon = { Text(type.icon, fontSize = 12.sp) },
                                colors = FilterChipDefaults.filterChipColors(
                                    selectedContainerColor = NV.command.copy(alpha = 0.3f),
                                    selectedLabelColor = NV.white,
                                    labelColor = NV.textSecondary
                                )
                            )
                        }
                    }

                    // 優先級
                    Text(stringResource(R.string.label_priority), color = NV.textSecondary, fontSize = 12.sp)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        CommandPriority.entries.forEach { pri ->
                            FilterChip(
                                selected = selectedPriority == pri,
                                onClick = { viewModel.setSelectedPriority(pri) },
                                label = { Text(pri.label, fontSize = 12.sp) },
                                colors = FilterChipDefaults.filterChipColors(
                                    selectedContainerColor = pri.color.copy(alpha = 0.3f),
                                    selectedLabelColor = NV.white,
                                    labelColor = NV.textSecondary
                                )
                            )
                        }
                    }

                    // 標題
                    OutlinedTextField(
                        value = title,
                        onValueChange = { viewModel.setCommandTitle(it) },
                        label = { Text(stringResource(R.string.label_command_title)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        colors = hqTextFieldColors()
                    )

                    // 說明
                    OutlinedTextField(
                        value = detail,
                        onValueChange = { viewModel.setCommandDetail(it) },
                        label = { Text(stringResource(R.string.label_command_detail)) },
                        maxLines = 3,
                        modifier = Modifier.fillMaxWidth(),
                        colors = hqTextFieldColors()
                    )

                    // 發送者
                    OutlinedTextField(
                        value = sender,
                        onValueChange = { viewModel.setSenderName(it) },
                        label = { Text(stringResource(R.string.label_sender)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        colors = hqTextFieldColors()
                    )

                    // PADOS 目標選擇
                    DeviceTargetSelector(
                        targetMode = targetMode,
                        selectedIDs = selectedTargetIDs,
                        fieldUnits = fieldUnits,
                        onModeChange = { viewModel.setTargetMode(it) },
                        onToggleDevice = { viewModel.toggleTargetDevice(it) },
                        onSelectAll = { viewModel.selectAllDevices() },
                        onDeselectAll = { viewModel.deselectAllDevices() }
                    )

                    // 發送按鈕
                    Button(
                        onClick = { viewModel.sendCustomCommand() },
                        enabled = isRunning && title.isNotBlank() && onlineCount > 0,
                        colors = ButtonDefaults.buttonColors(containerColor = NV.warning),
                        modifier = Modifier.fillMaxWidth().height(48.dp),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Icon(Icons.Default.Send, contentDescription = null)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            if (targetMode == HQViewModel.TargetMode.BROADCAST) stringResource(R.string.btn_broadcast_command)
                            else stringResource(R.string.btn_send_to_devices, selectedTargetIDs.size),
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }

        // 快捷命令
        item {
            Spacer(modifier = Modifier.height(8.dp))
            Text(stringResource(R.string.quick_commands), color = NV.textSecondary, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        }

        items(viewModel.quickCommands, key = { it.title }) { qc ->
            HQCard(borderColor = qc.priority.color) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(enabled = isRunning && onlineCount > 0) {
                            viewModel.sendQuickCommand(qc)
                        },
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(qc.type.icon, fontSize = 16.sp)
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(qc.title, color = NV.white, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                        }
                        Spacer(modifier = Modifier.height(2.dp))
                        Text(qc.detail, color = NV.textSecondary, fontSize = 12.sp)
                    }
                    Text(
                        qc.priority.label,
                        color = NV.textOnColor,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .background(qc.priority.color, RoundedCornerShape(4.dp))
                            .padding(horizontal = 6.dp, vertical = 2.dp)
                    )
                }
            }
        }

        // 倒數計時器
        item {
            Spacer(modifier = Modifier.height(8.dp))
            Text(stringResource(R.string.countdown_timer), color = NV.textSecondary, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        }

        item {
            var timerLabel by remember { mutableStateOf("") }
            var timerMinutes by remember { mutableStateOf("5") }

            HQCard {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        OutlinedTextField(
                            value = timerLabel,
                            onValueChange = { timerLabel = it },
                            label = { Text(stringResource(R.string.label_tag)) },
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                            colors = hqTextFieldColors()
                        )
                        OutlinedTextField(
                            value = timerMinutes,
                            onValueChange = { timerMinutes = it.filter { c -> c.isDigit() } },
                            label = { Text(stringResource(R.string.label_minutes)) },
                            singleLine = true,
                            modifier = Modifier.width(80.dp),
                            colors = hqTextFieldColors()
                        )
                    }
                    val defaultTimerLabel = stringResource(R.string.default_timer)
                    Button(
                        onClick = {
                            val mins = timerMinutes.toIntOrNull() ?: 0
                            if (mins > 0) {
                                viewModel.startCountdown(
                                    label = timerLabel.ifBlank { defaultTimerLabel },
                                    durationSeconds = mins * 60
                                )
                                timerLabel = ""; timerMinutes = "5"
                            }
                        },
                        colors = ButtonDefaults.buttonColors(containerColor = NV.command),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Default.Timer, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(stringResource(R.string.start_timer))
                    }
                }
            }
        }

        // Active timers
        items(timers, key = { it.id }) { timer ->
            val progress = if (timer.durationSeconds > 0) timer.remainingSeconds.toFloat() / timer.durationSeconds else 0f
            val mins = timer.remainingSeconds / 60
            val secs = timer.remainingSeconds % 60
            val timeColor = when {
                timer.remainingSeconds <= 0 -> NV.danger
                timer.remainingSeconds <= 30 -> NV.warning
                else -> NV.green
            }
            HQCard(borderColor = if (timer.isRunning) timeColor.copy(alpha = 0.5f) else NV.cardBorder) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(timer.label, color = NV.white, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                        Text(
                            String.format("%02d:%02d", mins, secs),
                            color = timeColor, fontSize = 24.sp, fontWeight = FontWeight.Bold
                        )
                        LinearProgressIndicator(
                            progress = progress,
                            modifier = Modifier.fillMaxWidth().height(4.dp),
                            color = timeColor,
                            trackColor = NV.cardBorder.copy(alpha = 0.3f)
                        )
                    }
                    Spacer(modifier = Modifier.width(12.dp))
                    if (timer.isRunning) {
                        IconButton(onClick = { viewModel.stopCountdown(timer.id) }) {
                            Icon(Icons.Default.Stop, contentDescription = stringResource(R.string.cd_stop), tint = NV.danger)
                        }
                    }
                    IconButton(onClick = { viewModel.removeCountdown(timer.id) }) {
                        Icon(Icons.Default.Close, contentDescription = stringResource(R.string.cd_remove), tint = NV.textSecondary)
                    }
                }
            }
        }
    }
}

// =====================================================
//  外勤單位詳細頁
// =====================================================

@Composable
fun FieldUnitsTab(viewModel: HQViewModel) {
    val fieldUnits by viewModel.server.fieldUnits.collectAsState()

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            Text(stringResource(R.string.label_field_units), color = NV.blue, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.height(8.dp))
        }

        if (fieldUnits.isEmpty()) {
            item {
                HQCard {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text("--", fontSize = 36.sp, color = NV.textSecondary)
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(stringResource(R.string.waiting_field_units), color = NV.textSecondary)
                    }
                }
            }
        } else {
            items(fieldUnits, key = { it.id }) { unit ->
                FieldUnitDetailCard(unit)
            }
        }
    }
}

@Composable
fun FieldUnitDetailCard(unit: ConnectedFieldUnit) {
    HQCard(borderColor = if (unit.isOnline) NV.green else NV.textSecondary) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            // 標題列
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier.size(10.dp).clip(CircleShape)
                            .background(if (unit.isOnline) NV.green else NV.textSecondary)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("${unit.deptCode} - ${unit.deviceID}", color = NV.white, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                }
                Text(
                    if (unit.isOnline) stringResource(R.string.online) else stringResource(R.string.offline),
                    color = if (unit.isOnline) NV.green else NV.textSecondary,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold
                )
            }

            // 資訊
            HQInfoRow(stringResource(R.string.label_battery), "${unit.battery}%")
            HQInfoRow(stringResource(R.string.label_ble), if (unit.bleConnected) stringResource(R.string.ble_connected) else stringResource(R.string.ble_not_connected))
            HQInfoRow(stringResource(R.string.label_victims), "${unit.victims.size}")
            HQInfoRow("SOS", "${unit.sosCount}")
            HQInfoRow(stringResource(R.string.label_last_report), unit.lastReportText)

            // 受困者列表
            if (unit.victims.isNotEmpty()) {
                Text(stringResource(R.string.detected_victims), color = NV.textSecondary, fontSize = 12.sp)
                unit.victims.forEach { victim ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(start = 8.dp, top = 2.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            "${victim.id} · ♡ ${if (victim.heartRate > 0) "${victim.heartRate}" else "--"} · ${victim.rssi.toInt()} dBm",
                            color = NV.textSecondary, fontSize = 11.sp
                        )
                        if (victim.isSOS) {
                            Text("SOS", color = NV.danger, fontSize = 11.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }
}

// =====================================================
//  歷史頁
// =====================================================

@Composable
fun HistoryTab(viewModel: HQViewModel) {
    val sentCommands by viewModel.sentCommands.collectAsState()

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            Text(stringResource(R.string.command_history), color = NV.command, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Spacer(modifier = Modifier.height(8.dp))
        }

        if (sentCommands.isEmpty()) {
            item {
                HQCard {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(Icons.Default.Edit, contentDescription = null, tint = NV.textSecondary, modifier = Modifier.size(36.dp))
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(stringResource(R.string.no_sent_commands), color = NV.textSecondary)
                    }
                }
            }
        } else {
            items(sentCommands, key = { it.id }) { cmd ->
                HQCard(borderColor = cmd.priority.color) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(cmd.type.icon, fontSize = 14.sp)
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(cmd.title, color = NV.white, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                            }
                            Text(
                                cmd.priority.label,
                                color = NV.textOnColor,
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier
                                    .background(cmd.priority.color, RoundedCornerShape(4.dp))
                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                            )
                        }
                        if (cmd.detail.isNotEmpty()) {
                            Text(cmd.detail, color = NV.textSecondary, fontSize = 12.sp)
                        }
                        Row {
                            Text("🏢 ${cmd.sender}", color = NV.textSecondary, fontSize = 11.sp)
                            Text(" · ", color = NV.textSecondary, fontSize = 11.sp)
                            Text(cmd.timeText, color = NV.textSecondary, fontSize = 11.sp)
                        }
                    }
                }
            }
        }
    }
}

// =====================================================
//  共用元件
// =====================================================

@Composable
fun HQCard(
    borderColor: Color = NV.cardBorder,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(NV.card)
            .border(1.dp, borderColor, RoundedCornerShape(12.dp))
            .padding(16.dp),
        content = content
    )
}

@Composable
fun HQStatCard(label: String, value: String, color: Color, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(NV.card)
            .border(1.dp, NV.cardBorder, RoundedCornerShape(12.dp))
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(label, color = NV.textSecondary, fontSize = 11.sp)
        Spacer(modifier = Modifier.height(4.dp))
        Text(value, color = color, fontSize = 28.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun HQInfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, color = NV.textSecondary, fontSize = 13.sp)
        Text(value, color = NV.white, fontWeight = FontWeight.Bold, fontSize = 13.sp)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun hqTextFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedTextColor = NV.white,
    unfocusedTextColor = NV.white,
    focusedBorderColor = NV.command,
    unfocusedBorderColor = NV.textSecondary,
    focusedLabelColor = NV.command,
    unfocusedLabelColor = NV.textSecondary
)
