"""
replay/server.py — LinkGuard 離線回放伺服器
從 USB 或本地 linkguard.db 讀取歷史資料，提供 Web 回放介面
依賴: flask, sqlite3（內建）
"""

import mimetypes
import os
import re
import sqlite3
import webbrowser
from datetime import datetime, timezone, timedelta

from flask import Flask, jsonify, request, Response, make_response

app = Flask(__name__)

TZ_TW = timezone(timedelta(hours=8))
DB_PATH = None
AUDIO_DIR = None


# ============================================================
# DB 偵測 & 連線
# ============================================================

def find_db() -> str | None:
    """自動偵測 linkguard.db 位置"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(script_dir, "linkguard.db"),
        os.path.join(script_dir, "data", "linkguard.db"),
        os.path.join(script_dir, "..", "data", "linkguard.db"),
        os.path.join(script_dir, "..", "linkguard.db"),
    ]
    for p in candidates:
        p = os.path.normpath(p)
        if os.path.exists(p):
            return p
    return None


def find_audio_dir() -> str | None:
    """自動偵測音訊目錄"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(script_dir, "reports", "audio"),
        os.path.join(script_dir, "..", "reports", "audio"),
        os.path.join(script_dir, "..", "data", "..", "reports", "audio"),
    ]
    for p in candidates:
        p = os.path.normpath(p)
        if os.path.isdir(p):
            return p
    return None


def get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def rows_to_list(rows) -> list:
    return [dict(r) for r in rows]


# ============================================================
# API: /api/timeline
# ============================================================

@app.route("/api/timeline")
def api_timeline():
    conn = get_conn()
    events = []

    # decisions
    for r in conn.execute("SELECT id, timestamp, decision_text, trigger_type FROM decisions ORDER BY timestamp"):
        events.append({
            "timestamp": r["timestamp"],
            "type": "decision",
            "summary": (r["decision_text"] or "")[:80],
            "id": r["id"],
        })

    # patients
    for r in conn.execute("SELECT id, timestamp, patient_id, priority FROM patients ORDER BY timestamp"):
        events.append({
            "timestamp": r["timestamp"],
            "type": "patient",
            "summary": f"{r['patient_id']} ({r['priority']})",
            "id": r["id"],
        })

    # reports
    for r in conn.execute("SELECT id, timestamp, report_id, sender_name FROM reports ORDER BY timestamp"):
        events.append({
            "timestamp": r["timestamp"],
            "type": "report",
            "summary": f"{r['report_id']} - {r['sender_name'] or ''}",
            "id": r["id"],
        })

    # node_status_log
    for r in conn.execute("SELECT id, timestamp, node_id, battery FROM node_status_log ORDER BY timestamp"):
        events.append({
            "timestamp": r["timestamp"],
            "type": "node",
            "summary": f"Node {r['node_id']} bat:{r['battery']}%",
            "id": r["id"],
        })

    # weather_log
    for r in conn.execute("SELECT id, timestamp, temperature, humidity FROM weather_log ORDER BY timestamp"):
        events.append({
            "timestamp": r["timestamp"],
            "type": "weather",
            "summary": f"{r['temperature']}°C {r['humidity']}%",
            "id": r["id"],
        })

    conn.close()
    events.sort(key=lambda e: e["timestamp"] or "")

    start = events[0]["timestamp"] if events else ""
    end = events[-1]["timestamp"] if events else ""

    return jsonify({"start": start, "end": end, "events": events})


# ============================================================
# API: /api/snapshot
# ============================================================

@app.route("/api/snapshot")
def api_snapshot():
    ts = request.args.get("timestamp", datetime.now(TZ_TW).isoformat())
    conn = get_conn()

    patients = rows_to_list(conn.execute(
        "SELECT * FROM patients WHERE timestamp <= ? ORDER BY patient_id", (ts,)
    ).fetchall())

    locations = rows_to_list(conn.execute(
        "SELECT * FROM locations WHERE timestamp <= ? ORDER BY timestamp DESC LIMIT 200", (ts,)
    ).fetchall())

    weather_row = conn.execute(
        "SELECT * FROM weather_log WHERE timestamp <= ? ORDER BY timestamp DESC LIMIT 1", (ts,)
    ).fetchone()
    weather = dict(weather_row) if weather_row else {}

    # 每個 node 的最新狀態
    node_rows = conn.execute("""
        SELECT n.* FROM node_status_log n
        INNER JOIN (
            SELECT node_id, MAX(id) as max_id
            FROM node_status_log WHERE timestamp <= ?
            GROUP BY node_id
        ) latest ON n.id = latest.max_id
    """, (ts,)).fetchall()
    nodes = rows_to_list(node_rows)

    decision_row = conn.execute(
        "SELECT decision_text FROM decisions WHERE timestamp <= ? ORDER BY timestamp DESC LIMIT 1", (ts,)
    ).fetchone()
    latest_decision = decision_row["decision_text"] if decision_row else ""

    active_reports = rows_to_list(conn.execute(
        "SELECT * FROM reports WHERE timestamp <= ? ORDER BY timestamp DESC LIMIT 10", (ts,)
    ).fetchall())

    conn.close()
    return jsonify({
        "timestamp": ts,
        "patients": patients,
        "locations": locations,
        "weather": weather,
        "nodes": nodes,
        "latest_decision": latest_decision,
        "active_reports": active_reports,
    })


# ============================================================
# API: 各表查詢
# ============================================================

@app.route("/api/decisions")
def api_decisions():
    since = request.args.get("since", "")
    until = request.args.get("until", "9999-12-31")
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM decisions WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp DESC",
        (since, until),
    ).fetchall()
    conn.close()
    return jsonify(rows_to_list(rows))


@app.route("/api/patients")
def api_patients():
    ts = request.args.get("timestamp", "9999-12-31")
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM patients WHERE timestamp <= ? ORDER BY patient_id", (ts,)
    ).fetchall()
    conn.close()
    return jsonify(rows_to_list(rows))


@app.route("/api/locations")
def api_locations():
    since = request.args.get("since", "")
    until = request.args.get("until", "9999-12-31")
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM locations WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp",
        (since, until),
    ).fetchall()
    conn.close()
    return jsonify(rows_to_list(rows))


@app.route("/api/reports")
def api_reports():
    limit = request.args.get("limit", 20, type=int)
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM reports ORDER BY timestamp DESC LIMIT ?", (limit,)
    ).fetchall()
    conn.close()
    return jsonify(rows_to_list(rows))


@app.route("/api/transcriptions")
def api_transcriptions():
    since = request.args.get("since", "")
    until = request.args.get("until", "9999-12-31")
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM transcriptions WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp DESC",
        (since, until),
    ).fetchall()
    conn.close()
    return jsonify(rows_to_list(rows))


@app.route("/api/nodes")
def api_nodes():
    since = request.args.get("since", "")
    until = request.args.get("until", "9999-12-31")
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM node_status_log WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp",
        (since, until),
    ).fetchall()
    conn.close()
    return jsonify(rows_to_list(rows))


# ============================================================
# 音訊串流（支援 Range request）
# ============================================================

@app.route("/audio/<report_id>")
def serve_audio(report_id):
    if not re.match(r"^RPT-\d{8}-\d{3}$", report_id):
        return "Invalid report_id", 400

    if not AUDIO_DIR:
        return "Audio directory not configured", 404

    path = os.path.join(AUDIO_DIR, f"{report_id}.m4a")
    if not os.path.exists(path):
        return "Audio not found", 404

    file_size = os.path.getsize(path)
    range_header = request.headers.get("Range")

    if range_header:
        m = re.match(r"bytes=(\d+)-(\d*)", range_header)
        if not m:
            return "Invalid Range", 416

        start = int(m.group(1))
        end = int(m.group(2)) if m.group(2) else file_size - 1
        end = min(end, file_size - 1)

        if start > end or start >= file_size:
            return "Range Not Satisfiable", 416

        length = end - start + 1
        with open(path, "rb") as f:
            f.seek(start)
            data = f.read(length)

        resp = Response(data, status=206, mimetype="audio/mp4")
        resp.headers["Content-Range"] = f"bytes {start}-{end}/{file_size}"
        resp.headers["Accept-Ranges"] = "bytes"
        resp.headers["Content-Length"] = str(length)
        return resp
    else:
        with open(path, "rb") as f:
            data = f.read()
        resp = Response(data, mimetype="audio/mp4")
        resp.headers["Accept-Ranges"] = "bytes"
        resp.headers["Content-Length"] = str(file_size)
        return resp


# ============================================================
# HTML 回放介面
# ============================================================

REPLAY_HTML = """<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>LinkGuard 事件回放</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
*{margin:0;padding:0;box-sizing:border-box}
:root{
  --bg:#0a0e14;--panel:#111820;--border:#1e2a38;
  --text:#c8d6e5;--dim:#5c6b7a;--accent:#00d2ff;
  --red:#ff4757;--yellow:#ffa502;--green:#2ed573;--black-tag:#555;
}
html,body{height:100%;font-family:'Segoe UI',system-ui,sans-serif;background:var(--bg);color:var(--text);overflow:hidden}
/* Top Bar */
#topbar{display:flex;align-items:center;gap:12px;padding:8px 16px;background:var(--panel);border-bottom:1px solid var(--border);height:52px;z-index:1000}
#topbar button{background:var(--border);color:var(--text);border:none;padding:6px 14px;border-radius:4px;cursor:pointer;font-size:13px}
#topbar button:hover{background:var(--accent);color:#000}
#topbar button.active{background:var(--accent);color:#000}
#timeline-slider{flex:1;accent-color:var(--accent)}
#time-display{font-family:monospace;font-size:14px;color:var(--accent);min-width:200px;text-align:center}
#speed-group{display:flex;gap:4px}
#speed-group button.active{background:var(--accent);color:#000}
/* Main Layout */
#main{display:flex;height:calc(100% - 52px - 60px)}
#left-panel{width:280px;overflow-y:auto;background:var(--panel);border-right:1px solid var(--border);padding:8px}
#center{flex:1;position:relative}
#map{width:100%;height:100%}
#right-panel{width:320px;overflow-y:auto;background:var(--panel);border-left:1px solid var(--border);padding:8px}
/* Bottom Event Axis */
#event-axis{height:60px;background:var(--panel);border-top:1px solid var(--border);position:relative;overflow:hidden}
#event-canvas{width:100%;height:100%;cursor:pointer}
#event-tooltip{position:absolute;background:#222;color:#eee;padding:4px 8px;border-radius:4px;font-size:11px;pointer-events:none;display:none;white-space:nowrap;z-index:2000}
/* Panels */
.section-title{font-size:12px;color:var(--dim);text-transform:uppercase;letter-spacing:1px;padding:8px 0 4px;border-bottom:1px solid var(--border);margin-bottom:6px}
.patient-card{padding:6px 8px;margin-bottom:4px;border-radius:4px;font-size:12px}
.patient-card.red{background:rgba(255,71,87,.2);border-left:3px solid var(--red)}
.patient-card.black{background:rgba(85,85,85,.2);border-left:3px solid var(--black-tag)}
.patient-card.yellow{background:rgba(255,165,2,.2);border-left:3px solid var(--yellow)}
.patient-card.green{background:rgba(46,213,115,.2);border-left:3px solid var(--green)}
.node-card{padding:5px 8px;margin-bottom:3px;border-radius:4px;font-size:11px;background:rgba(0,210,255,.08);border-left:3px solid var(--accent)}
.node-card.offline{opacity:.5;border-left-color:var(--red)}
.weather-panel{padding:8px;background:rgba(0,210,255,.05);border-radius:4px;font-size:12px;line-height:1.8}
.weather-panel span{color:var(--accent);font-weight:600}
.decision-card{padding:8px;margin-bottom:6px;background:rgba(0,210,255,.05);border-radius:4px;font-size:11px;border-left:3px solid var(--accent);white-space:pre-wrap;line-height:1.5}
.decision-card .time{font-size:10px;color:var(--dim);margin-bottom:4px}
.transcript-item{padding:4px 8px;margin-bottom:3px;font-size:11px;border-left:2px solid var(--border);color:var(--dim)}
.report-item{padding:6px 8px;margin-bottom:4px;background:rgba(255,165,2,.08);border-radius:4px;font-size:11px;cursor:pointer;border-left:3px solid var(--yellow)}
.report-item:hover{background:rgba(255,165,2,.15)}
.report-item .report-id{color:var(--yellow);font-weight:600}
#audio-player{width:100%;margin:8px 0}
::-webkit-scrollbar{width:6px}
::-webkit-scrollbar-track{background:var(--bg)}
::-webkit-scrollbar-thumb{background:var(--border);border-radius:3px}
</style>
</head>
<body>

<!-- Top Bar -->
<div id="topbar">
  <button id="btn-start" title="跳到開始">⏮</button>
  <button id="btn-play" title="播放/暫停">▶</button>
  <button id="btn-end" title="跳到結束">⏭</button>
  <input type="range" id="timeline-slider" min="0" max="1000" value="0"/>
  <div id="time-display">--:--:--</div>
  <div id="speed-group">
    <button data-speed="1" class="active">1x</button>
    <button data-speed="2">2x</button>
    <button data-speed="4">4x</button>
    <button data-speed="8">8x</button>
  </div>
  <label style="font-size:11px;color:var(--dim);display:flex;align-items:center;gap:4px">
    <input type="checkbox" id="auto-audio" checked/> 自動播放音訊
  </label>
</div>

<!-- Main -->
<div id="main">
  <!-- Left -->
  <div id="left-panel">
    <div class="section-title">傷員列表</div>
    <div id="patient-list"></div>
    <div class="section-title" style="margin-top:12px">LoRa 節點</div>
    <div id="node-list"></div>
    <div class="section-title" style="margin-top:12px">氣象資料</div>
    <div id="weather-panel" class="weather-panel">載入中...</div>
  </div>
  <!-- Center (Map) -->
  <div id="center">
    <div id="map"></div>
  </div>
  <!-- Right -->
  <div id="right-panel">
    <div class="section-title">指揮決策</div>
    <div id="decision-list"></div>
    <div class="section-title" style="margin-top:12px">語音轉錄</div>
    <div id="transcript-list"></div>
    <div class="section-title" style="margin-top:12px">會報</div>
    <audio id="audio-player" controls></audio>
    <div id="report-list"></div>
  </div>
</div>

<!-- Bottom Event Axis -->
<div id="event-axis">
  <canvas id="event-canvas"></canvas>
  <div id="event-tooltip"></div>
</div>

<script>
// === State ===
let playing = false;
let speed = 1;
let timelineStart = null;
let timelineEnd = null;
let currentTime = null;
let allEvents = [];
let updateTimer = null;
let lastSnapshotTime = '';
let map, markers = {}, polylines = {};
const audioPlayer = document.getElementById('audio-player');
let playedReports = new Set();

const priorityOrder = {'紅色':0,'黑色':1,'黃色':2,'綠色':3};
const priorityClass = {'紅色':'red','黑色':'black','黃色':'yellow','綠色':'green'};
const eventColors = {decision:'#00d2ff',patient:'#ff4757',report:'#ffa502',node:'#2ed573',weather:'#a29bfe'};

// === Init Map ===
map = L.map('map',{zoomControl:false}).setView([25.033,121.565],14);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{
  attribution:'&copy; OpenStreetMap',maxZoom:19
}).addTo(map);
L.control.zoom({position:'topright'}).addTo(map);

// === Timeline fetch ===
async function fetchTimeline(){
  try{
    const r = await fetch('/api/timeline');
    const d = await r.json();
    allEvents = d.events||[];
    if(d.start){
      timelineStart = new Date(d.start);
      timelineEnd = new Date(d.end);
      currentTime = new Date(timelineStart);
      updateTimeDisplay();
      drawEventAxis();
    }
  }catch(e){console.error('Timeline fetch error:',e)}
}

// === Snapshot fetch ===
async function fetchSnapshot(ts){
  if(!ts) return;
  const iso = ts.toISOString ? ts.toISOString() : ts;
  if(iso === lastSnapshotTime) return;
  lastSnapshotTime = iso;
  try{
    const r = await fetch('/api/snapshot?timestamp='+encodeURIComponent(iso));
    const snap = await r.json();
    renderPatients(snap.patients||[]);
    renderLocations(snap.locations||[]);
    renderWeather(snap.weather||{});
    renderNodes(snap.nodes||[]);
    renderDecisions(snap);
    renderReports(snap.active_reports||[]);
    checkAutoAudio(snap.active_reports||[]);
  }catch(e){console.error('Snapshot error:',e)}
}

async function fetchTranscripts(ts){
  try{
    const since = new Date(ts.getTime() - 30*60000).toISOString();
    const r = await fetch('/api/transcriptions?since='+encodeURIComponent(since)+'&until='+encodeURIComponent(ts.toISOString()));
    const data = await r.json();
    renderTranscripts(data);
  }catch(e){}
}

// === Render ===
function renderPatients(patients){
  const sorted = [...patients].sort((a,b)=>(priorityOrder[a.priority]??9)-(priorityOrder[b.priority]??9));
  const el = document.getElementById('patient-list');
  el.innerHTML = sorted.map(p=>{
    const cls = priorityClass[p.priority]||'green';
    return '<div class="patient-card '+cls+'"><b>'+esc(p.patient_id||'')+'</b> — '+esc(p.priority||'')+'<br>'+esc(p.location_desc||'')+(p.reason?' — '+esc(p.reason):'')+'</div>';
  }).join('');
}

function renderLocations(locations){
  // 清除舊 marker
  Object.values(markers).forEach(m=>map.removeLayer(m));
  Object.values(polylines).forEach(p=>map.removeLayer(p));
  markers={};polylines={};

  // 按 device_id 分組
  const grouped={};
  locations.forEach(l=>{
    if(!l.lat||!l.lon)return;
    const did=l.device_id||'unknown';
    if(!grouped[did])grouped[did]=[];
    grouped[did].push(l);
  });

  const roleColors = {rescue:'#ff4757',hq:'#00d2ff',victim:'#ffa502',default:'#2ed573'};
  const bounds=[];

  Object.entries(grouped).forEach(([did,locs])=>{
    const last = locs[locs.length-1];
    const color = roleColors[last.role]||roleColors.default;
    const marker = L.circleMarker([last.lat,last.lon],{radius:7,fillColor:color,color:'#fff',weight:1,fillOpacity:.9})
      .bindPopup('<b>'+esc(last.name||did)+'</b><br>'+esc(last.role||'')).addTo(map);
    markers[did]=marker;
    bounds.push([last.lat,last.lon]);

    // 軌跡線（最近30分鐘的位置）
    if(locs.length>1){
      const coords = locs.map(l=>[l.lat,l.lon]);
      polylines[did]=L.polyline(coords,{color:color,weight:2,opacity:.5,dashArray:'4 4'}).addTo(map);
    }
  });

  if(bounds.length>0) map.fitBounds(bounds,{padding:[30,30],maxZoom:16});
}

function renderWeather(w){
  const el = document.getElementById('weather-panel');
  if(!w||!w.temperature){el.innerHTML='無氣象資料';return;}
  el.innerHTML=
    '🌡️ 氣溫: <span>'+(w.temperature??'-')+'°C</span><br>'+
    '💧 濕度: <span>'+(w.humidity??'-')+'%</span><br>'+
    '💨 風速: <span>'+(w.wind_speed??'-')+' m/s</span><br>'+
    '🌧️ 雨量: <span>'+(w.rainfall??'-')+' mm</span>';
}

function renderNodes(nodes){
  const el = document.getElementById('node-list');
  el.innerHTML = nodes.map(n=>{
    const on = n.online?'':'offline';
    return '<div class="node-card '+on+'">'+
      '<b>'+esc(n.node_id||'')+'</b> '+
      '🔋'+(n.battery??'-')+'% '+
      'RSSI:'+(n.rssi??'-')+' '+
      'SNR:'+(n.snr??'-')+' '+
      'PDR:'+(n.pdr??'-')+'%'+
      '</div>';
  }).join('');

  // 地圖上標記節點
  nodes.forEach(n=>{
    if(!n.lat||!n.lon)return;
    const key='node-'+n.node_id;
    if(markers[key])map.removeLayer(markers[key]);
    const color=n.online?'#00d2ff':'#ff4757';
    markers[key]=L.circleMarker([n.lat,n.lon],{radius:5,fillColor:color,color:'#fff',weight:1,fillOpacity:.7})
      .bindPopup('Node: '+esc(n.node_id)+'<br>🔋'+n.battery+'%').addTo(map);
  });
}

function renderDecisions(snap){
  const el = document.getElementById('decision-list');
  const txt = snap.latest_decision||'';
  const reports = snap.active_reports||[];
  // 從回放時間附近取決策
  let html='';
  if(txt){
    html='<div class="decision-card"><div class="time">'+esc(snap.timestamp||'')+'</div>'+esc(txt)+'</div>';
  }else{
    html='<div style="color:var(--dim);font-size:11px;padding:8px">尚無決策</div>';
  }
  el.innerHTML=html;
}

function renderTranscripts(data){
  const el = document.getElementById('transcript-list');
  if(!data||!data.length){el.innerHTML='<div style="color:var(--dim);font-size:11px;padding:8px">尚無轉錄</div>';return;}
  el.innerHTML = data.slice(0,30).map(t=>
    '<div class="transcript-item"><b>'+esc(t.sender_id||'')+'</b> ['+esc(t.source||'')+'] '+esc(t.text||'')+'</div>'
  ).join('');
}

function renderReports(reports){
  const el = document.getElementById('report-list');
  el.innerHTML = reports.map(r=>
    '<div class="report-item" data-rid="'+esc(r.report_id||'')+'">'+
    '<span class="report-id">'+esc(r.report_id||'')+'</span> — '+esc(r.sender_name||'')+'<br>'+
    '<span style="color:var(--dim)">'+esc((r.transcription||'').substring(0,60))+'</span></div>'
  ).join('');

  el.querySelectorAll('.report-item').forEach(item=>{
    item.addEventListener('click',()=>{
      const rid=item.dataset.rid;
      if(rid) playAudio(rid);
    });
  });
}

function playAudio(reportId){
  audioPlayer.src='/audio/'+reportId;
  audioPlayer.play().catch(()=>{});
}

function checkAutoAudio(reports){
  if(!document.getElementById('auto-audio').checked)return;
  reports.forEach(r=>{
    if(!r.report_id||playedReports.has(r.report_id))return;
    if(currentTime&&r.timestamp){
      const rt=new Date(r.timestamp);
      const diff=Math.abs(currentTime-rt);
      if(diff<2000*speed){
        playedReports.add(r.report_id);
        playAudio(r.report_id);
      }
    }
  });
}

function esc(s){return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')}

// === Event Axis ===
function drawEventAxis(){
  const canvas = document.getElementById('event-canvas');
  const rect = canvas.parentElement.getBoundingClientRect();
  canvas.width = rect.width;
  canvas.height = rect.height;
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0,0,canvas.width,canvas.height);

  if(!timelineStart||!timelineEnd||!allEvents.length)return;
  const range = timelineEnd-timelineStart||1;
  const pad = 20;
  const w = canvas.width - pad*2;

  // 時間軸線
  ctx.strokeStyle='#1e2a38';ctx.lineWidth=1;
  ctx.beginPath();ctx.moveTo(pad,30);ctx.lineTo(pad+w,30);ctx.stroke();

  // 事件點
  allEvents.forEach(ev=>{
    const t=new Date(ev.timestamp);
    const x=pad+((t-timelineStart)/range)*w;
    ctx.fillStyle=eventColors[ev.type]||'#888';
    ctx.beginPath();ctx.arc(x,30,3,0,Math.PI*2);ctx.fill();
  });

  // 當前時間指示線
  if(currentTime){
    const x=pad+((currentTime-timelineStart)/range)*w;
    ctx.strokeStyle='var(--accent)';ctx.lineWidth=2;
    ctx.beginPath();ctx.moveTo(x,5);ctx.lineTo(x,55);ctx.stroke();
  }

  // 時間標籤
  ctx.fillStyle='#5c6b7a';ctx.font='10px monospace';ctx.textAlign='center';
  for(let i=0;i<=4;i++){
    const t=new Date(timelineStart.getTime()+range*(i/4));
    const x=pad+(w*(i/4));
    const label=t.toLocaleTimeString('zh-TW',{hour:'2-digit',minute:'2-digit'});
    ctx.fillText(label,x,52);
  }
}

// Event axis hover / click
const eventCanvas = document.getElementById('event-canvas');
const eventTooltip = document.getElementById('event-tooltip');

eventCanvas.addEventListener('mousemove',(e)=>{
  if(!timelineStart||!timelineEnd)return;
  const rect=eventCanvas.getBoundingClientRect();
  const x=e.clientX-rect.left;
  const pad=20;const w=rect.width-pad*2;
  const range=timelineEnd-timelineStart||1;
  const hoverTime=new Date(timelineStart.getTime()+((x-pad)/w)*range);

  // 找最近的事件
  let closest=null,closestDist=Infinity;
  allEvents.forEach(ev=>{
    const t=new Date(ev.timestamp);
    const ex=pad+((t-timelineStart)/range)*w;
    const dist=Math.abs(ex-x);
    if(dist<closestDist&&dist<15){closestDist=dist;closest=ev;}
  });

  if(closest){
    eventTooltip.style.display='block';
    eventTooltip.style.left=(e.clientX-rect.left)+'px';
    eventTooltip.style.top='2px';
    eventTooltip.textContent='['+closest.type+'] '+closest.summary;
  }else{
    eventTooltip.style.display='none';
  }
});

eventCanvas.addEventListener('mouseleave',()=>{eventTooltip.style.display='none'});

eventCanvas.addEventListener('click',(e)=>{
  if(!timelineStart||!timelineEnd)return;
  const rect=eventCanvas.getBoundingClientRect();
  const x=e.clientX-rect.left;
  const pad=20;const w=rect.width-pad*2;
  const range=timelineEnd-timelineStart||1;
  currentTime=new Date(timelineStart.getTime()+((x-pad)/w)*range);
  if(currentTime<timelineStart)currentTime=new Date(timelineStart);
  if(currentTime>timelineEnd)currentTime=new Date(timelineEnd);
  updateTimeDisplay();
  fetchSnapshot(currentTime);
  fetchTranscripts(currentTime);
  drawEventAxis();
});

// === Controls ===
const btnPlay = document.getElementById('btn-play');
const slider  = document.getElementById('timeline-slider');

btnPlay.addEventListener('click',()=>{
  playing=!playing;
  btnPlay.textContent=playing?'⏸':'▶';
  if(playing)startPlayback();
  else stopPlayback();
});

document.getElementById('btn-start').addEventListener('click',()=>{
  if(timelineStart){currentTime=new Date(timelineStart);playedReports.clear();updateAll();}
});

document.getElementById('btn-end').addEventListener('click',()=>{
  if(timelineEnd){currentTime=new Date(timelineEnd);updateAll();}
});

document.querySelectorAll('#speed-group button').forEach(btn=>{
  btn.addEventListener('click',()=>{
    speed=parseInt(btn.dataset.speed);
    document.querySelectorAll('#speed-group button').forEach(b=>b.classList.remove('active'));
    btn.classList.add('active');
  });
});

slider.addEventListener('input',()=>{
  if(!timelineStart||!timelineEnd)return;
  const range=timelineEnd-timelineStart;
  const pct=slider.value/1000;
  currentTime=new Date(timelineStart.getTime()+range*pct);
  updateTimeDisplay();
  fetchSnapshot(currentTime);
  fetchTranscripts(currentTime);
  drawEventAxis();
});

function updateTimeDisplay(){
  const el=document.getElementById('time-display');
  if(!currentTime){el.textContent='--:--:--';return;}
  el.textContent=currentTime.toLocaleString('zh-TW',{hour:'2-digit',minute:'2-digit',second:'2-digit',year:'numeric',month:'2-digit',day:'2-digit'});
  if(timelineStart&&timelineEnd){
    const range=timelineEnd-timelineStart||1;
    const pct=((currentTime-timelineStart)/range)*1000;
    slider.value=Math.min(1000,Math.max(0,Math.round(pct)));
  }
}

function updateAll(){
  updateTimeDisplay();
  fetchSnapshot(currentTime);
  fetchTranscripts(currentTime);
  drawEventAxis();
}

function startPlayback(){
  if(updateTimer)return;
  updateTimer=setInterval(()=>{
    if(!currentTime||!timelineEnd)return;
    currentTime=new Date(currentTime.getTime()+1000*speed);
    if(currentTime>=timelineEnd){
      currentTime=new Date(timelineEnd);
      playing=false;
      btnPlay.textContent='▶';
      stopPlayback();
    }
    updateAll();
  },1000);
}

function stopPlayback(){
  if(updateTimer){clearInterval(updateTimer);updateTimer=null;}
}

// Resize
window.addEventListener('resize',()=>{drawEventAxis();map.invalidateSize()});

// === Init ===
fetchTimeline().then(()=>{
  if(currentTime){
    updateAll();
  }
});
</script>
</body>
</html>"""


@app.route("/")
def index():
    return Response(REPLAY_HTML, mimetype="text/html")


# ============================================================
# 主程式
# ============================================================

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="LinkGuard 離線事件回放伺服器")
    parser.add_argument("--db", metavar="PATH",
                        help="linkguard.db 路徑（省略則自動搜尋）")
    parser.add_argument("--port", type=int, default=5000,
                        help="HTTP 服務埠（預設 5000）")
    parser.add_argument("--no-browser", action="store_true",
                        help="啟動後不自動開啟瀏覽器")
    args = parser.parse_args()

    DB_PATH = args.db if args.db else find_db()
    if not DB_PATH:
        print("[Replay] 找不到 linkguard.db！")
        print("[Replay] 請將 linkguard.db 放在以下任一位置：")
        print("  - 同目錄下")
        print("  - data/ 子目錄")
        print("  - 上層目錄的 data/ 子目錄")
        exit(1)

    AUDIO_DIR = find_audio_dir()
    print(f"[Replay] 資料庫: {DB_PATH}")
    print(f"[Replay] 音訊目錄: {AUDIO_DIR or '未找到'}")

    # 驗證 DB 可讀
    try:
        conn = get_conn()
        tables = [r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).fetchall()]
        conn.close()
        print(f"[Replay] 資料表: {', '.join(tables)}")
    except Exception as e:
        print(f"[Replay] 資料庫讀取失敗: {e}")
        exit(1)

    port = args.port
    print(f"[Replay] 啟動回放伺服器 http://localhost:{port}")
    if not args.no_browser:
        webbrowser.open(f"http://localhost:{port}")
    app.run(host="0.0.0.0", port=port, debug=False)
