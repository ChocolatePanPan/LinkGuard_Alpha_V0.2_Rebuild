#define HELTEC_POWER_BUTTON
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <Preferences.h>
#include <Wire.h>
#include <esp_task_wdt.h>
#include <heltec_unofficial.h>

#define VEXT_PIN 36
#ifndef LED_BUILTIN
#define LED_BUILTIN 35
#endif
#define VBAT_FULL 4.2
#define VBAT_EMPTY 3.3
#define VBAT_LOW_WARN 3.4
#define WDT_TIMEOUT 30
#define PING_INTERVAL 3000
#define BLE_NOTIFY_INTERVAL 5000

// === BLE UUIDs（對應 iOS App LinkGuardBLE 常數）===
#define SERVICE_UUID "4FAFC201-1FB5-459E-8FCC-C5C9C331914B"
#define STATUS_CHAR_UUID "BEB5483E-36E1-4688-B7F5-EA07361B26A8"
#define COMMAND_CHAR_UUID "BEB5483E-36E1-4688-B7F5-EA07361B26AB"
#define LORA_CMD_CHAR_UUID "BEB5483E-36E1-4688-B7F5-EA07361B26AC"

static const float RF_FREQ = 910.0;
static const int CSMA_MIN_BE = 2;
static const int CSMA_MAX_BE = 4;
static const int CSMA_MAX_RETRY = 3;
static const int CSMA_SLOT_TIME = 5;
static const int CSMA_CAD_TIMEOUT = 30;
static const float CSMA_RSSI_FLOOR = -100.0;

// === LoRa Profiles (只啟用 L4，其餘保留備用) ===
struct LoRaProfile {
  int sf;
  float bw;
  int cr;
  String label;
};
LoRaProfile profiles[9] = {
    {7, 500.0, 5, "L0:極速"},  // 註解: 備用
    {7, 250.0, 5, "L1:高速"},  // 註解: 備用
    {8, 250.0, 5, "L2:敏捷"},  // 註解: 備用
    {9, 250.0, 6, "L3:平衡"},  // 註解: 備用
    {9, 125.0, 6, "L4:標準"},  // <-- 使用中
    {10, 125.0, 7, "L5:穿透"}, // 註解: 備用
    {10, 62.5, 8, "L6:強穿"},  // 註解: 備用
    {11, 62.5, 8, "L7:極限"},  // 註解: 備用
    {12, 62.5, 8, "L8:最遠"}   // 註解: 備用
};
int curLvl = 4;

String NODE_ID = "";
String deptCode = "EMT";
String pairCode = "0000";  // LoRa 配對碼（4 碼英數）
Preferences prefs;

volatile bool rxFlag = false;
void onRxFlag() { rxFlag = true; }

volatile bool cadDone = false;
volatile bool channelFree = false;

float lastRSSI = 0;
float lastSNR = 0;
unsigned long lastRxTime = 0;

float batteryVoltage = 0;
int batteryPercent = 0;
bool batteryLow = false;

unsigned long lastPing = 0;
unsigned long bootTime = 0;
unsigned long lastDisplayUpdate = 0;
bool prgPressed = false;

struct VictimNode {
  String id;
  uint16_t heartRate;
  int battery;
  float rssi;
  float snr;
  bool sos;
  unsigned long lastSeen;
};
VictimNode victims[10];
int victimCount = 0;

int activeVictimIdx = -1;

// === 團隊節點追蹤 ===
struct TeamNode {
  String id;
  String deptCode;
  int battery;
  float rssi;
  float snr;
  int victimCount;
  unsigned long lastSeen;
};
TeamNode teamNodes[10];
int teamCount = 0;

// === 增援請求暫存 ===
struct ReinforcementReq {
  String fromTeam;
  String message;
  String location;
  unsigned long time;
  bool notified; // 已通知 BLE 端
};
ReinforcementReq rfReqs[5];
int rfReqCount = 0;

// === BLE 全域變數 ===
BLEServer *pServer = NULL;
BLECharacteristic *pStatusChar = NULL;
BLECharacteristic *pCommandChar = NULL;
BLECharacteristic *pLoRaCmdChar = NULL;  // LoRa 命令轉發特徵
bool bleDeviceConnected = false;
bool bleOldConnected = false;
unsigned long lastBLENotify = 0;

// === Serial 命令緩衝 ===
String serialBuffer = "";

String seenIds[10];
int seenIdx = 0;

// === 省電：OLED 自動關閉 + 自適應發射功率 ===
unsigned long lastInteraction = 0;
bool oledOn = true;
#define OLED_AUTO_OFF_MS 30000

void generateNodeID() {
  prefs.begin("rescue-r", false);
  String savedID = prefs.getString("node_id", "");
  deptCode = prefs.getString("dept", "EMT");
  pairCode = prefs.getString("pair", "0000");
  if (savedID.length() > 0) {
    NODE_ID = savedID + "-" + deptCode;
  } else {
    randomSeed(ESP.getEfuseMac() + millis());
    uint16_t id = random(0x100, 0xFFF);
    String base = "RT-" + String(id, HEX);
    base.toUpperCase();
    prefs.putString("node_id", base);
    NODE_ID = base + "-" + deptCode;
  }
  prefs.end();
}

void readBattery() {
  // 多次取樣取中位數，減少 ADC 噪音
  float samples[5];
  for (int i = 0; i < 5; i++) {
    samples[i] = heltec_vbat();
    delay(2);
  }
  // 簡易排序取中位數
  for (int i = 0; i < 4; i++)
    for (int j = i + 1; j < 5; j++)
      if (samples[j] < samples[i]) { float t = samples[i]; samples[i] = samples[j]; samples[j] = t; }
  float voltage = samples[2];

  if (voltage < 2.5 || voltage > 4.5)
    return;  // 超出鋰電池合理範圍，忽略

  if (batteryVoltage < 1.0) {
    batteryVoltage = voltage;
  } else {
    batteryVoltage = batteryVoltage * 0.85 + voltage * 0.15;
  }
  float pct = (batteryVoltage - VBAT_EMPTY) / (VBAT_FULL - VBAT_EMPTY) * 100.0;
  batteryPercent = (int)constrain(pct, 0, 100);
  batteryLow = (batteryVoltage < VBAT_LOW_WARN);
}

float estimateDistance(float rssi) {
  float n = 2.7;
  float A = -30.0;
  return pow(10.0, (A - rssi) / (10.0 * n));
}

String formatDistance(float dist) {
  if (dist < 0.1)
    return "<0.1m";
  if (dist < 10)
    return String(dist, 1) + "m";
  if (dist < 1000)
    return String((int)dist) + "m";
  return String(dist / 1000, 1) + "km";
}

void setLevel(int l) {
  if (l < 0)
    l = 0;
  if (l > 8)
    l = 8;
  curLvl = l;
  radio.standby();
  delay(10);
  radio.setFrequency(RF_FREQ);
  radio.setOutputPower(22);
  radio.setSpreadingFactor(profiles[l].sf);
  radio.setBandwidth(profiles[l].bw);
  radio.setCodingRate(profiles[l].cr);
  delay(10);
  radio.startReceive(RADIOLIB_SX126X_RX_TIMEOUT_INF);
}

void onCadDone(bool detected) {
  cadDone = true;
  channelFree = !detected;
}

bool isChannelFree() {
  cadDone = false;
  channelFree = false;
  radio.clearDio1Action();
  radio.setDio1Action([]() {
    onCadDone(radio.getChannelScanResult() == RADIOLIB_LORA_DETECTED);
  });
  int16_t state = radio.startChannelScan();
  if (state != RADIOLIB_ERR_NONE) {
    radio.setDio1Action(onRxFlag);
    return true;
  }
  unsigned long start = millis();
  while (!cadDone && (millis() - start < CSMA_CAD_TIMEOUT))
    delay(1);
  radio.setDio1Action(onRxFlag);
  if (!cadDone)
    return true;
  if (!channelFree) {
    if (radio.getRSSI() < CSMA_RSSI_FLOOR)
      return true;
  }
  return channelFree;
}

bool csmaBackoff() {
  int be = CSMA_MIN_BE;
  for (int retry = 0; retry < CSMA_MAX_RETRY; retry++) {
    if (isChannelFree())
      return true;
    int slots = random(0, (1 << be));
    delay(slots * CSMA_SLOT_TIME);
    if (be < CSMA_MAX_BE)
      be++;
  }
  return false;
}

bool isDuplicate(String id) {
  for (int i = 0; i < 10; i++)
    if (seenIds[i] == id)
      return true;
  return false;
}

void markSeen(String id) {
  seenIds[seenIdx] = id;
  seenIdx = (seenIdx + 1) % 10;
}

void updateVictim(String id, uint16_t hr, int bat, float rssi, float snr,
                  bool sos) {
  unsigned long now = millis();
  for (int i = 0; i < victimCount; i++) {
    if (victims[i].id == id) {
      victims[i].heartRate = hr;
      victims[i].battery = bat;
      victims[i].rssi = rssi;
      victims[i].snr = snr;
      victims[i].sos = sos;
      victims[i].lastSeen = now;
      activeVictimIdx = i;
      return;
    }
  }
  if (victimCount < 10) {
    victims[victimCount] = {id, hr, bat, rssi, snr, sos, now};
    activeVictimIdx = victimCount;
    victimCount++;
  }
}

void updateTeamNode(String id, String dept, int bat, int vCount, float rssi, float snr) {
  unsigned long now = millis();
  for (int i = 0; i < teamCount; i++) {
    if (teamNodes[i].id == id) {
      teamNodes[i].deptCode = dept;
      teamNodes[i].battery = bat;
      teamNodes[i].victimCount = vCount;
      teamNodes[i].rssi = rssi;
      teamNodes[i].snr = snr;
      teamNodes[i].lastSeen = now;
      return;
    }
  }
  if (teamCount < 10) {
    teamNodes[teamCount] = {id, dept, bat, rssi, snr, vCount, now};
    teamCount++;
  }
}

void addReinforcementReq(String from, String msg, String loc) {
  if (rfReqCount < 5) {
    rfReqs[rfReqCount] = {from, msg, loc, millis(), false};
    rfReqCount++;
  }
}

// === 省電功能 ===
void adjustTxPower() {
  if (lastRSSI > -70) {
    radio.setOutputPower(14);
  } else if (lastRSSI > -90) {
    radio.setOutputPower(18);
  } else {
    radio.setOutputPower(22);
  }
}

void wakeOLED() {
  lastInteraction = millis();
  if (!oledOn) {
    display.displayOn();
    oledOn = true;
  }
}

void sendRescuePing() {
  String pktId = String(random(0xFFFF), HEX);
  String packet = pktId + "|" + pairCode + "|" + NODE_ID + "|RESCUE|B" + String(batteryPercent);

  radio.clearDio1Action();
  radio.standby();
  delay(5);
  int state = radio.transmit(packet);
  if (state == RADIOLIB_ERR_NONE) {
    digitalWrite(LED_BUILTIN, HIGH);
    delay(50);
    digitalWrite(LED_BUILTIN, LOW);
  }
  radio.setDio1Action(onRxFlag);
  radio.startReceive(RADIOLIB_SX126X_RX_TIMEOUT_INF);
}

void sendTeamPing() {
  String pktId = String(random(0xFFFF), HEX);
  String packet = pktId + "|" + pairCode + "|" + NODE_ID + "|TEAM|B" +
                  String(batteryPercent) + "|V" + String(victimCount);
  radio.clearDio1Action();
  radio.standby();
  delay(5);
  int state = radio.transmit(packet);
  if (state == RADIOLIB_ERR_NONE) {
    digitalWrite(LED_BUILTIN, HIGH);
    delay(30);
    digitalWrite(LED_BUILTIN, LOW);
  }
  radio.setDio1Action(onRxFlag);
  radio.startReceive(RADIOLIB_SX126X_RX_TIMEOUT_INF);
}

void sendReinforceRequest(String msg, String loc) {
  String pktId = String(random(0xFFFF), HEX);
  String packet = pktId + "|" + pairCode + "|" + NODE_ID + "|REINFORCE|" + msg + "|" + loc;
  if (!csmaBackoff()) return;
  radio.clearDio1Action();
  radio.standby();
  delay(5);
  radio.transmit(packet);
  radio.setDio1Action(onRxFlag);
  radio.startReceive(RADIOLIB_SX126X_RX_TIMEOUT_INF);
  Serial.println("[TX] REINFORCE: " + msg + " @ " + loc);
}

void sendReinforceReply(String targetTeam, bool accept) {
  String pktId = String(random(0xFFFF), HEX);
  String type = accept ? "RF_JOIN" : "RF_NAK";
  String packet = pktId + "|" + pairCode + "|" + NODE_ID + "|" + type + "|" + targetTeam;
  if (!csmaBackoff()) return;
  radio.clearDio1Action();
  radio.standby();
  delay(5);
  radio.transmit(packet);
  radio.setDio1Action(onRxFlag);
  radio.startReceive(RADIOLIB_SX126X_RX_TIMEOUT_INF);
  Serial.println("[TX] " + type + " -> " + targetTeam);
}

// === 發送 LoRa 指揮命令（控制中心 → 所有節點）===
// 封包格式: pktId|pairCode|senderID|CMD|cmd_id|type|pri|title|detail
void sendLoRaCommand(String cmdId, String type, int pri, String title, String detail) {
  String pktId = String(random(0xFFFF), HEX);
  String packet = pktId + "|" + pairCode + "|" + NODE_ID + "|CMD|" +
                  cmdId + "|" + type + "|" + String(pri) + "|" + title + "|" + detail;
  if (!csmaBackoff()) {
    Serial.println("[CMD] CSMA backoff failed, force send");
  }
  radio.clearDio1Action();
  radio.standby();
  delay(5);
  int state = radio.transmit(packet);
  radio.setDio1Action(onRxFlag);
  radio.startReceive(RADIOLIB_SX126X_RX_TIMEOUT_INF);
  if (state == RADIOLIB_ERR_NONE) {
    Serial.println("[TX-CMD] " + title + " (pri:" + String(pri) + ")");
    // 同時通知 BLE 已連接的 App
    notifyBLECommand(cmdId, type, pri, title, detail);
  } else {
    Serial.println("[TX-CMD] FAIL: " + String(state));
  }
}

// 透過 BLE 通知已連接的 App 收到命令
void notifyBLECommand(String cmdId, String type, int pri, String title, String detail) {
  if (!bleDeviceConnected || !pLoRaCmdChar) return;
  String json = "{\"cmd_id\":\"" + cmdId + "\",\"type\":\"" + type +
                "\",\"pri\":" + String(pri) +
                ",\"title\":\"" + title +
                "\",\"detail\":\"" + detail +
                "\",\"sender\":\"" + NODE_ID + "\"}";
  pLoRaCmdChar->setValue(json.c_str());
  pLoRaCmdChar->notify();
}

// === 處理 Serial 命令（Mac 控制中心用）===
// 格式: CMD:cmd_id:type:pri:title:detail
// 範例: CMD:550e8400:evacuation:2:立即撤離:偵測到餘震風險所有人員撤離
void processSerialCommand(String line) {
  line.trim();
  if (line.startsWith("CMD:")) {
    String payload = line.substring(4);
    // 解析 5 個欄位: cmd_id:type:pri:title:detail
    int s1 = payload.indexOf(':');
    int s2 = payload.indexOf(':', s1 + 1);
    int s3 = payload.indexOf(':', s2 + 1);
    int s4 = payload.indexOf(':', s3 + 1);
    if (s1 > 0 && s2 > 0 && s3 > 0 && s4 > 0) {
      String cmdId  = payload.substring(0, s1);
      String type   = payload.substring(s1 + 1, s2);
      int pri       = payload.substring(s2 + 1, s3).toInt();
      String title  = payload.substring(s3 + 1, s4);
      String detail = payload.substring(s4 + 1);
      sendLoRaCommand(cmdId, type, pri, title, detail);
      Serial.println("OK:" + cmdId);
    } else {
      Serial.println("ERR:BAD_FORMAT");
    }
  } else if (line == "STATUS") {
    // 回傳目前狀態 JSON
    Serial.println(buildStatusJSON());
  } else if (line == "PING") {
    Serial.println("PONG:" + NODE_ID);
  } else if (line.startsWith("SETPAIR:")) {
    String p = line.substring(8);
    p.toUpperCase();
    if (p.length() >= 1 && p.length() <= 8) {
      pairCode = p;
      prefs.begin("rescue-r", false);
      prefs.putString("pair", pairCode);
      prefs.end();
      Serial.println("OK:PAIR=" + pairCode);
    }
  } else if (line.startsWith("SETLVL:")) {
    int l = line.substring(7).toInt();
    setLevel(l);
    Serial.println("OK:LVL=" + String(curLvl));
  }
}

void updateDisplay() {
  display.clear();
  display.setFont(ArialMT_Plain_10);

  display.drawString(0, 0, "[RES] " + NODE_ID);
  String pairLvl = pairCode + " L" + String(curLvl);
  display.drawString(128 - display.getStringWidth(pairLvl), 0, pairLvl);

  display.setFont(ArialMT_Plain_24);

  if (activeVictimIdx >= 0 &&
      (millis() - victims[activeVictimIdx].lastSeen < 30000)) {
    VictimNode &v = victims[activeVictimIdx];
    if (v.heartRate > 0) {
      String hrStr = String(v.heartRate) + " bpm";
      display.drawString(0, 12, hrStr);
    } else {
      display.drawString(0, 12, "-- bpm");
    }
    display.setFont(ArialMT_Plain_10);
    String victimInfo = v.id;
    if (v.sos)
      victimInfo += " SOS";
    display.drawString(0, 38, victimInfo);

    float dist = estimateDistance(v.rssi);
    String sigStr = String((int)v.rssi) + "dBm ~" + formatDistance(dist);
    display.drawString(0, 49, sigStr);
  } else {
    display.drawString(0, 12, "-- bpm");
    display.setFont(ArialMT_Plain_10);
    display.drawString(0, 38, "Scanning...");
    display.drawString(0, 49, "No signal");
  }

  display.setFont(ArialMT_Plain_10);
  String batStr = String(batteryPercent) + "% " + String(batteryVoltage, 2) + "V";
  display.drawString(128 - display.getStringWidth(batStr), 49, batStr);

  display.display();
}

// === BLE 連線回呼 ===
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) { bleDeviceConnected = true; }
  void onDisconnect(BLEServer *pServer) { bleDeviceConnected = false; }
};

// === BLE 指令接收回呼 ===
class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    String val = pChar->getValue().c_str();
    if (val.startsWith("setdept:")) {
      String d = val.substring(8);
      d.toUpperCase();
      if (d.length() >= 1 && d.length() <= 3) {
        deptCode = d;
        prefs.begin("rescue-r", false);
        String base = prefs.getString("node_id", "RT-000");
        prefs.putString("dept", deptCode);
        prefs.end();
        NODE_ID = base + "-" + deptCode;
        Serial.println("[BLE] Dept -> " + NODE_ID);
      }
    } else if (val.startsWith("setlvl:")) {
      int l = val.substring(7).toInt();
      setLevel(l);
      Serial.println("[BLE] Level -> L" + String(curLvl));
    } else if (val.startsWith("setpair:")) {
      String p = val.substring(8);
      p.toUpperCase();
      if (p.length() >= 1 && p.length() <= 8) {
        pairCode = p;
        prefs.begin("rescue-r", false);
        prefs.putString("pair", pairCode);
        prefs.end();
        Serial.println("[BLE] Pair -> " + pairCode);
      }
    } else if (val.startsWith("reinforce:")) {
      // 格式: reinforce:msg|loc
      String payload = val.substring(10);
      int sep = payload.indexOf('|');
      if (sep > 0) {
        String msg = payload.substring(0, sep);
        String loc = payload.substring(sep + 1);
        sendReinforceRequest(msg, loc);
      }
    } else if (val.startsWith("rf_reply:")) {
      // 格式: rf_reply:teamId|JOIN 或 rf_reply:teamId|NAK
      String payload = val.substring(9);
      int sep = payload.indexOf('|');
      if (sep > 0) {
        String team = payload.substring(0, sep);
        String action = payload.substring(sep + 1);
        sendReinforceReply(team, action == "JOIN");
      }
    } else if (val == "team_ping") {
      sendTeamPing();
    }
  }
};

// === 產生狀態 JSON（BLE Notify 用）===
String buildStatusJSON() {
  String j = "{";
  j += "\"id\":\"" + NODE_ID + "\",";
  j += "\"dept\":\"" + deptCode + "\",";
  j += "\"bat\":" + String(batteryPercent) + ",";
  j += "\"vbat\":" + String(batteryVoltage, 2) + ",";
  j += "\"lvl\":" + String(curLvl) + ",";
  j += "\"pair\":\"" + pairCode + "\",";
  j += "\"victims\":[";
  unsigned long now = millis();
  bool first = true;
  for (int i = 0; i < victimCount; i++) {
    bool online = (now - victims[i].lastSeen < 30000);
    if (!first)
      j += ",";
    first = false;
    j += "{\"id\":\"" + victims[i].id + "\"";
    j += ",\"hr\":" + String(victims[i].heartRate);
    j += ",\"bat\":" + String(victims[i].battery);
    j += ",\"rssi\":" + String(victims[i].rssi, 0);
    j += ",\"snr\":" + String(victims[i].snr, 1);
    j += ",\"sos\":" + String(victims[i].sos ? "true" : "false");
    j += ",\"online\":" + String(online ? "true" : "false");
    j += "}";
  }
  j += "],\"team\":[";
  first = true;
  for (int i = 0; i < teamCount; i++) {
    bool online = (now - teamNodes[i].lastSeen < 30000);
    if (!first)
      j += ",";
    first = false;
    j += "{\"id\":\"" + teamNodes[i].id + "\"";
    j += ",\"dept\":\"" + teamNodes[i].deptCode + "\"";
    j += ",\"bat\":" + String(teamNodes[i].battery);
    j += ",\"rssi\":" + String(teamNodes[i].rssi, 0);
    j += ",\"vc\":" + String(teamNodes[i].victimCount);
    j += ",\"online\":" + String(online ? "true" : "false");
    j += "}";
  }
  j += "],\"rf\":[";
  first = true;
  for (int i = 0; i < rfReqCount; i++) {
    if (!first)
      j += ",";
    first = false;
    j += "{\"from\":\"" + rfReqs[i].fromTeam + "\"";
    j += ",\"msg\":\"" + rfReqs[i].message + "\"";
    j += ",\"loc\":\"" + rfReqs[i].location + "\"";
    j += ",\"ago\":" + String((now - rfReqs[i].time) / 1000);
    j += "}";
  }
  j += "]}";
  return j;
}

void setup() {
  Serial.begin(115200);
  pinMode(VEXT_PIN, OUTPUT);
  digitalWrite(VEXT_PIN, LOW);
  delay(100);
  heltec_setup();

  display.init();
  display.flipScreenVertically();
  display.setFont(ArialMT_Plain_10);
  display.setColor(WHITE);
  display.clear();
  display.drawString(0, 0, "Rescue v1.0");
  display.display();

  generateNodeID();
  display.drawString(0, 10, "ID: " + NODE_ID);
  display.display();

  readBattery();
  pinMode(LED_BUILTIN, OUTPUT);

  esp_task_wdt_init(WDT_TIMEOUT, true);
  esp_task_wdt_add(NULL);

  display.drawString(0, 20, "Radio Init...");
  display.display();
  int16_t state = radio.begin();
  if (state != RADIOLIB_ERR_NONE) {
    display.drawString(0, 30, "Radio FAIL!");
    display.display();
    while (1)
      delay(1000);
  }
  display.drawString(0, 30, "Radio OK");
  display.display();

  radio.setDio1Action(onRxFlag);
  setLevel(4);

  // === BLE 初始化 ===
  display.drawString(0, 40, "BLE Init...");
  display.display();

  BLEDevice::init(NODE_ID.c_str());
  BLEDevice::setMTU(517);  // 提高 MTU 避免 JSON 截斷
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  // 狀態特徵（Notify）：定期推送與 /up 相同的 JSON
  pStatusChar = pService->createCharacteristic(
      STATUS_CHAR_UUID, BLECharacteristic::PROPERTY_READ |
                            BLECharacteristic::PROPERTY_NOTIFY);
  pStatusChar->addDescriptor(new BLE2902());

  // 指令特徵（Write）：接收 App 端的 setdept / setlvl 指令
  pCommandChar = pService->createCharacteristic(
      COMMAND_CHAR_UUID, BLECharacteristic::PROPERTY_WRITE);
  pCommandChar->setCallbacks(new CommandCallbacks());

  // LoRa 命令特徵（Notify）：轉發收到的指揮命令給 App
  pLoRaCmdChar = pService->createCharacteristic(
      LORA_CMD_CHAR_UUID, BLECharacteristic::PROPERTY_READ |
                              BLECharacteristic::PROPERTY_NOTIFY);
  pLoRaCmdChar->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  BLEDevice::startAdvertising();

  Serial.println("[BLE] Ready: " + NODE_ID);

  display.clear();
  display.drawString(0, 50, "Ready");
  display.display();
  lastInteraction = millis();
  bootTime = millis();
  delay(1500);
  updateDisplay();
}

void loop() {
  heltec_loop();
  esp_task_wdt_reset();

  if (rxFlag) {
    rxFlag = false;
    String packet;
    int state = radio.readData(packet);

    if (state == RADIOLIB_ERR_NONE && packet.length() > 0) {
      lastRSSI = radio.getRSSI();
      lastSNR = radio.getSNR();
      lastRxTime = millis();
      wakeOLED();

      Serial.printf("[RX-RAW] RSSI:%.0f SNR:%.1f len:%d -> %s\n",
                    lastRSSI, lastSNR, packet.length(),
                    packet.substring(0, min((int)packet.length(), 80)).c_str());

      int sep1 = packet.indexOf('|');
      int sep2 = packet.indexOf('|', sep1 + 1);
      int sep3 = packet.indexOf('|', sep2 + 1);
      int sep4 = packet.indexOf('|', sep3 + 1);

      // === 嘗試解析為 victim 封包: pktId|pairCode|sender|TYPE|B{bat}|BPM{hr} ===
      if (sep1 > 0 && sep2 > 0 && sep3 > 0 && sep4 > 0) {
        String pId = packet.substring(0, sep1);
        String rxPair = packet.substring(sep1 + 1, sep2);
        String sender = packet.substring(sep2 + 1, sep3);
        String type = packet.substring(sep3 + 1, sep4);

        // 配對碼過濾：不同碼的封包直接忽略
        if (rxPair != pairCode) {
          Serial.printf("[RX] Pair mismatch: got '%s' expect '%s' from %s\n",
                        rxPair.c_str(), pairCode.c_str(), sender.c_str());
          radio.startReceive(RADIOLIB_SX126X_RX_TIMEOUT_INF);
          return;
        }

        if (!isDuplicate(pId) && (type == "SOS" || type == "ACK")) {
          markSeen(pId);

          bool isSOS = sender.endsWith("SOS") || type == "SOS";
          String cleanId = sender;
          if (cleanId.endsWith(" SOS"))
            cleanId = cleanId.substring(0, cleanId.length() - 4);

          int bpmIdx = packet.indexOf("|BPM");
          uint16_t hr = 0;
          if (bpmIdx > 0) {
            int val = packet.substring(bpmIdx + 4).toInt();
            if (val >= 30 && val <= 250)
              hr = (uint16_t)val;
          }

          int batIdx = packet.indexOf("|B");
          int bat = 0;
          if (batIdx > 0) {
            String batStr = packet.substring(batIdx + 2);
            int nextPipe = batStr.indexOf('|');
            if (nextPipe > 0)
              batStr = batStr.substring(0, nextPipe);
            bat = batStr.toInt();
            if (bat < 0 || bat > 100)
              bat = 0;
          }

          updateVictim(cleanId, hr, bat, lastRSSI, lastSNR, isSOS);

          Serial.printf("[RX] %s HR:%d BAT:%d%% RSSI:%.0f %s\n",
                        cleanId.c_str(), hr, bat, lastRSSI,
                        isSOS ? "SOS!" : "");

          digitalWrite(LED_BUILTIN, HIGH);
          delay(30);
          digitalWrite(LED_BUILTIN, LOW);
        }

        // === TEAM 封包: pktId|pairCode|senderID|TEAM|B{bat}|V{vc} ===
        if (!isDuplicate(pId) && type == "TEAM" && sender != NODE_ID) {
          markSeen(pId);
          // 解析部門碼（senderID 格式: RT-xxx-DEPT）
          String dept = "";
          int lastDash = sender.lastIndexOf('-');
          if (lastDash > 0) dept = sender.substring(lastDash + 1);

          int batIdx = packet.indexOf("|B", sep4);
          int bat = 0;
          if (batIdx > 0) {
            String batStr = packet.substring(batIdx + 2);
            int nextPipe = batStr.indexOf('|');
            if (nextPipe > 0) batStr = batStr.substring(0, nextPipe);
            bat = batStr.toInt();
          }
          int vcIdx = packet.indexOf("|V");
          int vc = 0;
          if (vcIdx > 0) vc = packet.substring(vcIdx + 2).toInt();

          updateTeamNode(sender, dept, bat, vc, lastRSSI, lastSNR);
          Serial.printf("[RX-TEAM] %s BAT:%d%% VC:%d RSSI:%.0f\n",
                        sender.c_str(), bat, vc, lastRSSI);
        }

        // === REINFORCE 封包: pktId|pairCode|senderID|REINFORCE|msg|loc ===
        if (!isDuplicate(pId) && type == "REINFORCE" && sender != NODE_ID) {
          markSeen(pId);
          int sep5 = packet.indexOf('|', sep4 + 1);
          String msg = (sep5 > 0) ? packet.substring(sep4 + 1, sep5) : packet.substring(sep4 + 1);
          String loc = (sep5 > 0) ? packet.substring(sep5 + 1) : "";
          addReinforcementReq(sender, msg, loc);
          Serial.printf("[RX-RF] REINFORCE from %s: %s @ %s\n",
                        sender.c_str(), msg.c_str(), loc.c_str());
        }

        // === RF_JOIN / RF_NAK 封包: pktId|pairCode|senderID|RF_JOIN|targetTeam ===
        if (!isDuplicate(pId) && (type == "RF_JOIN" || type == "RF_NAK")) {
          markSeen(pId);
          String target = packet.substring(sep4 + 1);
          if (target == NODE_ID) {
            Serial.printf("[RX-RF] %s from %s\n", type.c_str(), sender.c_str());
          }
        }

        // === CMD 封包: pktId|pairCode|senderID|CMD|cmd_id|type|pri|title|detail ===
        if (!isDuplicate(pId) && type == "CMD" && sender != NODE_ID) {
          markSeen(pId);
          // 解析: cmd_id|type|pri|title|detail
          int cs1 = packet.indexOf('|', sep4 + 1);
          int cs2 = packet.indexOf('|', cs1 + 1);
          int cs3 = packet.indexOf('|', cs2 + 1);
          int cs4 = packet.indexOf('|', cs3 + 1);
          if (cs1 > 0 && cs2 > 0 && cs3 > 0 && cs4 > 0) {
            String cmdId    = packet.substring(sep4 + 1, cs1);
            String cmdType  = packet.substring(cs1 + 1, cs2);
            int cmdPri      = packet.substring(cs2 + 1, cs3).toInt();
            String cmdTitle = packet.substring(cs3 + 1, cs4);
            String cmdDetail = packet.substring(cs4 + 1);
            Serial.printf("[RX-CMD] %s pri:%d from %s\n",
                          cmdTitle.c_str(), cmdPri, sender.c_str());
            // 轉發給 BLE 連接的 App
            notifyBLECommand(cmdId, cmdType, cmdPri, cmdTitle, cmdDetail);
            // 也輸出到 Serial（Mac 控制中心可以監聽）
            Serial.println("CMD_RX:" + cmdId + ":" + cmdType + ":" +
                           String(cmdPri) + ":" + cmdTitle + ":" + cmdDetail +
                           ":" + sender);
          }
        }
      }  // end else-if chain
      // === 嘗試解析為實驗韌體封包: pktId|sender|PING|S{n}|B{bat} ===
      else if (sep1 > 0 && sep2 > 0 && sep3 > 0) {
        String pId = packet.substring(0, sep1);
        String sender = packet.substring(sep1 + 1, sep2);
        String type = packet.substring(sep2 + 1, sep3);

        if (!isDuplicate(pId) && type == "PING" && sender.startsWith("EX-")) {
          markSeen(pId);

          int batIdx = packet.indexOf("|B");
          int bat = 0;
          if (batIdx > 0) {
            String batStr = packet.substring(batIdx + 2);
            int nextPipe = batStr.indexOf('|');
            if (nextPipe > 0)
              batStr = batStr.substring(0, nextPipe);
            bat = batStr.toInt();
            if (bat < 0 || bat > 100)
              bat = 0;
          }

          updateVictim(sender, 0, bat, lastRSSI, lastSNR, false);

          Serial.printf("[RX-EXP] %s BAT:%d%% RSSI:%.0f SNR:%.1f\n",
                        sender.c_str(), bat, lastRSSI, lastSNR);

          digitalWrite(LED_BUILTIN, HIGH);
          delay(30);
          digitalWrite(LED_BUILTIN, LOW);
        }
      }
    }
    radio.startReceive(RADIOLIB_SX126X_RX_TIMEOUT_INF);
  }

  if (millis() - lastPing >= PING_INTERVAL) {
    lastPing = millis();
    readBattery();
    adjustTxPower();
    sendRescuePing();
    // 每 3 次 PING 發送一次 TEAM 廣播
    static int pingCount = 0;
    pingCount++;
    if (pingCount % 3 == 0) {
      delay(100);
      sendTeamPing();
    }
  }

  if (millis() - lastDisplayUpdate >= 500) {
    lastDisplayUpdate = millis();
    if (oledOn) updateDisplay();
  }

  // OLED 自動關閉（30 秒無互動）
  if (oledOn && millis() - lastInteraction > OLED_AUTO_OFF_MS) {
    display.displayOff();
    oledOn = false;
  }

  // === BLE Notify：定期推送狀態 JSON 到已連接的 iOS App ===
  if (bleDeviceConnected && (millis() - lastBLENotify >= BLE_NOTIFY_INTERVAL)) {
    lastBLENotify = millis();
    String statusJson = buildStatusJSON();
    pStatusChar->setValue(statusJson.c_str());
    pStatusChar->notify();
  }

  // === 讀取 Serial 命令（Mac 控制中心）===
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (serialBuffer.length() > 0) {
        processSerialCommand(serialBuffer);
        serialBuffer = "";
      }
    } else {
      serialBuffer += c;
      if (serialBuffer.length() > 256) serialBuffer = "";  // 防溢出
    }
  }

  // BLE 斷線後重新啟動廣播
  if (!bleDeviceConnected && bleOldConnected) {
    delay(500);
    pServer->startAdvertising();
    Serial.println("[BLE] Restart advertising");
  }
  bleOldConnected = bleDeviceConnected;

  unsigned long now = millis();
  for (int i = victimCount - 1; i >= 0; i--) {
    if (now - victims[i].lastSeen > 120000) {
      for (int j = i; j < victimCount - 1; j++)
        victims[j] = victims[j + 1];
      victimCount--;
      if (activeVictimIdx >= victimCount)
        activeVictimIdx = victimCount - 1;
    }
  }
  // 清理超時團隊節點（60 秒無回應視為離線，120 秒後移除）
  for (int i = teamCount - 1; i >= 0; i--) {
    if (now - teamNodes[i].lastSeen > 120000) {
      for (int j = i; j < teamCount - 1; j++)
        teamNodes[j] = teamNodes[j + 1];
      teamCount--;
    }
  }
  // 清理過期增援請求（5 分鐘）
  for (int i = rfReqCount - 1; i >= 0; i--) {
    if (now - rfReqs[i].time > 300000) {
      for (int j = i; j < rfReqCount - 1; j++)
        rfReqs[j] = rfReqs[j + 1];
      rfReqCount--;
    }
  }
}
