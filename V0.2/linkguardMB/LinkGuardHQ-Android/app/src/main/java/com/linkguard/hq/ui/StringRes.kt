package com.linkguard.hq.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.linkguard.hq.R
import com.linkguard.hq.model.*

// =====================================================
//  Enum → stringResource 映射（i18n 用）
//  在 Compose UI 層使用，取代 enum.label
// =====================================================

@Composable
fun CollapseType.localizedLabel(): String = when (this) {
    CollapseType.PARTIAL -> stringResource(R.string.collapse_partial)
    CollapseType.PANCAKE -> stringResource(R.string.collapse_pancake)
    CollapseType.LEAN -> stringResource(R.string.collapse_lean)
    CollapseType.V_SHAPE -> stringResource(R.string.collapse_v_shape)
    CollapseType.NONE -> stringResource(R.string.collapse_none)
    CollapseType.UNKNOWN -> stringResource(R.string.collapse_unknown)
}

@Composable
fun FloorCondition.localizedLabel(): String = when (this) {
    FloorCondition.COLLAPSED -> stringResource(R.string.floor_collapsed)
    FloorCondition.PARTIAL -> stringResource(R.string.floor_partial)
    FloorCondition.ACCESSIBLE -> stringResource(R.string.floor_accessible)
    FloorCondition.CLEARED -> stringResource(R.string.floor_cleared)
    FloorCondition.RESTRICTED -> stringResource(R.string.floor_restricted)
    FloorCondition.UNKNOWN -> stringResource(R.string.floor_unknown)
}

@Composable
fun ZoneStatus.localizedLabel(): String = when (this) {
    ZoneStatus.ACTIVE -> stringResource(R.string.zone_active)
    ZoneStatus.STANDBY -> stringResource(R.string.zone_standby)
    ZoneStatus.CLEARED -> stringResource(R.string.zone_cleared)
    ZoneStatus.DANGEROUS -> stringResource(R.string.zone_dangerous)
    ZoneStatus.RESTRICTED -> stringResource(R.string.zone_restricted)
}

@Composable
fun HazardType.localizedLabel(): String = when (this) {
    HazardType.GAS_LEAK -> stringResource(R.string.hazard_gas_leak)
    HazardType.FIRE -> stringResource(R.string.hazard_fire)
    HazardType.FLOODING -> stringResource(R.string.hazard_flooding)
    HazardType.STRUCTURAL -> stringResource(R.string.hazard_structural)
    HazardType.ELECTRICAL -> stringResource(R.string.hazard_electrical)
    HazardType.CHEMICAL -> stringResource(R.string.hazard_chemical)
}

@Composable
fun PersonnelRole.localizedLabel(): String = when (this) {
    PersonnelRole.SEARCH -> stringResource(R.string.role_search)
    PersonnelRole.RESCUE -> stringResource(R.string.role_rescue)
    PersonnelRole.MEDICAL -> stringResource(R.string.role_medical)
    PersonnelRole.LOGISTICS -> stringResource(R.string.role_logistics)
    PersonnelRole.SAFETY -> stringResource(R.string.role_safety)
    PersonnelRole.COMMANDER -> stringResource(R.string.role_commander)
    PersonnelRole.SUPPORT -> stringResource(R.string.role_support)
}

@Composable
fun PWSAlertType.localizedLabel(): String = when (this) {
    PWSAlertType.EARTHQUAKE -> stringResource(R.string.pws_earthquake)
    PWSAlertType.AFTERSHOCK -> stringResource(R.string.pws_aftershock)
    PWSAlertType.TSUNAMI -> stringResource(R.string.pws_tsunami)
    PWSAlertType.TYPHOON -> stringResource(R.string.pws_typhoon)
    PWSAlertType.FLOOD -> stringResource(R.string.pws_flood)
    PWSAlertType.LANDSLIDE -> stringResource(R.string.pws_landslide)
    PWSAlertType.OTHER -> stringResource(R.string.pws_other)
}

@Composable
fun PWSSeverity.localizedLabel(): String = when (this) {
    PWSSeverity.INFO -> stringResource(R.string.severity_info)
    PWSSeverity.MINOR -> stringResource(R.string.severity_minor)
    PWSSeverity.MODERATE -> stringResource(R.string.severity_moderate)
    PWSSeverity.SEVERE -> stringResource(R.string.severity_severe)
    PWSSeverity.EXTREME -> stringResource(R.string.severity_extreme)
}

@Composable
fun BriefingType.localizedLabel(): String = when (this) {
    BriefingType.INITIAL -> stringResource(R.string.briefing_initial)
    BriefingType.PROGRESS -> stringResource(R.string.briefing_progress)
    BriefingType.SHIFT -> stringResource(R.string.briefing_shift)
    BriefingType.FINAL -> stringResource(R.string.briefing_final)
}

@Composable
fun CommandPriority.localizedLabel(): String = when (this) {
    CommandPriority.ROUTINE -> stringResource(R.string.cmd_priority_routine)
    CommandPriority.URGENT -> stringResource(R.string.cmd_priority_urgent)
    CommandPriority.CRITICAL -> stringResource(R.string.cmd_priority_critical)
}

@Composable
fun CommandType.localizedLabel(): String = when (this) {
    CommandType.SEARCH_AREA -> stringResource(R.string.cmd_search_area)
    CommandType.STANDBY -> stringResource(R.string.cmd_standby)
    CommandType.SUPPORT -> stringResource(R.string.cmd_support)
    CommandType.STATUS_REPORT -> stringResource(R.string.cmd_status_report)
    CommandType.EVACUATION -> stringResource(R.string.cmd_evacuation)
}

@Composable
fun VictimStatus.localizedLabel(): String = when (this) {
    VictimStatus.PENDING -> stringResource(R.string.vstatus_pending)
    VictimStatus.ON_SCENE -> stringResource(R.string.vstatus_on_scene)
    VictimStatus.WAITING_AMBULANCE -> stringResource(R.string.vstatus_waiting_ambulance)
    VictimStatus.EN_ROUTE -> stringResource(R.string.vstatus_en_route)
    VictimStatus.HOSPITALIZED -> stringResource(R.string.vstatus_hospitalized)
    VictimStatus.RESCUED -> stringResource(R.string.vstatus_rescued)
    VictimStatus.DECEASED -> stringResource(R.string.vstatus_deceased)
}

@Composable
fun VictimPriority.localizedLabel(): String = when (this) {
    VictimPriority.UNSET -> stringResource(R.string.vpriority_unset)
    VictimPriority.LOW -> stringResource(R.string.vpriority_low)
    VictimPriority.MEDIUM -> stringResource(R.string.vpriority_medium)
    VictimPriority.HIGH -> stringResource(R.string.vpriority_high)
    VictimPriority.CRITICAL -> stringResource(R.string.vpriority_critical)
}
