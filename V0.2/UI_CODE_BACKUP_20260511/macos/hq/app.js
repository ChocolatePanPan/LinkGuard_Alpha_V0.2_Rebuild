/* ============================================================
   LinkGuard Windows HQ — Dashboard Application
   WebSocket 即時通訊 + 完整 HQ 功能
   ============================================================ */

// === State ===
let ws = null;
let reconnectTimer = null;
const S = {
  victims: {},
  teams: {},
  commands: [],
  chats: [],
  patients: [],
  decisions: [],
  briefings: [],
  radioReports: [],
  disasterSite: {},
  personnel: [],
  reinforcements: [],
  quickStatuses: [],
  tasks: [],
  hazards: [],
  pwsAlerts: [],
  sosAlerts: [],
  photos: [],
  notifications: [],
  timeline: [],
  stats: {},
  weather: {},
  loraNodes: {},
  locations: {},
  textBroadcasts: [],
  patientWarnings: [],
  connectedDevices: [],
  deviceCount: 0,
  backendConnected: false,
};

// === Utilities ===
function esc(s) {
  if (s == null) return '';
  const d = document.createElement('div');
  d.textContent = String(s);
  return d.innerHTML;
}
function timeStr(ts) {
  if (!ts) return '';
  const d = new Date(ts);
  return d.toLocaleTimeString('zh-TW', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}
function relTime(ts) {
  if (!ts) return '';
  const diff = (Date.now() - new Date(ts).getTime()) / 1000;
  if (diff < 60) return '剛剛';
  if (diff < 3600) return `${Math.floor(diff / 60)} 分鐘前`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} 小時前`;
  return `${Math.floor(diff / 86400)} 天前`;
}

// === Toast ===
function showToast(msg, type = 'info') {
  const c = document.getElementById('toastContainer');
  const t = document.createElement('div');
  t.className = `toast toast-${type}`;
  t.textContent = msg;
  c.appendChild(t);
  setTimeout(() => { t.style.opacity = '0'; setTimeout(() => t.remove(), 300); }, 3000);
}

// === Navigation ===
let currentPage = 'dashboard';
document.querySelectorAll('.nav-item').forEach(item => {
  item.addEventListener('click', () => {
    const page = item.dataset.page;
    if (!page) return;
    switchPage(page);
  });
});

function switchPage(page) {
  currentPage = page;
  document.querySelectorAll('.nav-item').forEach(n =>
    n.classList.toggle('active', n.dataset.page === page));
  document.querySelectorAll('.page').forEach(p =>
    p.classList.toggle('active', p.id === `page-${page}`));

  const titles = {
    dashboard: ' 儀表板', timeline: ' 事件日誌', victims: ' 受困者總覽',
    teams: ' 隊員總覽', personnel: ' 人員配置', patients: ' 傷患檢傷',
    commands: ' 命令廣播', chat: ' 通訊頻道', broadcast: ' 文字廣播',
    notifications: ' 通知管理', disaster: ' 災害現場', hazards: ' 危害回報',
    reinforcements: ' 增援請求', quickstatus: ' 快速狀態', radio: ' 電台監聽',
    decisions: ' AI 決策', photos: ' 照片牆', briefings: ' 會報系統',
    tasks: ' 任務指派', pws: ' PWS 警報', weather: ' 即時氣象',
    lora: ' LoRa 節點', settings: ' 連線設定',
  };
  document.getElementById('pageTitle').textContent = titles[page] || page;
  refreshPage(page);
}

function refreshPage(page) {
  switch (page) {
    case 'dashboard': renderDashboard(); break;
    case 'timeline': renderTimeline(); break;
    case 'victims': renderVictims(); break;
    case 'teams': renderTeams(); break;
    case 'personnel': renderPersonnel(); break;
    case 'patients': renderPatients(); break;
    case 'commands': renderCommands(); break;
    case 'chat': renderChats(); break;
    case 'broadcast': renderBroadcasts(); break;
    case 'notifications': renderNotifications(); break;
    case 'disaster': renderDisaster(); break;
    case 'hazards': renderHazards(); break;
    case 'reinforcements': renderReinforcements(); break;
    case 'quickstatus': renderQuickStatuses(); break;
    case 'radio': renderRadio(); break;
    case 'decisions': renderDecisions(); break;
    case 'photos': renderPhotos(); break;
    case 'briefings': renderBriefings(); break;
    case 'tasks': renderTasks(); break;
    case 'pws': renderPWS(); break;
    case 'weather': renderWeather(); break;
    case 'lora': renderLoRa(); break;
    case 'settings': renderSettings(); break;
  }
}

// === WebSocket ===
function connectWS() {
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  const url = `${proto}//${location.host}/ws`;
  ws = new WebSocket(url);

  ws.onopen = () => {
    document.getElementById('wsDot').classList.remove('offline');
    document.getElementById('wsStatus').textContent = '已連線';
    showToast('HQ 儀表板已連線', 'success');
    if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
  };

  ws.onclose = () => {
    document.getElementById('wsDot').classList.add('offline');
    document.getElementById('wsStatus').textContent = '已斷線';
    reconnectTimer = setTimeout(connectWS, 3000);
  };

  ws.onerror = () => {
    ws.close();
  };

  ws.onmessage = (ev) => {
    try {
      const msg = JSON.parse(ev.data);
      handleWSMessage(msg);
    } catch (e) {
      console.error('WS parse error:', e);
    }
  };
}

function wsSend(action, data = {}) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ action, data }));
  } else {
    showToast('未連線到 HQ 伺服器', 'error');
  }
}

// === WS Message Handler ===
function handleWSMessage(msg) {
  const { type, data } = msg;

  switch (type) {
    case 'snapshot':
      // Full state sync — replace demo data with real data
      const banner = document.getElementById('demoBanner');
      if (banner) banner.style.display = 'none';
      Object.assign(S, {
        victims: data.victims || {},
        teams: data.teams || {},
        commands: data.commands || [],
        chats: data.chats || [],
        patients: data.patients || [],
        decisions: data.decisions || [],
        briefings: data.briefings || [],
        radioReports: data.radio_reports || [],
        disasterSite: data.disaster_site || {},
        personnel: data.personnel || [],
        reinforcements: data.reinforcements || [],
        quickStatuses: data.quick_statuses || [],
        tasks: data.tasks || [],
        hazards: data.hazards || [],
        pwsAlerts: data.pws_alerts || [],
        sosAlerts: data.sos_alerts || [],
        photos: data.photos || [],
        notifications: data.notifications || [],
        timeline: data.timeline || [],
        stats: data.stats || {},
        weather: data.weather || {},
        loraNodes: data.lora_nodes || {},
        locations: data.locations || {},
        textBroadcasts: data.text_broadcasts || [],
        patientWarnings: data.patient_warnings || [],
        connectedDevices: data.connected_devices || [],
        deviceCount: data.device_count || 0,
        backendConnected: data.backend_connected || false,
      });
      updateStatusBar();
      refreshPage(currentPage);
      updateSOSOverlay();
      break;

    case 'status_report':
      if (data.victims) data.victims.forEach(v => { if (v.id) S.victims[v.id] = v; });
      if (data.teams) data.teams.forEach(t => { if (t.id) S.teams[t.id] = t; });
      if (currentPage === 'victims') renderVictims();
      if (currentPage === 'teams') renderTeams();
      if (currentPage === 'dashboard') renderDashboard();
      updateBadges();
      break;

    case 'chat_message':
      S.chats.push(data);
      if (currentPage === 'chat') renderChats();
      updateBadges();
      break;

    case 'quick_status':
      S.quickStatuses.push(data);
      if (currentPage === 'quickstatus') renderQuickStatuses();
      if (currentPage === 'dashboard') renderDashboard();
      break;

    case 'patient':
      S.patients.push(data);
      if (currentPage === 'patients') renderPatients();
      if (currentPage === 'dashboard') renderDashboard();
      break;

    case 'patient_triage':
      // 更新傷患的 triage 資訊
      S.patients.forEach(p => {
        const pid = p.patientId || p.patient_id || p.id;
        if (pid === data.patient_id) {
          p.triage = data.triage;
          p.triageReason = data.reason;
          p.totalScore = data.totalScore;
        }
      });
      if (currentPage === 'patients') renderPatients();
      if (currentPage === 'dashboard') renderDashboard();
      break;

    case 'sos_alert':
      S.sosAlerts.push(data);
      updateSOSOverlay();
      showToast(` SOS 警報: ${data.senderName || data.deviceID}`, 'error');
      break;

    case 'sos_cancel':
    case 'sos_dismissed':
      S.sosAlerts = S.sosAlerts.filter(s => s.id !== (data.sos_id || data.id));
      updateSOSOverlay();
      break;

    case 'hazard_report':
      S.hazards.push(data);
      if (currentPage === 'hazards') renderHazards();
      showToast(` 危害回報: ${data.hazardType}`, 'warning');
      break;

    case 'reinforcement_request':
      S.reinforcements.push(data);
      if (currentPage === 'reinforcements') renderReinforcements();
      updateBadges();
      showToast(` 增援請求: ${data.fromTeam}`, 'warning');
      break;

    case 'reinforcement_update':
      S.reinforcements.forEach(r => {
        if (r.id === data.id) r.status = data.status;
      });
      if (currentPage === 'reinforcements') renderReinforcements();
      break;

    case 'command':
      S.commands.push(data);
      if (currentPage === 'commands') renderCommands();
      break;

    case 'decision':
      S.decisions.push(data);
      if (currentPage === 'decisions') renderDecisions();
      showToast(' 新的 AI 決策已生成', 'info');
      break;

    case 'decision_error':
      showToast(` AI 決策失敗: ${data.error || '未知錯誤'}`, 'error');
      break;

    case 'text_broadcast':
      S.textBroadcasts.push(data);
      if (currentPage === 'broadcast') renderBroadcasts();
      break;

    case 'radio_control':
      updateRadioStatus(data);
      break;

    case 'radio_transcription':
    case 'report_summary':
      S.radioReports.push(data);
      if (currentPage === 'radio') renderRadio();
      break;

    case 'notification':
      S.notifications.push(data);
      if (currentPage === 'notifications') renderNotifications();
      break;

    case 'task_created':
      S.tasks.push(data);
      if (currentPage === 'tasks') renderTasks();
      break;

    case 'task_update':
      S.tasks.forEach(t => { if (t.id === data.id) t.status = data.taskStatus || data.status; });
      if (currentPage === 'tasks') renderTasks();
      break;

    case 'location':
      S.locations[data.device_id] = data;
      break;

    case 'weather_update':
      S.weather = data;
      if (currentPage === 'weather') renderWeather();
      break;

    case 'node_status':
      (data.nodes || []).forEach(n => { if (n.node_id) S.loraNodes[n.node_id] = n; });
      if (currentPage === 'lora') renderLoRa();
      break;

    case 'pws_alert':
      S.pwsAlerts.push(data);
      if (currentPage === 'pws') renderPWS();
      showToast(` PWS 警報: ${data.title}`, 'warning');
      break;

    case 'patient_warning':
      S.patientWarnings.push(data);
      showToast(` 傷患惡化: ${data.patient_id}`, 'error');
      break;

    case 'personnel':
      S.personnel = data.list || [];
      if (currentPage === 'personnel') renderPersonnel();
      break;

    case 'briefing':
      S.briefings.push(data);
      if (currentPage === 'briefings') renderBriefings();
      break;

    case 'disaster_site':
      S.disasterSite = data;
      if (currentPage === 'disaster') renderDisaster();
      break;

    case 'stats_update':
      S.stats = data;
      if (currentPage === 'dashboard') renderDashboard();
      updateStatusBar();
      break;

    case 'device_connect':
      S.deviceCount++;
      updateStatusBar();
      showToast(` 裝置連線: ${data.address}`, 'success');
      break;

    case 'device_disconnect':
      S.connectedDevices = data.devices ? S.connectedDevices.filter(d => !data.devices.includes(d)) : [];
      S.deviceCount = data.device_count || S.deviceCount - 1;
      updateStatusBar();
      break;

    case 'backend_status':
      S.backendConnected = data.connected;
      updateStatusBar();
      break;

    case 'countdown':
      showToast(`⏱ 倒數計時: ${data.label} (${data.seconds}s)`, 'info');
      break;

    default:
      // Add to timeline if it looks like an event
      if (data && typeof data === 'object') {
        S.timeline.unshift({ event_type: type, title: type, detail: JSON.stringify(data).slice(0, 80), timestamp: msg.timestamp });
        if (currentPage === 'timeline') renderTimeline();
      }
  }
}

// === Status Bar ===
function updateStatusBar() {
  const bDot = document.getElementById('backendDot');
  const bText = document.getElementById('backendStatus');
  bDot.classList.toggle('on', S.backendConnected);
  bDot.classList.toggle('off', !S.backendConnected);
  bText.textContent = `後端: ${S.backendConnected ? '已連線' : '未連線'}`;

  const fDot = document.getElementById('fieldDot');
  const fText = document.getElementById('fieldStatus');
  fDot.classList.toggle('on', S.deviceCount > 0);
  fDot.classList.toggle('off', S.deviceCount === 0);
  fText.textContent = `前線: ${S.deviceCount} 裝置`;

  if (document.getElementById('backendBadge')) {
    const bb = document.getElementById('backendBadge');
    bb.className = `badge ${S.backendConnected ? 'badge-green' : 'badge-red'}`;
    bb.textContent = S.backendConnected ? '已連線' : '未連線';
  }
}

function updateBadges() {
  const sosBadge = document.getElementById('badgeVictimsSOS');
  const sosCount = Object.values(S.victims).filter(v => v.isSOS).length;
  sosBadge.style.display = sosCount > 0 ? 'block' : 'none';
  sosBadge.textContent = sosCount;

  const rBadge = document.getElementById('badgeReinforce');
  const rCount = S.reinforcements.filter(r => r.status === 'pending').length;
  rBadge.style.display = rCount > 0 ? 'block' : 'none';
  rBadge.textContent = rCount;
}

// === SOS Overlay ===
function updateSOSOverlay() {
  const overlay = document.getElementById('sosOverlay');
  const list = document.getElementById('sosList');
  if (S.sosAlerts.length === 0) {
    overlay.style.display = 'none';
    return;
  }
  overlay.style.display = 'flex';
  list.innerHTML = S.sosAlerts.map(s => `
    <div class="sos-item">
      <div>
        <div class="sender"> ${esc(s.senderName || s.deviceID || '')}</div>
        <div class="coords">GPS: ${s.lat || '?'}, ${s.lon || '?'}</div>
        <div style="font-size:11px; color:var(--nv-text2)">${timeStr(s.timestamp)}</div>
      </div>
      <button class="btn btn-danger btn-sm" onclick="dismissSOS('${esc(s.id)}')">解除</button>
    </div>
  `).join('');
}

function dismissSOS(id) {
  wsSend('dismiss_sos', { sos_id: id });
  S.sosAlerts = S.sosAlerts.filter(s => s.id !== id);
  updateSOSOverlay();
}

function dismissAllSOS() {
  S.sosAlerts.forEach(s => wsSend('dismiss_sos', { sos_id: s.id }));
  S.sosAlerts = [];
  updateSOSOverlay();
}

// ============================================================
// RENDERERS
// ============================================================

// --- Dashboard ---
function renderDashboard() {
  const st = S.stats;
  const victims = Object.values(S.victims);
  const vTotal = st.victims_total || victims.length;
  const vOnline = st.victims_online || victims.filter(v => v.isOnline).length;
  const vSOS = st.victims_sos || victims.filter(v => v.isSOS).length;

  document.getElementById('dashStatGrid').innerHTML = `
    <div class="stat-card triage-red"><div class="label">SOS 警報</div><div class="value">${S.sosAlerts.length}</div></div>
    <div class="stat-card"><div class="label">受困者</div><div class="value">${vTotal}</div><div class="sub">線上 ${vOnline} · SOS ${vSOS}</div></div>
    <div class="stat-card"><div class="label">前線裝置</div><div class="value">${S.deviceCount}</div></div>
    <div class="stat-card"><div class="label">傷患</div><div class="value">${st.patients_total || S.patients.length}</div>
      <div class="sub" style="color:var(--nv-danger)">紅${st.patients_immediate || 0} 黃${st.patients_delayed || 0} 綠${st.patients_minor || 0} 黑${st.patients_expectant || 0}</div></div>
    <div class="stat-card"><div class="label">人員配置</div><div class="value">${S.personnel.length}</div></div>
    <div class="stat-card"><div class="label">命令</div><div class="value">${st.commands_count || S.commands.length}</div></div>
    <div class="stat-card"><div class="label">決策</div><div class="value">${st.decisions_count || S.decisions.length}</div></div>
    <div class="stat-card"><div class="label">事件時長</div><div class="value">${st.event_duration_min || 0}<span class="sub"> 分</span></div></div>
  `;

  // Quick statuses
  const qs = S.quickStatuses.slice(-8).reverse();
  document.getElementById('dashQuickStatus').innerHTML = qs.length === 0
    ? '<div class="empty-state"><div class="text">尚無快速狀態</div></div>'
    : qs.map(q => {
      const icons = { area_clear: '', need_support: '', victim_found: '', retreating: '' };
      return `<div class="list-item" style="padding:8px 0">
        <span>${icons[q.type] || ''}</span>
        <span style="font-weight:500">${esc(q.senderName)}</span>
        <span style="color:var(--nv-text2); font-size:12px">${esc(q.zone || '')}</span>
        <span style="margin-left:auto; font-size:11px; color:var(--nv-text3)">${relTime(q.timestamp)}</span>
      </div>`;
    }).join('');

  // Timeline
  const tl = S.timeline.slice(0, 10);
  document.getElementById('dashTimeline').innerHTML = tl.length === 0
    ? '<div class="empty-state"><div class="text">等待事件…</div></div>'
    : tl.map(renderTimelineItem).join('');
}

// --- Timeline ---
const eventIcons = {
  sos: '', command: '', chat: '', decision: '', patient: '',
  status: '', radio: '', broadcast: '', hazard: '', reinforcement: '',
  quick_status: '', task: '', personnel: '', briefing: '', pws: '',
  disaster: '', photo_alert: '', sos_cancel: '', radio_transcription: '',
  patient_warning: '', voice: '',
};

function renderTimelineItem(ev) {
  const icon = eventIcons[ev.event_type] || '';
  return `<div class="timeline-item">
    <span class="time">${timeStr(ev.timestamp)}</span>
    <span class="event-icon">${icon}</span>
    <div class="event-body">
      <div class="event-title">${esc(ev.title)}</div>
      ${ev.detail ? `<div class="event-detail">${esc(ev.detail)}</div>` : ''}
    </div>
  </div>`;
}

function renderTimeline() {
  document.getElementById('timelineList').innerHTML = S.timeline.length === 0
    ? '<div class="empty-state"><div class="icon"></div><div class="text">等待事件…</div></div>'
    : S.timeline.map(renderTimelineItem).join('');
}

// --- Victims ---
function renderVictims() {
  const search = (document.getElementById('victimSearch')?.value || '').toLowerCase();
  let victims = Object.values(S.victims);
  if (search) victims = victims.filter(v =>
    (v.id || '').toLowerCase().includes(search) ||
    (v.name || '').toLowerCase().includes(search));

  const tb = document.getElementById('victimTableBody');
  if (victims.length === 0) {
    tb.innerHTML = '<tr><td colspan="9" style="color:var(--nv-text3); text-align:center">無資料</td></tr>';
    return;
  }
  tb.innerHTML = victims.map(v => {
    const priColors = { unset: 'badge-gray', low: 'badge-green', medium: 'badge-yellow',
                        high: 'badge-orange', critical: 'badge-red' };
    return `<tr>
      <td style="font-family:monospace">${esc(v.id)}</td>
      <td>${v.heartRate || '-'}</td>
      <td>${v.battery || '-'}%</td>
      <td>${v.rssi || '-'}</td>
      <td>${v.isSOS ? '<span class="badge badge-red">SOS</span>' : '-'}</td>
      <td>${v.isOnline ? '<span class="badge badge-green">●</span>' : '<span class="badge badge-gray">○</span>'}</td>
      <td>
        <select class="priority-select" onchange="setVictimPriority('${esc(v.id)}', this.value)">
          <option value="unset" ${(v.priority || 'unset') === 'unset' ? 'selected' : ''}>未設定</option>
          <option value="low" ${v.priority === 'low' ? 'selected' : ''}>低</option>
          <option value="medium" ${v.priority === 'medium' ? 'selected' : ''}>中</option>
          <option value="high" ${v.priority === 'high' ? 'selected' : ''}>高</option>
          <option value="critical" ${v.priority === 'critical' ? 'selected' : ''}>緊急</option>
        </select>
      </td>
      <td style="max-width:120px"><input class="form-input" style="padding:4px 6px; font-size:11px"
           value="${esc(v.note || '')}" onchange="setVictimNote('${esc(v.id)}', this.value)" placeholder="備註"></td>
      <td><span class="badge ${priColors[v.priority] || 'badge-gray'}">${v.priority || 'unset'}</span></td>
    </tr>`;
  }).join('');
}

function setVictimPriority(id, priority) {
  const note = S.victims[id]?.note || '';
  wsSend('set_victim_priority', { victim_id: id, priority, note });
  if (S.victims[id]) S.victims[id].priority = priority;
}
function setVictimNote(id, note) {
  const priority = S.victims[id]?.priority || 'unset';
  wsSend('set_victim_priority', { victim_id: id, priority, note });
  if (S.victims[id]) S.victims[id].note = note;
}

document.getElementById('victimSearch')?.addEventListener('input', () => {
  if (currentPage === 'victims') renderVictims();
});

// --- Teams ---
function renderTeams() {
  const teams = Object.values(S.teams);
  const tb = document.getElementById('teamTableBody');
  if (teams.length === 0) {
    tb.innerHTML = '<tr><td colspan="7" style="color:var(--nv-text3); text-align:center">無資料</td></tr>';
    return;
  }
  tb.innerHTML = teams.map(t => `<tr>
    <td style="font-family:monospace">${esc(t.id)}</td>
    <td>${esc(t.deptCode || '')}</td>
    <td>${t.battery || '-'}%</td>
    <td>${t.rssi || '-'}</td>
    <td>${t.isOnline ? '<span class="badge badge-green">●</span>' : '<span class="badge badge-gray">○</span>'}</td>
    <td>${t.victimCount || 0}</td>
    <td style="font-size:11px; color:var(--nv-text2)">${esc(t.source_device || '')}</td>
  </tr>`).join('');
}

// --- Personnel ---
function renderPersonnel() {
  const el = document.getElementById('personnelList');
  if (S.personnel.length === 0) {
    el.innerHTML = '<div class="empty-state"><div class="icon"></div><div class="text">尚無人員配置</div></div>';
    return;
  }
  const roleLabels = { search: '搜索', rescue: '救援', medical: '醫療', logistics: '後勤',
                       safety: '安全官', commander: '指揮', support: '支援' };
  el.innerHTML = S.personnel.map(p => `
    <div class="personnel-card">
      <div class="avatar">${(p.name || '?')[0]}</div>
      <div class="info">
        <div class="name">${esc(p.name)}</div>
        <div class="role">${esc(roleLabels[p.role] || p.role)} · ${esc(p.assignedZone || '')} ${esc(p.assignedFloor || '')}</div>
      </div>
      <button class="btn btn-ghost btn-sm" onclick="removePersonnel('${esc(p.id)}')">移除</button>
    </div>
  `).join('');
}

function showPersonnelModal() {
  showModal('配置人員', `
    <div class="form-group"><label>姓名</label><input class="form-input" id="pName" placeholder="隊員姓名"></div>
    <div class="form-row">
      <div class="form-group"><label>角色</label>
        <select class="form-select" id="pRole">
          <option value="search">搜索</option><option value="rescue">救援</option>
          <option value="medical">醫療</option><option value="logistics">後勤</option>
          <option value="safety">安全官</option><option value="commander">指揮</option>
          <option value="support">支援</option>
        </select>
      </div>
      <div class="form-group"><label>區域</label><input class="form-input" id="pZone" placeholder="A區"></div>
      <div class="form-group"><label>樓層</label><input class="form-input" id="pFloor" placeholder="1F"></div>
    </div>
  `, () => {
    wsSend('assign_personnel', {
      name: document.getElementById('pName').value,
      role: document.getElementById('pRole').value,
      zone: document.getElementById('pZone').value,
      floor: document.getElementById('pFloor').value,
    });
    closeModal();
    showToast('已配置人員', 'success');
  });
}

function removePersonnel(id) {
  wsSend('remove_personnel', { id });
  S.personnel = S.personnel.filter(p => p.id !== id);
  renderPersonnel();
}

// --- Patients ---
function renderPatients() {
  const el = document.getElementById('patientList');
  if (S.patients.length === 0) {
    el.innerHTML = '<div class="empty-state"><div class="icon"></div><div class="text">尚無傷患資料</div></div>';
    return;
  }
  const triageColors = { immediate: 'badge-red', delayed: 'badge-yellow', minor: 'badge-green', expectant: 'badge-gray' };
  const triageLabels = { immediate: '即刻(紅)', delayed: '延遲(黃)', minor: '輕傷(綠)', expectant: '期望(黑)' };
  el.innerHTML = S.patients.slice().reverse().map(p => `
    <div class="list-item">
      <div>
        <div style="font-weight:500">${esc(p.patientId || p.patient_id || '?')}</div>
        <div style="font-size:12px; color:var(--nv-text2)">
          位置: ${esc(p.location || '')} · 呼吸: ${p.breathingRate || '-'}/min · 微血管: ${p.capillaryRefill || '-'}s
        </div>
        <div style="font-size:11px; color:var(--nv-text3)">${relTime(p.received_at || p.timestamp)}</div>
      </div>
      <span class="badge ${triageColors[p.triage] || 'badge-gray'}">${triageLabels[p.triage] || p.triage || '未分類'}</span>
    </div>
  `).join('');
}

// --- Commands ---
function renderCommands() {
  const el = document.getElementById('commandList');
  if (S.commands.length === 0) {
    el.innerHTML = '<div class="empty-state"><div class="text">尚無命令</div></div>';
    return;
  }
  const priLabels = ['例行', '緊急', '危急'];
  const priColors = ['badge-gray', 'badge-yellow', 'badge-red'];
  el.innerHTML = S.commands.slice().reverse().map(c => `
    <div class="list-item">
      <span style="font-size:14px"></span>
      <div style="flex:1">
        <div style="font-weight:500">${esc(c.title || c.type)}</div>
        <div style="font-size:12px; color:var(--nv-text2)">${esc(c.detail || '')}</div>
      </div>
      <span class="badge ${priColors[c.priority] || 'badge-gray'}">${priLabels[c.priority] || '例行'}</span>
      <span style="font-size:11px; color:var(--nv-text3); white-space:nowrap">${timeStr(c.timestamp)}</span>
    </div>
  `).join('');
}

function sendCommand() {
  const type = document.getElementById('cmdType').value;
  const priority = parseInt(document.getElementById('cmdPriority').value);
  const title = document.getElementById('cmdTitle').value.trim();
  const detail = document.getElementById('cmdDetail').value.trim();
  if (!title) return showToast('請輸入命令標題', 'warning');
  wsSend('send_command', { type, priority, title, detail });
  document.getElementById('cmdTitle').value = '';
  document.getElementById('cmdDetail').value = '';
  showToast('命令已發送', 'success');
}

// --- Chat ---
function renderChats() {
  const el = document.getElementById('chatMessages');
  if (S.chats.length === 0) {
    el.innerHTML = '<div class="empty-state"><div class="text">尚無訊息</div></div>';
    return;
  }
  el.innerHTML = S.chats.map(c => {
    const isHQ = c.senderID === 'HQ';
    return `<div class="chat-bubble ${isHQ ? 'outgoing' : 'incoming'}">
      ${!isHQ ? `<div class="sender">${esc(c.senderName || c.senderID)}</div>` : ''}
      <div>${esc(c.content)}</div>
      <div class="time">${timeStr(c.timestamp)}</div>
    </div>`;
  }).join('');
  el.scrollTop = el.scrollHeight;
}

function sendChat() {
  const input = document.getElementById('chatInput');
  const content = input.value.trim();
  if (!content) return;
  wsSend('send_chat', { content });
  input.value = '';
}

document.getElementById('chatInput')?.addEventListener('keydown', e => {
  if (e.key === 'Enter') sendChat();
});

// --- Broadcast ---
function renderBroadcasts() {
  const el = document.getElementById('broadcastList');
  if (S.textBroadcasts.length === 0) {
    el.innerHTML = '<div class="empty-state"><div class="text">尚無廣播</div></div>';
    return;
  }
  el.innerHTML = S.textBroadcasts.slice().reverse().map(b => `
    <div class="list-item">
      <span></span>
      <div style="flex:1">
        <div style="font-weight:500">${esc(b.sender_name || 'HQ')}</div>
        <div style="font-size:13px">${esc(b.message)}</div>
      </div>
      <span class="badge ${b.priority === 'critical' ? 'badge-red' : b.priority === 'urgent' ? 'badge-yellow' : 'badge-gray'}">${b.priority}</span>
      <span style="font-size:11px; color:var(--nv-text3)">${timeStr(b.timestamp)}</span>
    </div>
  `).join('');
}

function sendBroadcast() {
  const message = document.getElementById('broadcastMsg').value.trim();
  const priority = document.getElementById('broadcastPriority').value;
  if (!message) return showToast('請輸入廣播內容', 'warning');
  wsSend('text_broadcast', { message, priority });
  document.getElementById('broadcastMsg').value = '';
  showToast('廣播已發送', 'success');
}

// --- Notifications ---
function renderNotifications() {
  // Update target device dropdown
  const sel = document.getElementById('notifTarget');
  if (sel) {
    sel.innerHTML = '<option value="">全部裝置</option>' +
      S.connectedDevices.map(d => `<option value="${esc(d)}">${esc(d)}</option>`).join('');
  }
  const el = document.getElementById('notificationList');
  if (S.notifications.length === 0) {
    el.innerHTML = '<div class="empty-state"><div class="text">尚無通知</div></div>';
    return;
  }
  el.innerHTML = S.notifications.slice().reverse().map(n => `
    <div class="list-item">
      <span></span>
      <div style="flex:1">
        <div style="font-weight:500">${esc(n.title)}</div>
        <div style="font-size:12px; color:var(--nv-text2)">${esc(n.content)}</div>
        <div style="font-size:11px; color:var(--nv-text3)">→ ${esc(n.target_device || '全部')}</div>
      </div>
      <span style="font-size:11px; color:var(--nv-text3)">${timeStr(n.timestamp)}</span>
    </div>
  `).join('');
}

function sendNotification() {
  const target = document.getElementById('notifTarget').value;
  const title = document.getElementById('notifTitle').value.trim();
  const content = document.getElementById('notifContent').value.trim();
  if (!title) return showToast('請輸入通知標題', 'warning');
  wsSend('send_notification', { target_device: target, title, content });
  document.getElementById('notifTitle').value = '';
  document.getElementById('notifContent').value = '';
  showToast('通知已發送', 'success');
}

// --- Disaster ---
function renderDisaster() {
  const ds = S.disasterSite;
  if (ds.buildingName) document.getElementById('disasterBuilding').value = ds.buildingName;
  if (ds.address) document.getElementById('disasterAddress').value = ds.address;
  if (ds.floors) document.getElementById('disasterFloors').value = ds.floors;
  if (ds.collapseType) document.getElementById('disasterCollapse').value = ds.collapseType;
  if (ds.rallyPoint) document.getElementById('disasterRally').value = ds.rallyPoint;
  if (ds.notes) document.getElementById('disasterNotes').value = ds.notes;

  const floors = parseInt(document.getElementById('disasterFloors').value) || 5;
  const fg = document.getElementById('floorGrid');
  const floorStatuses = ds.floorStatuses || {};
  const html = [];
  for (let i = floors; i >= 1; i--) {
    const st = floorStatuses[`${i}F`] || 'unknown';
    html.push(`<div class="floor-chip ${st}" onclick="cycleFloorStatus(this, '${i}F')">${i}F - ${st}</div>`);
  }
  fg.innerHTML = html.join('');
}

function cycleFloorStatus(el, floor) {
  const states = ['unknown', 'collapsed', 'partial', 'accessible', 'cleared'];
  const current = el.className.replace('floor-chip ', '').trim();
  const idx = states.indexOf(current);
  const next = states[(idx + 1) % states.length];
  el.className = `floor-chip ${next}`;
  el.textContent = `${floor} - ${next}`;
}

function updateDisasterSite() {
  const floors = parseInt(document.getElementById('disasterFloors').value) || 5;
  const floorStatuses = {};
  document.querySelectorAll('#floorGrid .floor-chip').forEach(chip => {
    const text = chip.textContent;
    const parts = text.split(' - ');
    if (parts.length === 2) floorStatuses[parts[0]] = parts[1];
  });
  const data = {
    buildingName: document.getElementById('disasterBuilding').value,
    address: document.getElementById('disasterAddress').value,
    floors,
    collapseType: document.getElementById('disasterCollapse').value,
    rallyPoint: document.getElementById('disasterRally').value,
    notes: document.getElementById('disasterNotes').value,
    floorStatuses,
  };
  wsSend('update_disaster_site', data);
  showToast('災害資訊已更新', 'success');
}

// --- Hazards ---
function renderHazards() {
  const el = document.getElementById('hazardList');
  if (S.hazards.length === 0) {
    el.innerHTML = '<div class="empty-state"><div class="icon"></div><div class="text">尚無危害回報</div></div>';
    return;
  }
  const sevColors = { low: 'badge-green', medium: 'badge-yellow', high: 'badge-orange', critical: 'badge-red' };
  el.innerHTML = S.hazards.slice().reverse().map(h => `
    <div class="list-item">
      <span></span>
      <div style="flex:1">
        <div style="font-weight:500">${esc(h.hazardType || '')}</div>
        <div style="font-size:12px; color:var(--nv-text2)">${esc(h.description || '')}</div>
        <div style="font-size:11px; color:var(--nv-text3)">${esc(h.reporterName || '')} · ${esc(h.zone || '')}</div>
      </div>
      <span class="badge ${sevColors[h.severity] || 'badge-gray'}">${h.severity || ''}</span>
      <span style="font-size:11px; color:var(--nv-text3)">${timeStr(h.timestamp)}</span>
    </div>
  `).join('');
}

// --- Reinforcements ---
function renderReinforcements() {
  const el = document.getElementById('reinforcementList');
  if (S.reinforcements.length === 0) {
    el.innerHTML = '<div class="empty-state"><div class="icon"></div><div class="text">尚無增援請求</div></div>';
    return;
  }
  const stColors = { pending: 'badge-yellow', joined: 'badge-green', rejected: 'badge-red' };
  const stLabels = { pending: '待回應', joined: '已加入', rejected: '已拒絕' };
  el.innerHTML = S.reinforcements.slice().reverse().map(r => `
    <div class="list-item">
      <span></span>
      <div style="flex:1">
        <div style="font-weight:500">${esc(r.fromTeam)}</div>
        <div style="font-size:13px">${esc(r.message)}</div>
        <div style="font-size:11px; color:var(--nv-text3)">位置: ${esc(r.location)}</div>
      </div>
      <span class="badge ${stColors[r.status] || 'badge-gray'}">${stLabels[r.status] || r.status}</span>
      ${r.status === 'pending' ? `
        <button class="btn btn-green btn-sm" onclick="replyReinforce('${esc(r.id)}','joined')">加入</button>
        <button class="btn btn-danger btn-sm" onclick="replyReinforce('${esc(r.id)}','rejected')">拒絕</button>
      ` : ''}
    </div>
  `).join('');
}

function replyReinforce(id, status) {
  wsSend('reinforce_reply', { id, status });
  showToast(`增援已${status === 'joined' ? '接受' : '拒絕'}`, 'success');
}

// --- Quick Status ---
function renderQuickStatuses() {
  const el = document.getElementById('quickStatusList');
  if (S.quickStatuses.length === 0) {
    el.innerHTML = '<div class="empty-state"><div class="icon"></div><div class="text">尚無快速狀態</div></div>';
    return;
  }
  const icons = { area_clear: '', need_support: '', victim_found: '', retreating: '' };
  const labels = { area_clear: '區域清除', need_support: '需要支援', victim_found: '發現受困者', retreating: '撤退中' };
  el.innerHTML = S.quickStatuses.slice().reverse().map(q => `
    <div class="list-item">
      <span style="font-size:18px">${icons[q.type] || ''}</span>
      <div style="flex:1">
        <div style="font-weight:500">${esc(labels[q.type] || q.type)}</div>
        <div style="font-size:12px; color:var(--nv-text2)">${esc(q.senderName)} · ${esc(q.zone || '')}</div>
        ${q.note ? `<div style="font-size:12px; color:var(--nv-text2)">${esc(q.note)}</div>` : ''}
      </div>
      <span style="font-size:11px; color:var(--nv-text3)">${relTime(q.timestamp)}</span>
    </div>
  `).join('');
}

// --- Radio ---
function renderRadio() {
  const el = document.getElementById('radioReportList');
  if (S.radioReports.length === 0) {
    el.innerHTML = '<div class="empty-state"><div class="icon"></div><div class="text">尚無會報轉錄</div></div>';
    return;
  }
  el.innerHTML = S.radioReports.slice().reverse().map(r => `
    <div class="list-item">
      <span></span>
      <div style="flex:1">
        <div style="font-weight:500">${esc(r.senderName || '')}</div>
        <div style="font-size:13px">${esc(r.transcription || '(無轉錄)')}</div>
        ${r.locationDesc ? `<div style="font-size:11px; color:var(--nv-text3)"> ${esc(r.locationDesc)}</div>` : ''}
      </div>
      <span style="font-size:11px; color:var(--nv-text3)">${timeStr(r.timestamp)}</span>
    </div>
  `).join('');
}

function updateRadioStatus(data) {
  const indicator = document.getElementById('radioIndicator');
  const title = document.getElementById('radioTitle');
  const sub = document.getElementById('radioSub');

  if (data.action === 'start') {
    indicator.classList.add('active');
    title.textContent = `${data.sender_name || '前線'} 正在廣播`;
    sub.textContent = '接收 PTT 音訊中…';
  } else {
    indicator.classList.remove('active');
    title.textContent = '電台待命中';
    sub.textContent = '等待 PTT 廣播…';
  }
}

// --- Decisions ---
function renderDecisions() {
  const el = document.getElementById('decisionList');
  if (S.decisions.length === 0) {
    el.innerHTML = '<div class="empty-state"><div class="icon"></div><div class="text">尚無 AI 決策</div></div>';
    return;
  }
  el.innerHTML = S.decisions.slice().reverse().map(d => `
    <div class="card" style="margin-bottom:12px; border-left:3px solid var(--nv-purple)">
      <div style="font-size:11px; color:var(--nv-text3); margin-bottom:8px">
        ${timeStr(d.timestamp)} · 觸發: ${esc(d.trigger || '')}
      </div>
      <div style="white-space:pre-wrap; font-size:13px; line-height:1.6">${esc(d.decision)}</div>
      ${(d.patients && d.patients.length > 0) ? `
        <div style="margin-top:12px; padding-top:8px; border-top:1px solid var(--nv-border)">
          <div style="font-size:11px; color:var(--nv-text2); margin-bottom:4px">傷患 (${d.patients.length})</div>
          ${d.patients.map(p => `<span class="badge badge-gray" style="margin:2px">${esc(p.patientId || p.patient_id || '?')}</span>`).join('')}
        </div>
      ` : ''}
    </div>
  `).join('');
}

function requestDecision() {
  const context = prompt('決策上下文 (可選):');
  wsSend('request_decision', { context: context || '' });
  showToast('已請求 AI 決策', 'info');
}

// --- Photos ---
function renderPhotos() {
  const el = document.getElementById('photoGrid');
  if (S.photos.length === 0) {
    el.innerHTML = '<div class="empty-state" style="grid-column:1/-1"><div class="icon"></div><div class="text">尚無照片</div></div>';
    return;
  }
  el.innerHTML = S.photos.map(p => {
    const thumbUrl = p.thumbnail_url || p.thumb_url || '';
    const fullUrl = p.full_url || p.url || thumbUrl;
    return `<div class="photo-card" onclick="openPhoto('${esc(fullUrl)}')">
      ${thumbUrl ? `<img src="${esc(thumbUrl)}" alt="" loading="lazy" onerror="this.style.display='none'">` :
        `<div style="aspect-ratio:1; background:var(--nv-surface); display:flex; align-items:center; justify-content:center; font-size:32px"></div>`}
      <div class="info">
        <div>${esc(p.caption || p.photo_id || '')}</div>
        <div>${esc(p.sender_name || '')} · ${esc(p.location_desc || '')}</div>
      </div>
    </div>`;
  }).join('');
}

function openPhoto(url) {
  if (!url) return;
  document.getElementById('photoModalImg').src = url;
  document.getElementById('photoModal').style.display = 'flex';
}
function closePhotoModal() {
  document.getElementById('photoModal').style.display = 'none';
  document.getElementById('photoModalImg').src = '';
}

// --- Briefings ---
function renderBriefings() {
  const el = document.getElementById('briefingList');
  if (S.briefings.length === 0) {
    el.innerHTML = '<div class="empty-state"><div class="icon"></div><div class="text">尚無會報</div></div>';
    return;
  }
  const typeLabels = { initial: '初期', progress: '進度', shift: '交接', final: '結案' };
  el.innerHTML = S.briefings.slice().reverse().map(b => `
    <div class="card" style="margin-bottom:12px">
      <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px">
        <div style="font-weight:500; font-size:14px">${esc(b.title)}</div>
        <span class="badge badge-blue">${typeLabels[b.type] || b.type}</span>
      </div>
      <div style="font-size:11px; color:var(--nv-text3); margin-bottom:8px">${esc(b.author)} · ${timeStr(b.timestamp)}</div>
      ${(b.sections || []).map(s => `
        <div style="margin-bottom:8px">
          <div style="font-size:12px; font-weight:500; color:var(--nv-text2)">${esc(s.heading || s.title || '')}</div>
          <div style="font-size:13px; white-space:pre-wrap">${esc(s.content || s.body || '')}</div>
        </div>
      `).join('')}
    </div>
  `).join('');
}

function showBriefingModal() {
  showModal('新增會報', `
    <div class="form-group"><label>標題</label><input class="form-input" id="brTitle" placeholder="會報標題"></div>
    <div class="form-group"><label>類型</label>
      <select class="form-select" id="brType">
        <option value="initial">初期會報</option><option value="progress">進度會報</option>
        <option value="shift">交接會報</option><option value="final">結案會報</option>
      </select>
    </div>
    <div class="form-group"><label>作者</label><input class="form-input" id="brAuthor" value="HQ"></div>
    <div class="form-group"><label>章節 1 標題</label><input class="form-input" id="brSec1Title" placeholder="現場狀況"></div>
    <div class="form-group"><label>章節 1 內容</label><textarea class="form-textarea" id="brSec1Content" rows="3"></textarea></div>
    <div class="form-group"><label>章節 2 標題 (選填)</label><input class="form-input" id="brSec2Title" placeholder="行動計畫"></div>
    <div class="form-group"><label>章節 2 內容</label><textarea class="form-textarea" id="brSec2Content" rows="3"></textarea></div>
  `, () => {
    const sections = [];
    const s1t = document.getElementById('brSec1Title').value;
    const s1c = document.getElementById('brSec1Content').value;
    if (s1t || s1c) sections.push({ heading: s1t, content: s1c });
    const s2t = document.getElementById('brSec2Title').value;
    const s2c = document.getElementById('brSec2Content').value;
    if (s2t || s2c) sections.push({ heading: s2t, content: s2c });
    wsSend('create_briefing', {
      title: document.getElementById('brTitle').value,
      type: document.getElementById('brType').value,
      author: document.getElementById('brAuthor').value,
      sections,
    });
    closeModal();
    showToast('會報已建立', 'success');
  });
}

// --- Tasks ---
function renderTasks() {
  const tb = document.getElementById('taskTableBody');
  if (S.tasks.length === 0) {
    tb.innerHTML = '<tr><td colspan="5" style="color:var(--nv-text3); text-align:center">尚無任務</td></tr>';
    return;
  }
  const priLabels = ['例行', '緊急', '危急'];
  const priColors = ['badge-gray', 'badge-yellow', 'badge-red'];
  const stColors = { pending: 'badge-gray', accepted: 'badge-blue', in_progress: 'badge-yellow', completed: 'badge-green', cancelled: 'badge-red' };
  const stLabels = { pending: '待接受', accepted: '已接受', in_progress: '執行中', completed: '已完成', cancelled: '已取消' };
  tb.innerHTML = S.tasks.map(t => `<tr>
    <td style="font-weight:500">${esc(t.title)}</td>
    <td>${esc(t.assigneeName || t.assigneeID || '')}</td>
    <td>${esc(t.zone || '')}</td>
    <td><span class="badge ${priColors[t.priority] || 'badge-gray'}">${priLabels[t.priority] || '例行'}</span></td>
    <td><span class="badge ${stColors[t.status] || 'badge-gray'}">${stLabels[t.status] || t.status}</span></td>
  </tr>`).join('');
}

function showTaskModal() {
  showModal('新增任務', `
    <div class="form-group"><label>標題</label><input class="form-input" id="taskTitle" placeholder="任務標題"></div>
    <div class="form-group"><label>詳情</label><textarea class="form-textarea" id="taskDetail" rows="2" placeholder="任務詳情"></textarea></div>
    <div class="form-row">
      <div class="form-group"><label>指派對象 ID</label><input class="form-input" id="taskAssignee" placeholder="裝置 ID"></div>
      <div class="form-group"><label>姓名</label><input class="form-input" id="taskAssigneeName" placeholder="隊員姓名"></div>
    </div>
    <div class="form-row">
      <div class="form-group"><label>區域</label><input class="form-input" id="taskZone" placeholder="A區"></div>
      <div class="form-group"><label>優先級</label>
        <select class="form-select" id="taskPriority">
          <option value="0">例行</option><option value="1">緊急</option><option value="2">危急</option>
        </select>
      </div>
    </div>
  `, () => {
    wsSend('create_task', {
      title: document.getElementById('taskTitle').value,
      detail: document.getElementById('taskDetail').value,
      assigneeID: document.getElementById('taskAssignee').value,
      assigneeName: document.getElementById('taskAssigneeName').value,
      zone: document.getElementById('taskZone').value,
      priority: parseInt(document.getElementById('taskPriority').value),
    });
    closeModal();
    showToast('任務已建立', 'success');
  });
}

// --- PWS ---
function renderPWS() {
  const el = document.getElementById('pwsList');
  if (S.pwsAlerts.length === 0) {
    el.innerHTML = '<div class="empty-state"><div class="icon"></div><div class="text">目前無 PWS 警報</div></div>';
    return;
  }
  el.innerHTML = S.pwsAlerts.slice().reverse().map(a => {
    const sevClass = ['severe', 'extreme'].includes(a.severity) ? a.severity : '';
    const typeLabels = { earthquake: '地震', aftershock: '餘震', tsunami: '海嘯', typhoon: '颱風',
                         flood: '洪水', landslide: '土石流', other: '其他' };
    return `<div class="pws-card ${sevClass}">
      <div class="pws-title">${esc(typeLabels[a.alertType] || a.alertType)} — ${esc(a.title)}</div>
      <div class="pws-content">${esc(a.content)}</div>
      <div class="pws-meta">嚴重度: ${esc(a.severity)} · 發布: ${esc(a.publisher)} · ${timeStr(a.publishTime ? new Date(a.publishTime * 1000).toISOString() : '')}</div>
    </div>`;
  }).join('');
}

function showPWSModal() {
  showModal('發布 PWS 警報', `
    <div class="form-row">
      <div class="form-group"><label>類型</label>
        <select class="form-select" id="pwsType">
          <option value="earthquake">地震</option><option value="aftershock">餘震</option>
          <option value="tsunami">海嘯</option><option value="typhoon">颱風</option>
          <option value="flood">洪水</option><option value="landslide">土石流</option>
          <option value="other">其他</option>
        </select>
      </div>
      <div class="form-group"><label>嚴重度</label>
        <select class="form-select" id="pwsSev">
          <option value="info">資訊</option><option value="minor">輕微</option>
          <option value="moderate">中等</option><option value="severe">嚴重</option>
          <option value="extreme">極端</option>
        </select>
      </div>
    </div>
    <div class="form-group"><label>標題</label><input class="form-input" id="pwsTitle" placeholder="警報標題"></div>
    <div class="form-group"><label>內容</label><textarea class="form-textarea" id="pwsContent" rows="3" placeholder="警報內容"></textarea></div>
  `, () => {
    wsSend('pws_alert', {
      alertType: document.getElementById('pwsType').value,
      severity: document.getElementById('pwsSev').value,
      title: document.getElementById('pwsTitle').value,
      content: document.getElementById('pwsContent').value,
    });
    closeModal();
    showToast('PWS 警報已發布', 'success');
  });
}

// --- Weather ---
function renderWeather() {
  const el = document.getElementById('weatherGrid');
  const w = S.weather;
  if (!w || Object.keys(w).length === 0) {
    el.innerHTML = '<div class="empty-state" style="grid-column:1/-1"><div class="text">等待氣象資料…</div></div>';
    return;
  }
  el.innerHTML = `
    <div class="weather-item"><div class="w-value">${w.temperature != null ? w.temperature + '°C' : '--'}</div><div class="w-label"> 溫度</div></div>
    <div class="weather-item"><div class="w-value">${w.humidity != null ? w.humidity + '%' : '--'}</div><div class="w-label"> 濕度</div></div>
    <div class="weather-item"><div class="w-value">${w.wind_speed != null ? w.wind_speed + ' m/s' : '--'}</div><div class="w-label"> 風速</div></div>
    <div class="weather-item"><div class="w-value">${w.rainfall != null ? w.rainfall + ' mm' : '--'}</div><div class="w-label"> 降雨</div></div>
    <div class="weather-item" style="grid-column:1/-1">
      <div class="w-label" style="font-size:12px">觀測時間: ${esc(w.obs_time || w.obsTime || '--')}</div>
    </div>
  `;
}

// --- LoRa ---
function renderLoRa() {
  const nodes = Object.values(S.loraNodes);
  const tb = document.getElementById('loraTableBody');
  if (nodes.length === 0) {
    tb.innerHTML = '<tr><td colspan="6" style="color:var(--nv-text3); text-align:center">等待節點資料…</td></tr>';
    return;
  }
  tb.innerHTML = nodes.map(n => `<tr>
    <td style="font-family:monospace">${esc(n.node_id)}</td>
    <td>${n.rssi || '-'} dBm</td>
    <td>${n.snr != null ? n.snr : '-'} dB</td>
    <td>${n.battery || '-'}%</td>
    <td>${n.pdr != null ? (n.pdr * 100).toFixed(0) + '%' : '-'}</td>
    <td style="font-size:11px; color:var(--nv-text3)">${esc(n.last_seen || '')}</td>
  </tr>`).join('');
}

// --- Settings ---
function renderSettings() {
  const el = document.getElementById('connectedDevicesList');
  if (S.connectedDevices.length === 0) {
    el.innerHTML = '<div style="color:var(--nv-text3); font-size:13px">無裝置連線</div>';
    return;
  }
  el.innerHTML = S.connectedDevices.map(d => `
    <div class="list-item" style="border:1px solid var(--nv-border); border-radius:6px; margin-bottom:4px">
      <span style="font-family:monospace">${esc(d)}</span>
      <span class="badge badge-green" style="margin-left:auto">線上</span>
    </div>
  `).join('');
}

// ============================================================
// MODAL HELPERS
// ============================================================
function showModal(title, bodyHTML, onConfirm) {
  const container = document.getElementById('modalContainer');
  container.innerHTML = `
    <div class="modal-overlay" onclick="if(event.target===this)closeModal()">
      <div class="modal">
        <h3>${esc(title)}</h3>
        <div id="modalBody">${bodyHTML}</div>
        <div class="modal-actions">
          <button class="btn btn-ghost" onclick="closeModal()">取消</button>
          <button class="btn" id="modalConfirm">確認</button>
        </div>
      </div>
    </div>
  `;
  document.getElementById('modalConfirm').onclick = onConfirm;
}

function closeModal() {
  document.getElementById('modalContainer').innerHTML = '';
}

// ============================================================
// DEMO / SEED DATA
// ============================================================
function seedDemoData() {
  const now = Date.now();
  const ts = (minAgo) => new Date(now - minAgo * 60000).toISOString();

  // --- Victims ---
  S.victims = {
    'V-001': { id: 'V-001', name: '陳志明', heartRate: 92, battery: 78, rssi: -62, isSOS: true, isOnline: true, priority: 'critical', note: '3F 東側受困，腿部壓傷' },
    'V-002': { id: 'V-002', name: '林美玲', heartRate: 68, battery: 45, rssi: -78, isSOS: false, isOnline: true, priority: 'high', note: '4F 辦公區' },
    'V-003': { id: 'V-003', name: '王大偉', heartRate: 110, battery: 12, rssi: -85, isSOS: true, isOnline: true, priority: 'critical', note: '電池即將耗盡' },
    'V-004': { id: 'V-004', name: '張小芳', heartRate: 74, battery: 91, rssi: -55, isSOS: false, isOnline: true, priority: 'medium', note: '2F 樓梯間' },
    'V-005': { id: 'V-005', name: '李建國', heartRate: 0, battery: 33, rssi: -90, isSOS: false, isOnline: false, priority: 'unset', note: '最後訊號 5F' },
    'V-006': { id: 'V-006', name: '吳佩珍', heartRate: 82, battery: 67, rssi: -70, isSOS: false, isOnline: true, priority: 'low', note: '已移至安全區' },
    'V-007': { id: 'V-007', name: '黃世傑', heartRate: 105, battery: 28, rssi: -82, isSOS: false, isOnline: true, priority: 'high', note: '3F 西側' },
    'V-008': { id: 'V-008', name: '劉雅琪', heartRate: 76, battery: 56, rssi: -65, isSOS: false, isOnline: true, priority: 'medium', note: '' },
    'V-009': { id: 'V-009', name: '趙國華', heartRate: 88, battery: 41, rssi: -75, isSOS: false, isOnline: true, priority: 'low', note: '1F 大廳' },
    'V-010': { id: 'V-010', name: '周雅文', heartRate: 0, battery: 0, rssi: -99, isSOS: false, isOnline: false, priority: 'unset', note: '信號中斷 40 分鐘' },
  };

  // --- Teams ---
  S.teams = {
    'T-Alpha': { id: 'T-Alpha', deptCode: '新北特搜一', battery: 85, rssi: -58, isOnline: true, victimCount: 3, source_device: 'LG-F301' },
    'T-Bravo': { id: 'T-Bravo', deptCode: '新北特搜二', battery: 72, rssi: -66, isOnline: true, victimCount: 2, source_device: 'LG-F302' },
    'T-Charlie': { id: 'T-Charlie', deptCode: '台北醫療組', battery: 91, rssi: -52, isOnline: true, victimCount: 0, source_device: 'LG-F303' },
    'T-Delta': { id: 'T-Delta', deptCode: '國軍支援組', battery: 64, rssi: -74, isOnline: true, victimCount: 4, source_device: 'LG-F304' },
    'T-Echo': { id: 'T-Echo', deptCode: '義消中隊', battery: 38, rssi: -88, isOnline: false, victimCount: 1, source_device: 'LG-F305' },
  };

  // --- Personnel ---
  S.personnel = [
    { id: 'P01', name: '陳隊長', role: 'commander', assignedZone: '全區', assignedFloor: 'HQ' },
    { id: 'P02', name: '林志豪', role: 'search', assignedZone: 'A區', assignedFloor: '3F' },
    { id: 'P03', name: '王心怡', role: 'medical', assignedZone: 'B區', assignedFloor: '1F' },
    { id: 'P04', name: '黃建民', role: 'rescue', assignedZone: 'A區', assignedFloor: '4F' },
    { id: 'P05', name: '張偉潔', role: 'safety', assignedZone: '全區', assignedFloor: '' },
    { id: 'P06', name: '劉家銘', role: 'logistics', assignedZone: '集結點', assignedFloor: '' },
    { id: 'P07', name: '許文馨', role: 'search', assignedZone: 'B區', assignedFloor: '5F' },
    { id: 'P08', name: '蔡佳穎', role: 'rescue', assignedZone: 'A區', assignedFloor: '3F' },
  ];

  // --- Patients ---
  S.patients = [
    { patientId: 'PA-001', location: '3F-A區 柱旁', breathingRate: 28, capillaryRefill: 4.2, triage: 'immediate', timestamp: ts(25) },
    { patientId: 'PA-002', location: '4F-B區 辦公室', breathingRate: 18, capillaryRefill: 2.1, triage: 'delayed', timestamp: ts(20) },
    { patientId: 'PA-003', location: '2F 樓梯轉角', breathingRate: 20, capillaryRefill: 1.5, triage: 'minor', timestamp: ts(18) },
    { patientId: 'PA-004', location: '1F 大廳入口', breathingRate: 16, capillaryRefill: 1.8, triage: 'minor', timestamp: ts(15) },
    { patientId: 'PA-005', location: '3F-A區 窗邊', breathingRate: 32, capillaryRefill: 5.0, triage: 'immediate', timestamp: ts(12) },
    { patientId: 'PA-006', location: '5F 電梯旁', breathingRate: 0, capillaryRefill: 0, triage: 'expectant', timestamp: ts(10) },
    { patientId: 'PA-007', location: '3F-B區 走廊', breathingRate: 22, capillaryRefill: 3.0, triage: 'delayed', timestamp: ts(8) },
    { patientId: 'PA-008', location: '1F 門口', breathingRate: 19, capillaryRefill: 1.2, triage: 'minor', timestamp: ts(5) },
  ];

  // --- Commands ---
  S.commands = [
    { type: 'search', priority: 2, title: '緊急搜索 3F 東側區域', detail: '偵測到生命徵象，疑似有受困者。Alpha 隊立即前往 3F 東側執行搜索，攜帶破壞工具與生命探測器。', timestamp: ts(45) },
    { type: 'evacuation', priority: 2, title: '撤離 5F 全部人員', detail: '結構工程評估 5F 有二次坍塌風險，所有人員立即撤離至安全區。', timestamp: ts(35) },
    { type: 'standby', priority: 1, title: 'Bravo 隊進入待命', detail: '等候 Alpha 隊初步評估回報，準備接替進入 4F 搜索。', timestamp: ts(28) },
    { type: 'rescue', priority: 2, title: '啟動 3F 救援行動', detail: '確認 V-001 受困位置。救援組攜帶液壓頂升器前往。醫療組 A 待命。', timestamp: ts(22) },
    { type: 'medical', priority: 1, title: '醫療站擴編', detail: 'Charlie 隊在 1F 大廳設置第二醫療站，處理輕傷患者轉運。', timestamp: ts(15) },
    { type: 'search', priority: 0, title: 'B 區 4F 常規搜索', detail: 'Delta 隊於 B 區 4F 執行系統性搜索，每間辦公室逐一確認。', timestamp: ts(10) },
  ];

  // --- Chat ---
  S.chats = [
    { senderID: 'LG-F301', senderName: 'Alpha 隊長', content: 'HQ 收到，Alpha 隊已抵達 3F 東側入口。結構尚穩。', timestamp: ts(42) },
    { senderID: 'HQ', senderName: 'HQ', content: '收到 Alpha。注意 3F 東側牆面有裂縫，謹慎前進。回報受困者位置。', timestamp: ts(41) },
    { senderID: 'LG-F301', senderName: 'Alpha 隊長', content: '發現一名男性受困者（V-001），右腿被混凝土壓住，意識清楚。需要液壓頂升器。', timestamp: ts(38) },
    { senderID: 'LG-F303', senderName: 'Charlie 醫療組', content: '醫療組已就位 1F，可隨時接收傷患。目前已處理 3 名輕傷。', timestamp: ts(35) },
    { senderID: 'HQ', senderName: 'HQ', content: '收到。救援組攜帶液壓設備前往 3F，ETA 5 分鐘。Charlie 準備紅色傷患接收。', timestamp: ts(34) },
    { senderID: 'LG-F304', senderName: 'Delta 隊長', content: 'Delta 隊 4F B區搜索中，已確認 3 間辦公室清空。持續前進。', timestamp: ts(30) },
    { senderID: 'LG-F302', senderName: 'Bravo 隊長', content: 'Bravo 待命中。聽到 5F 有結構聲響，建議暫停該樓層作業。', timestamp: ts(27) },
    { senderID: 'HQ', senderName: 'HQ', content: ' 全頻道通知：5F 發布撤離令。所有 5F 人員立即後撤至 3F 以下。', timestamp: ts(26) },
    { senderID: 'LG-F301', senderName: 'Alpha 隊長', content: '液壓頂升作業開始。V-001 生命徵象穩定，心率 92。預估 15 分鐘完成救出。', timestamp: ts(20) },
    { senderID: 'LG-F304', senderName: 'Delta 隊長', content: '4F B區發現 2 名受困者（V-007、V-008），可自行移動，引導下樓中。', timestamp: ts(15) },
    { senderID: 'HQ', senderName: 'HQ', content: '各隊注意：氣象預報 1 小時後有大雨，加速作業。後勤組準備防水帆布。', timestamp: ts(10) },
    { senderID: 'LG-F301', senderName: 'Alpha 隊長', content: 'V-001 救出成功！正在搬運下樓，需要擔架。', timestamp: ts(5) },
    { senderID: 'HQ', senderName: 'HQ', content: '太好了！擔架已在 1F 等候。Charlie 準備接收。全體辛苦了。', timestamp: ts(4) },
  ];

  // --- Text Broadcasts ---
  S.textBroadcasts = [
    { sender_name: 'HQ', message: '【緊急通知】5F 結構不穩，全員撤離 5F。立即往 3F 以下移動。安全第一。', priority: 'critical', timestamp: ts(26) },
    { sender_name: 'HQ', message: '【進度更新】3F 東側救援作業進行中，預計 15 分鐘完成。各隊維持目前位置繼續作業。', priority: 'normal', timestamp: ts(19) },
    { sender_name: 'HQ', message: '【氣象警報】中央氣象署發布大雨特報，預計 1 小時內抵達。各隊做好防雨準備，加速搜索。', priority: 'urgent', timestamp: ts(10) },
    { sender_name: 'HQ', message: '【好消息】V-001 已成功救出並轉送醫療站。目前累計救出 5 人、搜索完成率 62%。', priority: 'normal', timestamp: ts(4) },
  ];

  // --- Notifications ---
  S.notifications = [
    { title: 'SOS 警報觸發', content: 'V-001 於 3F 東側觸發 SOS，心率 92 BPM。', target_device: '', timestamp: ts(44) },
    { title: '電池低電量警告', content: 'V-003 電池剩餘 12%，信號可能中斷。', target_device: 'LG-F301', timestamp: ts(30) },
    { title: '5F 撤離命令', content: '5F 結構不穩定，所有人員立即撤離。', target_device: '', timestamp: ts(26) },
    { title: 'V-001 救出通知', content: '受困者 V-001 陳志明已成功救出。', target_device: '', timestamp: ts(5) },
    { title: '氣象特報', content: '大雨特報生效中，預計 1 小時內影響現場。', target_device: '', timestamp: ts(10) },
  ];

  // --- Disaster Site ---
  S.disasterSite = {
    buildingName: '信義商業大樓',
    address: '台北市信義區信義路五段 88 號',
    floors: 7,
    collapseType: 'partial',
    rallyPoint: '大樓南側停車場（距出口 50m）',
    notes: '6.2 級地震後部分樓層坍塌。3F-5F 東側嚴重受損。1F-2F 結構尚穩。地下室待評估。消防梯可用至 4F。電梯全部停用。已斷電斷氣。',
    floorStatuses: {
      '7F': 'collapsed',
      '6F': 'partial',
      '5F': 'partial',
      '4F': 'accessible',
      '3F': 'accessible',
      '2F': 'cleared',
      '1F': 'cleared',
    },
  };

  // --- Hazards ---
  S.hazards = [
    { hazardType: '結構裂縫', description: '3F 東側承重牆出現 15cm 寬裂縫，有持續擴大跡象。建議支撐後再進入。', reporterName: 'Alpha 隊長', zone: 'A區 3F', severity: 'high', timestamp: ts(40) },
    { hazardType: '瓦斯洩漏', description: '2F 廚房區域偵測到微量瓦斯，已關閉總閥。建議保持通風。', reporterName: 'Bravo 隊長', zone: 'B區 2F', severity: 'critical', timestamp: ts(32) },
    { hazardType: '碎玻璃', description: '4F 窗戶全部破裂，地面大量碎玻璃。進入需穿戴護具。', reporterName: 'Delta 隊長', zone: 'B區 4F', severity: 'medium', timestamp: ts(28) },
    { hazardType: '積水', description: '1F 大廳消防管線破裂，地面積水約 10cm。已設置排水。', reporterName: '劉家銘（後勤）', zone: '1F 大廳', severity: 'low', timestamp: ts(20) },
    { hazardType: '二次坍塌風險', description: '5F 天花板鋼筋暴露，混凝土持續剝落。禁止進入。', reporterName: '安全官', zone: '5F 全區', severity: 'critical', timestamp: ts(25) },
  ];

  // --- Reinforcements ---
  S.reinforcements = [
    { id: 'RF-001', fromTeam: 'Alpha 隊', message: '3F 救援需要額外 2 名救援手及液壓切割器。', location: '3F 東側', status: 'joined', timestamp: ts(36) },
    { id: 'RF-002', fromTeam: 'Delta 隊', message: '4F 發現多名受困者，需要醫療人員就近支援。', location: '4F B區', status: 'pending', timestamp: ts(14) },
    { id: 'RF-003', fromTeam: 'Bravo 隊', message: '請求結構技師評估 5F 安全性後再開放搜索。', location: '5F', status: 'pending', timestamp: ts(26) },
  ];

  // --- Quick Statuses ---
  S.quickStatuses = [
    { type: 'victim_found', senderName: 'Alpha 隊長', zone: 'A區 3F', note: '男性，意識清楚，腿部受困', timestamp: ts(38) },
    { type: 'need_support', senderName: 'Alpha 隊長', zone: 'A區 3F', note: '需液壓頂升器', timestamp: ts(37) },
    { type: 'retreating', senderName: '許文馨', zone: '5F B區', note: '結構聲響，主動撤退', timestamp: ts(26) },
    { type: 'area_clear', senderName: 'Bravo 隊長', zone: 'A區 2F', note: '2F A區搜索完畢，無受困者', timestamp: ts(22) },
    { type: 'victim_found', senderName: 'Delta 隊長', zone: 'B區 4F', note: '2 名受困者，可自行移動', timestamp: ts(15) },
    { type: 'area_clear', senderName: 'Delta 隊長', zone: 'B區 4F-1', note: '4F 第一區清除完畢', timestamp: ts(8) },
    { type: 'need_support', senderName: 'Delta 隊長', zone: 'B區 4F', note: '需要擔架協助轉運傷患', timestamp: ts(6) },
    { type: 'area_clear', senderName: 'Alpha 隊長', zone: 'A區 3F 東側', note: 'V-001 救出完成', timestamp: ts(5) },
  ];

  // --- Radio Reports ---
  S.radioReports = [
    { senderName: 'Alpha 隊長', transcription: '呼叫 HQ，Alpha 已到達 3F 東側入口。目視結構裂縫但可通行。準備進入搜索。Over。', locationDesc: '3F 東側入口', timestamp: ts(42) },
    { senderName: 'Bravo 隊長', transcription: '呼叫 HQ，5F 傳出明顯結構聲響，像是鋼筋斷裂。建議暫停 5F 作業。Over。', locationDesc: '3F 樓梯間', timestamp: ts(27) },
    { senderName: 'Charlie 醫療組', transcription: '醫療站回報：目前 3 名綠色傷患已處理完畢，1 名黃色正在治療中。紅色通道待命。Over。', locationDesc: '1F 醫療站', timestamp: ts(18) },
    { senderName: 'Alpha 隊長', transcription: '液壓頂升完成！受困者已移出。正在固定傷處。需要擔架上來 3F。Over。', locationDesc: '3F 東側', timestamp: ts(6) },
    { senderName: 'Delta 隊長', transcription: '4F B區掃蕩完成 60%。兩名移動傷患已引導至 2F 樓梯間等候。繼續搜索。Over。', locationDesc: '4F B區', timestamp: ts(3) },
  ];

  // --- Decisions ---
  S.decisions = [
    {
      timestamp: ts(33),
      trigger: '多名傷患同時回報',
      decision: '【AI 分類建議】\n\n根據目前 8 名傷患的檢傷資料分析：\n\n1. PA-001 (3F-A區)：呼吸 28/min，微血管 4.2s → 即刻(紅)\n   → 建議：優先轉送，需固定腿部後擔架搬運\n\n2. PA-005 (3F-A區)：呼吸 32/min，微血管 5.0s → 即刻(紅)\n   → 建議：呼吸偏快須監控，可能內出血\n\n3. PA-002、PA-007：延遲(黃)，生命徵象穩定\n   → 建議：原地等待，每 15 分鐘重新評估\n\n4. PA-003、PA-004、PA-008：輕傷(綠)\n   → 建議：移至 1F 醫療站自行處置\n\n5. PA-006 (5F)：無呼吸 → 期望(黑)\n   → 建議：標記位置，現階段不投入資源\n\n 優先序：PA-001 > PA-005 > PA-007 > PA-002',
      patients: [
        { patientId: 'PA-001' }, { patientId: 'PA-005' }, { patientId: 'PA-002' },
        { patientId: 'PA-007' }, { patientId: 'PA-003' }, { patientId: 'PA-004' },
        { patientId: 'PA-008' }, { patientId: 'PA-006' },
      ],
    },
    {
      timestamp: ts(12),
      trigger: '5F 結構風險 + 氣象變化',
      decision: '【AI 戰術建議】\n\n綜合評估當前狀況：\n\n 3F 救援進度良好（V-001 即將救出）\n 5F 結構持續惡化，禁入區確認\n 大雨預計 1 小時內抵達\n\n建議行動：\n1. 維持 3F 救援作業至完成\n2. 加速 4F 搜索，目標 45 分鐘內完成\n3. 1F-2F 已清除區域設置防水措施\n4. 預備撤退路線：消防梯 → 1F 南側出口 → 集結點\n5. 後勤組準備雨具與照明設備\n\n風險評級：中高\n建議全面撤退時機：降雨量達 30mm/hr 或結構再次發出異響',
      patients: [],
    },
  ];

  // --- Photos ---
  S.photos = [
    { photo_id: 'PH-001', thumbnail_url: '', full_url: '', caption: '3F 東側坍塌現場全景', sender_name: 'Alpha 隊長', location_desc: '3F A區' },
    { photo_id: 'PH-002', thumbnail_url: '', full_url: '', caption: '受困者 V-001 位置標記', sender_name: 'Alpha 隊長', location_desc: '3F 東側柱旁' },
    { photo_id: 'PH-003', thumbnail_url: '', full_url: '', caption: '5F 天花板鋼筋暴露', sender_name: 'Bravo 隊長', location_desc: '5F 走廊' },
    { photo_id: 'PH-004', thumbnail_url: '', full_url: '', caption: '1F 醫療站設置完成', sender_name: 'Charlie 醫療組', location_desc: '1F 大廳' },
    { photo_id: 'PH-005', thumbnail_url: '', full_url: '', caption: '4F B區窗戶碎裂', sender_name: 'Delta 隊長', location_desc: '4F B區' },
    { photo_id: 'PH-006', thumbnail_url: '', full_url: '', caption: 'V-001 救出瞬間', sender_name: 'Alpha 隊長', location_desc: '3F 東側' },
  ];

  // --- Briefings ---
  S.briefings = [
    {
      title: '初期災害評估會報',
      type: 'initial',
      author: '陳隊長',
      timestamp: ts(50),
      sections: [
        { heading: '災害概述', content: '2025/01/15 14:32 發生芮氏 6.2 地震，震央位於台北市東方 15km。信義商業大樓（7F RC 結構，1985 年建造）東側 5F-7F 部分坍塌。初步評估 10-15 人受困。' },
        { heading: '已投入資源', content: '- 新北特搜一隊（Alpha）12 人\n- 新北特搜二隊（Bravo）10 人\n- 台北醫療組（Charlie）6 人\n- 國軍支援組（Delta）15 人\n- 義消中隊（Echo）8 人\n- 生命探測器 x2、液壓破壞組 x2、搜救犬 x1' },
        { heading: '行動計畫', content: '1. 1F-2F 快速搜索（已完成）\n2. 3F 東側重點救援（進行中）\n3. 4F 系統搜索（進行中）\n4. 5F 待結構評估後決定\n5. 6F-7F 暫列禁入區' },
      ],
    },
    {
      title: '第一次進度會報',
      type: 'progress',
      author: '陳隊長',
      timestamp: ts(15),
      sections: [
        { heading: '搜索進度', content: '1F：清除 \n2F：清除 （發現 2 名輕傷自行撤離）\n3F：A區救援中，V-001 即將救出\n4F：B區搜索中，60% 完成，發現 2 名受困者\n5F：禁入（結構不穩）\n6F-7F：禁入（坍塌）' },
        { heading: '傷患統計', content: '紅色（即刻）：2 人\n黃色（延遲）：2 人\n綠色（輕傷）：3 人\n黑色（期望）：1 人\n\n共計 8 名傷患，1F 醫療站運行正常。' },
        { heading: '待處理事項', content: '- V-001 救出後立即送醫\n- Delta 隊 4F 搜索完成後評估是否進入 6F\n- 氣象觀測：1 小時後大雨，需加速作業\n- 後勤確認是否需要夜間照明設備' },
      ],
    },
  ];

  // --- Tasks ---
  S.tasks = [
    { id: 'TK-001', title: '3F 東側救援 V-001', assigneeName: '蔡佳穎', assigneeID: 'LG-F301-3', zone: 'A區 3F', priority: 2, status: 'completed' },
    { id: 'TK-002', title: '4F B區系統搜索', assigneeName: 'Delta 隊長', assigneeID: 'LG-F304', zone: 'B區 4F', priority: 1, status: 'in_progress' },
    { id: 'TK-003', title: '5F 結構安全評估', assigneeName: '張偉潔（安全官）', assigneeID: 'LG-F302-2', zone: '5F', priority: 2, status: 'pending' },
    { id: 'TK-004', title: '1F 醫療站擴編', assigneeName: '王心怡', assigneeID: 'LG-F303-1', zone: '1F', priority: 1, status: 'completed' },
    { id: 'TK-005', title: '集結點防水帆布架設', assigneeName: '劉家銘', assigneeID: 'LG-F306', zone: '集結點', priority: 0, status: 'in_progress' },
    { id: 'TK-006', title: '搜救犬 3F 西側搜索', assigneeName: '林志豪', assigneeID: 'LG-F301-2', zone: 'A區 3F', priority: 1, status: 'accepted' },
  ];

  // --- PWS Alerts ---
  S.pwsAlerts = [
    { alertType: 'earthquake', severity: 'severe', title: '台北市信義區有感地震', content: '地震規模：芮氏 6.2\n震源深度：12km\n震央位置：台北市東方 15km（北緯 25.03，東經 121.58）\n各地最大震度：台北市 5弱、新北市 4、基隆市 4、桃園市 3\n\n請注意餘震及建築物安全。', publisher: '中央氣象署', publishTime: Math.floor((now - 55 * 60000) / 1000) },
    { alertType: 'aftershock', severity: 'moderate', title: '餘震警報 — 芮氏 4.1', content: '芮氏 4.1 餘震，震央同一位置。作業人員注意結構反應。', publisher: '中央氣象署', publishTime: Math.floor((now - 30 * 60000) / 1000) },
    { alertType: 'flood', severity: 'minor', title: '大雨特報', content: '台北市、新北市發布大雨特報。預計未來 3 小時累積雨量達 80mm。低窪地區注意淹水。', publisher: '中央氣象署', publishTime: Math.floor((now - 10 * 60000) / 1000) },
  ];

  // --- Weather ---
  S.weather = {
    temperature: 23.5,
    humidity: 82,
    wind_speed: 4.2,
    rainfall: 0.0,
    obs_time: new Date(now - 5 * 60000).toLocaleString('zh-TW'),
  };

  // --- LoRa Nodes ---
  S.loraNodes = {
    'LR-GW01': { node_id: 'LR-GW01', rssi: -45, snr: 12.5, battery: 100, pdr: 0.98, last_seen: ts(1) },
    'LR-N01': { node_id: 'LR-N01', rssi: -72, snr: 8.2, battery: 76, pdr: 0.92, last_seen: ts(2) },
    'LR-N02': { node_id: 'LR-N02', rssi: -85, snr: 5.1, battery: 54, pdr: 0.85, last_seen: ts(3) },
    'LR-N03': { node_id: 'LR-N03', rssi: -68, snr: 9.7, battery: 88, pdr: 0.95, last_seen: ts(1) },
    'LR-N04': { node_id: 'LR-N04', rssi: -91, snr: 2.3, battery: 31, pdr: 0.72, last_seen: ts(8) },
  };

  // --- Timeline ---
  S.timeline = [
    { event_type: 'disaster', title: '地震發生', detail: '芮氏 6.2，信義商業大樓部分坍塌', timestamp: ts(55) },
    { event_type: 'command', title: '救災指揮中心成立', detail: '陳隊長擔任現場指揮官', timestamp: ts(52) },
    { event_type: 'briefing', title: '初期評估會報', detail: '投入 5 支隊伍、51 人', timestamp: ts(50) },
    { event_type: 'command', title: '緊急搜索 3F 東側', detail: 'Alpha 隊前往偵測到生命徵象的區域', timestamp: ts(45) },
    { event_type: 'sos', title: 'SOS 警報：V-001', detail: '3F 東側受困者觸發 SOS', timestamp: ts(44) },
    { event_type: 'chat', title: 'Alpha 隊抵達 3F', detail: '結構尚穩，開始搜索', timestamp: ts(42) },
    { event_type: 'status', title: '發現受困者 V-001', detail: '男性，右腿被混凝土壓住', timestamp: ts(38) },
    { event_type: 'reinforcement', title: '增援請求：液壓設備', detail: 'Alpha 隊請求液壓頂升器', timestamp: ts(36) },
    { event_type: 'command', title: '撤離 5F 全部人員', detail: '結構不穩風險', timestamp: ts(35) },
    { event_type: 'hazard', title: '危害回報：瓦斯洩漏', detail: '2F 廚房偵測到微量瓦斯', timestamp: ts(32) },
    { event_type: 'patient', title: '傷患 PA-001 檢傷', detail: '即刻(紅) — 3F A區', timestamp: ts(25) },
    { event_type: 'decision', title: 'AI 分類建議', detail: '8 名傷患優先序排列', timestamp: ts(33) },
    { event_type: 'command', title: '啟動 3F 救援行動', detail: '液壓頂升作業開始', timestamp: ts(22) },
    { event_type: 'radio', title: 'Charlie 醫療站回報', detail: '3 名綠色處理完畢', timestamp: ts(18) },
    { event_type: 'quick_status', title: 'Delta 發現受困者', detail: 'B區 4F，2 名可移動', timestamp: ts(15) },
    { event_type: 'briefing', title: '第一次進度會報', detail: '搜索完成率 62%', timestamp: ts(15) },
    { event_type: 'pws', title: '大雨特報', detail: '台北市大雨特報生效', timestamp: ts(10) },
    { event_type: 'decision', title: 'AI 戰術建議', detail: '綜合 5F 風險 + 氣象', timestamp: ts(12) },
    { event_type: 'radio', title: 'Alpha 救出 V-001', detail: '液壓頂升完成', timestamp: ts(6) },
    { event_type: 'status', title: 'V-001 救出成功', detail: '搬運下樓中', timestamp: ts(5) },
  ];

  // --- Connected Devices ---
  S.connectedDevices = ['LG-F301', 'LG-F302', 'LG-F303', 'LG-F304'];
  S.deviceCount = 4;
  S.backendConnected = true;

  // --- Stats ---
  S.stats = {
    victims_total: 10,
    victims_online: 8,
    victims_sos: 2,
    patients_total: 8,
    patients_immediate: 2,
    patients_delayed: 2,
    patients_minor: 3,
    patients_expectant: 1,
    commands_count: 6,
    decisions_count: 2,
    event_duration_min: 55,
  };

  // --- SOS Alerts (active) ---
  S.sosAlerts = [
    { id: 'SOS-001', senderName: '陳志明', deviceID: 'V-001', lat: 25.0330, lon: 121.5654, timestamp: ts(44) },
    { id: 'SOS-003', senderName: '王大偉', deviceID: 'V-003', lat: 25.0331, lon: 121.5655, timestamp: ts(30) },
  ];
}

// ============================================================
// INIT
// ============================================================
seedDemoData();
updateStatusBar();
updateBadges();
switchPage('dashboard');
connectWS();




