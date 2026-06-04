# ICS and INSARAG Mapping

LinkGuard v0.3 同時採用 ICS 管理骨架與 INSARAG 搜救流程。核心判斷是：ICS 定義指揮、權限、作戰週期與資源管理；INSARAG 定義國際 USAR 現場如何分區、評估、標記、派遣、回報與撤收。

## Design Rule

ICS 是管理結構，INSARAG 是搜救方法。兩者必須在資料層合併成同一個 incident state，不應做成兩套互相競爭的頁面。

在產品上，UCC/SCC/TL/TE/EMT/VO 看到的是同一個事件，只是權限、細節與可操作範圍不同：

- UCC 看跨災區、跨 SCC、資源缺口、外部協調、AAR 與資料權威。
- SCC 看現場 incident command、sector/worksite、任務派遣、人員安全與醫療後送狀態。
- TL 管分隊任務、worksite 回報、危險區與進出場。
- TE/VO 回報 GPS、照片、ASR/RCM 線索、任務狀態與 SOS。
- EMT 管傷患、START、生命徵象、後送與醫療交接，向 SCC/UCC 提供 operational summary。

## Structure Mapping

| INSARAG / USAR element | ICS mapping | LinkGuard role | Data owner | Product meaning |
| --- | --- | --- | --- | --- |
| UCC / OSOCC coordination | Unified Command / Command Staff | UCC | UCC | 跨災區協調、外部隊伍與政府/國際協作彙整。 |
| RDC / arriving team reception | Planning + Logistics | UCC / SCC | UCC | 抵達隊伍登錄、能力表、資源需求與部署建議。 |
| SCC / Site Command Center | Incident Command Post | SCC | SCC | 現場戰術指揮、分區、任務、通訊、安全與醫療協調。 |
| Sector / Sub-sector | Operations Branch / Division | SCC / TL | SCC | 把大範圍災區切成可派遣、可回報、可安全管制的作戰區。 |
| Worksite | Tactical assignment location | SCC / TL | SCC | 建築物、倒塌區、搜索點或醫療救援點，所有 ASR/RCM/任務都應能回掛。 |
| Squad / Team | Operations resource | TL / TE / VO | TL | 執行搜索、救援、支援或志工任務的現場單位。 |
| ASR | Planning intelligence + Operations assessment | TL / TE / SCC | SCC | 建築/工作點評估、危險、受困者線索與優先順序。 |
| RCM | Operations marking + shared map product | TL / TE / SCC | SCC | 現場標記、搜索狀態、危險資訊與可視化交接。 |
| EMT / Medical cell | Medical Unit / EMS coordination | EMT / SCC | EMT | 傷患分類、穩定、後送、醫療容量與交接紀錄。 |
| AAR | Planning + Finance/Admin record | UCC / SCC | UCC | 事件復盤、時間線、決策紀錄、資源與成本摘要。 |

## Operational Objects

LinkGuard 的 INSARAG 層不應只是 UI 文字，應落在可同步、可稽核的資料物件上：

| Object | Required fields | Current anchor |
| --- | --- | --- |
| Incident | incident ID, name, started time, command authority, operational period | `IncidentModels.swift`, `OperationSnapshot` |
| Sector / Sub-sector | code, boundary, commander, risk level, active worksites | `MapSystemTypes.swift`, `FieldAppCore` |
| Worksite | code, sector, location, priority, ASR level, status, assigned team | `Worksite`, copied HQ USAR flow |
| ASR assessment | worksite, level, hazards, victims, access route, timestamp, reporter | `ASRLevel`, USAR copied flow |
| RCM marking | type, location, worksite, message, status, timestamp, photo reference | copied HQ USAR flow, map markup model |
| Team capability | team code, country, response type, classification, technical/dog/medical/hazmat capability, support needs | `TeamCapabilityModels.swift` |
| Task | source, target, worksite, objective, priority, due time, acceptance/result | `TaskModels.swift`, FieldUI envelopes |
| Medical evacuation | patient ID, START category, CCP, route, destination, handoff status | `MedicalModels.swift` |
| CEOC/EMIC disaster report | source agency, verification status, affected area, victim estimate, EMIC reference | `DisasterReport`, `disasterReportUpsert` |
| Agency message | from/to agency, notification/request/reply/decision kind, subject, body, verification status | `AgencyMessage`, `agencyMessageUpsert` |
| CEOC mission | mission number, issuing/receiving agency, task description, status, priority, due/completed time | `CEOCMission`, `ceocMissionUpsert` |
| Operational period / IAP summary | objectives, safety, weather, communications, medical plan, resources, EOC activation level | `OperationalPeriod`, `operationalPeriodUpsert` |
| Patient operational summary | patient ID, START category, location, evacuation status, destination hospital | `PatientOperationalSummary`, `patientOperationalSummaryUpsert` |
| Audit event | actor, role, operation, before/after summary, sync receipt | sync envelope / AAR models |

## Authority Boundaries

- UCC may create the incident, set cross-SCC priorities, approve external resource strategy, receive team capability reports, and publish operational-period summaries.
- UCC owns CEOC/EMIC coordination records: agency messages, CEOC missions, EOC activation level, and verified disaster-report exchange.
- SCC owns tactical site command: sector boundaries, worksite assignment, safety control, task dispatch and operational map truth.
- SCC may receive/respond to CEOC missions and agency messages, but does not own the UCC-only EMIC integration or EOC activation management feature.
- TL owns team execution details inside assigned sectors or worksites, but cannot silently overwrite SCC authority data.
- TE/VO can submit observations and SOS, but their submissions should remain pending or attributed until TL/SCC accepts them into the official operational picture.
- EMT owns clinical detail. SCC/UCC should receive evacuation status, capacity and triage summary without taking over full medical record authority.

## Data Flow

1. UCC creates or receives an incident and defines the initial command authority.
2. UCC/SCC register incoming teams through team capability reports, including response type, classification, arrival and support needs.
3. SCC creates sectors, sub-sectors and worksites from reconnaissance or UCC intelligence.
4. TL/TE/VO submit ASR observations, RCM markings, photos, GPS tracks, hazards and task results.
5. SCC promotes accepted field observations into the official map and worksite state.
6. EMT updates patient, START, CCP and evacuation summaries; clinical details stay in the medical boundary.
7. UCC receives cross-site situation, resource gaps, medical load, finance events and AAR timeline.
8. UCC/SCC exchange CEOC/EMIC-compatible agency messages and mission records while keeping field tasks and clinical patient records in their separate authority boundaries.

## UI Implications

- UCC Mac should show ICS lanes plus INSARAG operational products: SCC status, sector/worksite board, team capability intake, medical load and AAR.
- SCC iPad/Mac should use the map as the primary operating picture, with sector/worksite tasking and safety controls adjacent to it.
- Field apps should not expose full command complexity. They should give each role the fastest route to report location, task state, ASR/RCM evidence, SOS and medical handoff.
- Every INSARAG action that changes operational truth should create an audit event and sync envelope.

## Current Implementation Notes

- `MacUCCICSArchitecture` and `MacUCCICSArchitecturePanel` provide the first UCC ICS architecture surface.
- `TeamCapabilityModels.swift` contains the current shared model for USAR team capability intake, including OSOCC/RDC support flags.
- `MapSystemTypes.swift` contains the point/line/polygon, ICS area and map markup primitives needed by ASR/RCM overlays.
- CEOC/EMIC data contracts are now represented in shared core through `AgencyMessage`, `CEOCMission`, `OperationalPeriod` extensions, and `PatientOperationalSummary`; this is data-contract readiness, not a claim that a government EMIC API is connected.
- `HQUSARCommandView.swift` under `V02CopiedHQ` still carries useful ASR/RCM/worksite behavior, but it should be treated as migration reference until the v0.3 UCC/SCC products fully replace copied v0.2 UI.

## Acceptance Checks

- A worksite can be traced from UCC/SCC strategy to sector, assigned team, ASR, RCM, task result, medical event and AAR record.
- A team capability report can affect resource planning without giving the reporting team command authority.
- UCC can read SCC and medical summaries without bypassing SCC tactical ownership or EMT clinical ownership.
- Offline field observations remain attributable and mergeable when connectivity returns.
- Map overlays, task boards and AAR timeline represent the same incident state, not separate copies.
