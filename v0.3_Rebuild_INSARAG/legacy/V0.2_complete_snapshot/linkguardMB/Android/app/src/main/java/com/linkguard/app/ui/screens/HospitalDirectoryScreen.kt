package com.linkguard.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.linkguard.app.data.HospitalData
import com.linkguard.app.model.Hospital
import com.linkguard.app.model.HospitalLevel
import com.linkguard.app.ui.theme.NV
import com.linkguard.app.ui.theme.NVShape
import com.linkguard.app.viewmodel.LinkGuardViewModel

// =====================================================
//  醫院目錄畫面 — 對齊 iOS FieldHospitalView
//  靜態資料，依地區分組，支援搜尋，GPS 自動定位城市
// =====================================================

@Composable
fun HospitalDirectoryScreen(viewModel: LinkGuardViewModel) {
    var searchQuery by remember { mutableStateOf("") }
    var expandedRegion by remember { mutableStateOf<String?>(null) }
    val nearbyCity by viewModel.gpsCity.collectAsState()

    // 自動展開最近城市所在地區
    LaunchedEffect(nearbyCity) {
        if (nearbyCity != null) {
            expandedRegion = HospitalData.regionForCity(nearbyCity!!)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(NV.bg)
    ) {
        // 標題列 + GPS 城市提示
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(NV.surface)
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.LocalHospital, contentDescription = null, tint = NV.danger, modifier = Modifier.size(22.dp))
                Spacer(Modifier.width(8.dp))
                Text("醫療資源目錄", color = NV.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.weight(1f))
                if (nearbyCity != null) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(NV.green.copy(alpha = 0.12f))
                            .padding(horizontal = 8.dp, vertical = 3.dp)
                    ) {
                        Icon(Icons.Default.LocationOn, contentDescription = null, tint = NV.green, modifier = Modifier.size(12.dp))
                        Spacer(Modifier.width(3.dp))
                        Text(nearbyCity!!, color = NV.green, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                    }
                }
            }

            // 搜尋欄
            OutlinedTextField(
                value = searchQuery,
                onValueChange = { searchQuery = it },
                placeholder = { Text("搜尋醫院名稱或地址…", fontSize = 13.sp, color = NV.textSecondary) },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null, tint = NV.textSecondary, modifier = Modifier.size(18.dp)) },
                trailingIcon = {
                    if (searchQuery.isNotEmpty()) {
                        IconButton(onClick = { searchQuery = "" }) {
                            Icon(Icons.Default.Clear, contentDescription = null, tint = NV.textSecondary, modifier = Modifier.size(16.dp))
                        }
                    }
                },
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = NV.green,
                    unfocusedBorderColor = NV.cardBorder,
                    focusedTextColor = NV.textPrimary,
                    unfocusedTextColor = NV.textPrimary,
                    cursorColor = NV.green
                ),
                modifier = Modifier.fillMaxWidth(),
                shape = NVShape.card
            )
        }

        Divider(color = NV.divider, thickness = 0.5.dp)

        // 清單
        if (searchQuery.isNotBlank()) {
            val results = HospitalData.search(searchQuery)
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (results.isEmpty()) {
                    item {
                        Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                            Text("找不到符合條件的醫院", color = NV.textSecondary, fontSize = 14.sp)
                        }
                    }
                } else {
                    items(results, key = { it.id }) { hospital ->
                        HospitalCard(hospital)
                    }
                }
                item { Spacer(Modifier.height(80.dp)) }
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                HospitalData.regions.forEach { region ->
                    val regionHospitals = HospitalData.byRegion(region)
                    val isExpanded = expandedRegion == region

                    item(key = "region_$region") {
                        RegionHeader(
                            region = region,
                            count = regionHospitals.size,
                            isExpanded = isExpanded,
                            isHighlighted = nearbyCity != null && HospitalData.regionForCity(nearbyCity!!) == region,
                            onClick = { expandedRegion = if (isExpanded) null else region }
                        )
                    }

                    if (isExpanded) {
                        items(regionHospitals, key = { it.id }) { hospital ->
                            HospitalCard(hospital)
                        }
                    }
                }
                item { Spacer(Modifier.height(80.dp)) }
            }
        }
    }
}

@Composable
private fun RegionHeader(
    region: String,
    count: Int,
    isExpanded: Boolean,
    isHighlighted: Boolean,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        color = if (isHighlighted) NV.green.copy(alpha = 0.08f) else NV.surface,
        shape = NVShape.card,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                Icons.Default.Map,
                contentDescription = null,
                tint = if (isHighlighted) NV.green else NV.textSecondary,
                modifier = Modifier.size(18.dp)
            )
            Spacer(Modifier.width(10.dp))
            Text(
                region,
                color = if (isHighlighted) NV.green else NV.textPrimary,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f)
            )
            Text(
                "$count 處",
                color = NV.textSecondary,
                fontSize = 12.sp
            )
            Spacer(Modifier.width(8.dp))
            Icon(
                if (isExpanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                contentDescription = null,
                tint = NV.textSecondary,
                modifier = Modifier.size(18.dp)
            )
        }
    }
}

@Composable
private fun HospitalCard(hospital: Hospital) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(NVShape.card)
            .background(NV.card)
            .border(1.dp, NV.cardBorder, NVShape.card)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                hospital.name,
                color = NV.textPrimary,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f)
            )
            LevelBadge(hospital.level, hospital.levelColor)
        }

        Row(
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Default.Place, contentDescription = null, tint = NV.textSecondary, modifier = Modifier.size(12.dp))
            Spacer(Modifier.width(4.dp))
            Text(hospital.address, color = NV.textSecondary, fontSize = 11.sp)
        }

        if (hospital.phone.isNotEmpty()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Phone, contentDescription = null, tint = NV.info, modifier = Modifier.size(12.dp))
                Spacer(Modifier.width(4.dp))
                Text(hospital.phone, color = NV.info, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
            }
        }

        if (hospital.totalBeds > 0 || hospital.icuBeds > 0 || hospital.orRooms > 0) {
            Divider(color = NV.divider, thickness = 0.5.dp)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                if (hospital.totalBeds > 0) CapacityChip(label = "床位", value = hospital.totalBeds.toString(), color = NV.team)
                if (hospital.icuBeds > 0)   CapacityChip(label = "加護", value = hospital.icuBeds.toString(), color = NV.danger)
                if (hospital.orRooms > 0)   CapacityChip(label = "手術", value = hospital.orRooms.toString(), color = NV.warning)
            }
        }
    }
}

@Composable
private fun LevelBadge(level: HospitalLevel, color: Color) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(4.dp))
            .background(color.copy(alpha = 0.15f))
            .border(0.5.dp, color.copy(alpha = 0.4f), RoundedCornerShape(4.dp))
            .padding(horizontal = 6.dp, vertical = 2.dp)
    ) {
        Text(level.label, color = color, fontSize = 10.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun CapacityChip(label: String, value: String, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = NV.textSecondary, fontSize = 10.sp)
        Spacer(Modifier.width(3.dp))
        Text(value, color = color, fontSize = 11.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
    }
}
