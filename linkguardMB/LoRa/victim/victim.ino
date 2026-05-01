// =====================================================
//  LinkGuard — 受困端韌體 (Victim Node)
//  Heltec WiFi LoRa 32 V3
//  與 rescue.ino (搜救端) 通訊
//  LoRa 封包格式: pktId|pairCode|VT-XXX|TYPE|B{bat}|BPM{hr}
//
//  心率來源模式（可切換, 持久化）：
//    HR_MODE_SIM    — 內建模擬心率（無需外部設備）
//    HR_MODE_GARMIN — Garmin BLE HRP (Heart Rate Service 0x180D)
//
//  切換方式：
//    Serial:  mode:sim  / mode:garmin
//    按鍵:    PRG 長按 >2 秒切換模式（短按仍為 SOS 開關）
// =====================================================

#define HELTEC_POWER_BUTTON
#include <BLEDevice.h>
#include <BLEClient.h>
#include <BLEScan.h>
#include <BLEUtils.h>
#include <BLEAdvertisedDevice.h>
#include <Preferences.h>
#include <Wire.h>
#include <esp_task_wdt.h>
#include <heltec_unofficial.h>

#define VEXT_PIN 36
#ifndef LED_BUILTIN
#define LED_BUILTIN 35
#endif
#define VBAT_FULL       4.2
#define VBAT_EMPTY      3.3
#define VBAT_LOW_WARN   3.4
#define WDT_TIMEOUT     30
#define PING_INTERVAL_NORMAL 15000
#define PING_INTERVAL_SOS    3000
#define DEBOUNCE_MS     300
#define HR_UPDATE_MS    2000
#define LONG_PRESS_MS   2000

// === Garmin BLE Heart Rate Profile ===
// 標準 BLE Heart Rate Service / Measurement Characteristic
#define BLE_SCAN_DURATION   5       // 每次掃描秒數
#define BLE_SCAN_INTERVAL   15000   // 斷線後重新掃描間隔 (ms)
#define BLE_SCAN_STUCK_MS   12000   // 掃描卡住超過此時間強制重置
static BLEUUID hrServiceUUID((uint16_t)0x180D);   // Heart Rate Service
static BLEUUID hrMeasCharUUID((uint16_t)0x2A37);  // Heart Rate Measurement

BLEClient*    bleClient       = nullptr;
BLEScan*      bleScan         = nullptr;
BLEAddress    garminAddr("");
esp_ble_addr_type_t garminAddrType = BLE_ADDR_TYPE_PUBLIC;
bool          garminFound      = false;
bool          garminConnected  = false;
bool          doScan           = true;
bool          scanInProgress   = false;
unsigned long lastBLEScan      = 0;
volatile unsigned long lastGarminHR = 0;  // BLE 任務寫入，主 loop 讀取
#define GARMIN_TIMEOUT_MS 10000     // 超過此時間無通知視為失聯
bool          bleReady         = false;  // BLEDevice::init() 只能呼叫一次

// === 心率模式 ===
enum HRMode { HR_MODE_SIM, HR_MODE_GARMIN };
HRMode hrMode = HR_MODE_SIM;  // 預設模擬模式，startup 時從 NVS 載入

// === LoRa 設定（與 rescue.ino L4 完全一致）===
static const float RF_FREQ = 910.0;
static const int   LORA_SF = 9;
static const float LORA_BW = 125.0;
static const int   LORA_CR = 6;

// === CSMA/CA 參數（與 rescue.ino 一致）===
static const int   CSMA_MIN_BE      = 2;
static const int   CSMA_MAX_BE      = 4;
static const int   CSMA_MAX_RETRY   = 3;
static const int   CSMA_SLOT_TIME   = 5;
static const int   CSMA_CAD_TIMEOUT = 30;
static const float CSMA_RSSI_FLOOR  = -100.0;

// === 全域狀態 ===
String NODE_ID = "";
String pairCode = "0000";  // LoRa 配對碼（與 rescue.ino 相同才能通訊）
Preferences prefs;

volatile bool rxFlag = false;
void onRxFlag() { rxFlag = true; }

volatile bool cadDone    = false;
volatile bool channelFree = false;

float batteryVoltage = 0;
int   batteryPercent = 0;
bool  batteryLow     = false;

unsigned long lastPing          = 0;
unsigned long bootTime          = 0;
unsigned long lastDisplayUpdate = 0;
unsigned long lastRescueRx      = 0;

// SOS 狀態 + 按鍵追蹤
bool isSOS = false;
bool lastButtonState  = true;  // PRG 按鍵預設 HIGH（active low）
unsigned long pressStartMs  = 0;  // 按下時刻（用於長按偵測）
bool          pressHandled  = false;

// 心率（volatile：BLE 回調任務與主 loop 共用）
int baseHeartRate        = 0;
volatile int currentHeartRate = 0;
unsigned long lastHRUpdate    = 0;

// 封包去重
String seenIds[10];
int seenIdx = 0;

// === 省電：OLED 自動關閉 + 自適應發射功率 ===
unsigned long lastInteraction = 0;
bool oledOn = true;
#define OLED_AUTO_OFF_MS 30000
float lastRxRSSI = 0;

// =====================================================
//  節點 ID 產生（VT-XXX 格式，持久化）
// =====================================================

void generateNodeID() {
  prefs.begin("victim-v", false);
  String savedID = prefs.getString("node_id", "");
  pairCode = prefs.getString("pair", "0000");
  if (savedID.length() > 0) {
    NODE_ID = savedID;
  } else {
    randomSeed(ESP.getEfuseMac() + millis());
    uint16_t id = random(0x100, 0xFFF);
    NODE_ID = "VT-" + String(id, HEX);
    NODE_ID.toUpperCase();
    prefs.putString("node_id", NODE_ID);
  }
  prefs.end();
}

// =====================================================
//  電池讀取（與 rescue.ino 一致）
// =====================================================

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

  if (voltage < 2.5 || voltage > 4.5) return;  // 超出鋰電池合理範圍

  if (batteryVoltage < 1.0) {
    batteryVoltage = voltage;
  } else {
    batteryVoltage = batteryVoltage * 0.85 + voltage * 0.15;
  }
  float pct = (batteryVoltage - VBAT_EMPTY) / (VBAT_FULL - VBAT_EMPTY) * 100.0;
  batteryPercent = (int)constrain(pct, 0, 100);
  batteryLow = (batteryVoltage < VBAT_LOW_WARN);
}

// =====================================================
//  Garmin BLE Heart Rate Profile 客戶端
//  使用標準 BLE HRP (Heart Rate Service 0x180D)
//  支援所有廣播 HRP 的 Garmin 裝置（Forerunner/Fenix/Instinct 等）
//  未連線時退回模擬心率（不中斷 LoRa 封包）
// =====================================================

// Heart Rate Measurement 通知回調
void onHRNotify(BLERemoteCharacteristic* /*pChr*/, uint8_t* data, size_t len, bool /*isNotify*/) {
  if (len < 2) return;
  uint16_t hr;
  // Flags byte: bit0 = 0 → 8-bit value，bit0 = 1 → 16-bit value
  if ((data[0] & 0x01) && len >= 3) {
    hr = data[1] | ((uint16_t)data[2] << 8);
  } else {
    hr = data[1];
  }
  currentHeartRate = (int)constrain(hr, 20, 250);
  lastGarminHR = millis();
  Serial.printf("[BLE] HR: %d\n", (int)currentHeartRate);
}

// BLE 掃描回調：尋找廣播 Heart Rate Service 或名稱含 "Garmin" 的裝置
class HRScanCallbacks : public BLEAdvertisedDeviceCallbacks {
  void onResult(BLEAdvertisedDevice dev) override {
    Serial.printf("[BLE-SCAN] name='%s' addr=%s type=%d rssi=%d\n",
                  dev.getName().c_str(), dev.getAddress().toString().c_str(),
                  dev.getAddressType(), dev.getRSSI());

    bool matched = false;
    // 方法 1：Service UUID 匹配
    if (dev.haveServiceUUID() && dev.isAdvertisingService(hrServiceUUID)) {
      Serial.println("[BLE-SCAN] Matched by UUID 0x180D");
      matched = true;
    }
    // 方法 2：裝置名稱含 "Garmin" 或常見 HR 設備名稱
    if (!matched && dev.haveName()) {
      String name = dev.getName().c_str();
      name.toLowerCase();
      if (name.indexOf("garmin") >= 0 || name.indexOf("polar") >= 0 ||
          name.indexOf("wahoo") >= 0 || name.indexOf("tickr") >= 0 ||
          name.indexOf("coospo") >= 0 || name.indexOf("hr") >= 0 ||
          name.indexOf("heartrate") >= 0 || name.indexOf("heart") >= 0) {
        Serial.printf("[BLE-SCAN] Matched by name '%s'\n", dev.getName().c_str());
        matched = true;
      }
    }
    if (matched) {
      garminAddr     = dev.getAddress();
      garminAddrType = dev.getAddressType();
      garminFound    = true;
      BLEDevice::getScan()->stop();
    }
  }
};

void onScanComplete(BLEScanResults /*results*/) {
  scanInProgress = false;
}

// =====================================================
//  BLE 初始化（只執行一次）
// =====================================================

void setupBLE() {
  if (bleReady) return;
  BLEDevice::init("");
  bleScan = BLEDevice::getScan();
  bleScan->setAdvertisedDeviceCallbacks(new HRScanCallbacks(), false);
  bleScan->setInterval(100);
  bleScan->setWindow(99);
  bleScan->setActiveScan(true);
  bleReady = true;
}

bool connectGarmin() {
  Serial.printf("[BLE] Connecting to %s (addrType=%d)...\n",
                garminAddr.toString().c_str(), garminAddrType);
  if (bleClient == nullptr) {
    bleClient = BLEDevice::createClient();
  }
  // 使用正確的位址類型連線（Garmin 通常用 RANDOM 位址）
  if (!bleClient->connect(garminAddr, garminAddrType)) {
    Serial.println("[BLE] Connect failed");
    return false;
  }
  Serial.println("[BLE] Connected, discovering services...");

  // 列出所有服務（除錯用）
  auto* svcMap = bleClient->getServices();
  if (svcMap) {
    for (auto& entry : *svcMap) {
      Serial.printf("[BLE]   Svc: %s\n", entry.first.c_str());
    }
  }

  BLERemoteService* hrSvc = bleClient->getService(hrServiceUUID);
  if (!hrSvc) {
    Serial.println("[BLE] HR Service 0x180D NOT FOUND");
    bleClient->disconnect();
    return false;
  }
  Serial.println("[BLE] Heart Rate Service found");

  BLERemoteCharacteristic* hrChar = hrSvc->getCharacteristic(hrMeasCharUUID);
  if (!hrChar) {
    Serial.println("[BLE] HR char 0x2A37 NOT FOUND");
    bleClient->disconnect();
    return false;
  }
  Serial.printf("[BLE] HR char: canNotify=%d canIndicate=%d\n",
                hrChar->canNotify(), hrChar->canIndicate());

  if (!hrChar->canNotify() && !hrChar->canIndicate()) {
    Serial.println("[BLE] HR char unusable");
    bleClient->disconnect();
    return false;
  }

  // 註冊本機回調（明確 true = notification 模式）
  hrChar->registerForNotify(onHRNotify, true);

  // 明確寫入 CCCD descriptor 啟用遠端通知
  BLERemoteDescriptor* cccd = hrChar->getDescriptor(BLEUUID((uint16_t)0x2902));
  if (cccd) {
    uint8_t val[] = {0x01, 0x00};
    cccd->writeValue(val, 2, true);
    Serial.println("[BLE] CCCD written: notifications ON");
  } else {
    Serial.println("[BLE] CCCD not found");
  }

  garminConnected = true;
  lastGarminHR    = millis();
  Serial.println("[BLE] === Garmin HR ACTIVE ===");
  return true;
}

// handleBLE() 只在 HR_MODE_GARMIN 時被呼叫
void handleBLE() {
  // 檢查掃描卡住：如果 scanInProgress 超過 BLE_SCAN_STUCK_MS 強制重置
  if (scanInProgress && (millis() - lastBLEScan > BLE_SCAN_STUCK_MS)) {
    Serial.println("[BLE] Scan stuck, forcing reset");
    bleScan->stop();
    scanInProgress = false;
    doScan = true;
  }

  // 檢查連線狀態，斷線則重新掃描
  if (garminConnected) {
    bool alive = bleClient && bleClient->isConnected() &&
                 (millis() - lastGarminHR < GARMIN_TIMEOUT_MS);
    if (!alive) {
      garminConnected = false;
      garminFound     = false;
      doScan          = true;
      if (bleClient && bleClient->isConnected()) bleClient->disconnect();
      Serial.println("[BLE] Garmin disconnected, will retry scan");
    }
    return;
  }
  // 找到裝置地址 → 連線
  if (garminFound) {
    garminFound    = false;
    scanInProgress = false;
    connectGarmin();
    return;
  }
  // 定期重新掃描（非阻塞）
  if (!scanInProgress && (doScan || millis() - lastBLEScan > BLE_SCAN_INTERVAL)) {
    lastBLEScan    = millis();
    doScan         = false;
    scanInProgress = true;
    bleScan->clearResults();
    bleScan->start(BLE_SCAN_DURATION, onScanComplete, false);
    Serial.println("[BLE] Scanning for Garmin HR device...");
  }
}

// =====================================================
//  模式切換
// =====================================================

void startSimMode() {
  // 停止並清理 BLE（若正在運作）
  if (garminConnected && bleClient && bleClient->isConnected()) {
    bleClient->disconnect();
  }
  if (scanInProgress && bleReady) {
    bleScan->stop();
  }
  garminConnected = false;
  garminFound     = false;
  scanInProgress  = false;
  doScan          = false;

  // 重置模擬心率
  initHeartRate();
  hrMode = HR_MODE_SIM;

  prefs.begin("victim-v", false);
  prefs.putString("hrmode", "sim");
  prefs.end();
  Serial.println("[MODE] Switched to SIM");
}

void startGarminMode() {
  setupBLE();  // 若尚未初始化則初始化
  garminConnected = false;
  garminFound     = false;
  doScan          = true;  // 立即觸發掃描
  scanInProgress  = false;
  hrMode          = HR_MODE_GARMIN;

  prefs.begin("victim-v", false);
  prefs.putString("hrmode", "garmin");
  prefs.end();
  Serial.println("[MODE] Switched to GARMIN");
}

void toggleHRMode() {
  if (hrMode == HR_MODE_SIM) {
    startGarminMode();
  } else {
    startSimMode();
  }
}

// =====================================================
//  心率模擬（HR_MODE_SIM 專用）
//  正常: 基線 65-85 ± 微波動 / SOS: 逐步升到 100-140
// =====================================================

void initHeartRate() {
  randomSeed(ESP.getEfuseMac() + millis());
  baseHeartRate    = random(65, 86);
  currentHeartRate = baseHeartRate;
  lastHRUpdate     = millis();
}

// 只在 HR_MODE_SIM 時呼叫
void updateSimHeartRate() {
  if (millis() - lastHRUpdate < HR_UPDATE_MS) return;
  lastHRUpdate = millis();

  if (isSOS) {
    int target = random(100, 141);
    currentHeartRate += (target > currentHeartRate) ? random(1, 4) : random(-2, 1);
    currentHeartRate = constrain(currentHeartRate, 90, 150);
  } else {
    int drift = random(-3, 4);
    currentHeartRate = constrain(baseHeartRate + drift, 50, 110);
  }
}

// 統一入口（loop 呼叫此函式）
void updateHeartRate() {
  if (hrMode == HR_MODE_SIM) {
    updateSimHeartRate();
  }
  // HR_MODE_GARMIN: 由 onHRNotify() BLE 回調直接更新 currentHeartRate
}

// =====================================================
//  CSMA/CA（與 rescue.ino 完全一致）
// =====================================================

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
  if (!cadDone) return true;
  if (!channelFree) {
    if (radio.getRSSI() < CSMA_RSSI_FLOOR) return true;
  }
  return channelFree;
}

bool csmaBackoff() {
  int be = CSMA_MIN_BE;
  for (int retry = 0; retry < CSMA_MAX_RETRY; retry++) {
    if (isChannelFree()) return true;
    int slots = random(0, (1 << be));
    delay(slots * CSMA_SLOT_TIME);
    if (be < CSMA_MAX_BE) be++;
  }
  return false;
}

// =====================================================
//  封包去重
// =====================================================

bool isDuplicate(String id) {
  for (int i = 0; i < 10; i++)
    if (seenIds[i] == id) return true;
  return false;
}

void markSeen(String id) {
  seenIds[seenIdx] = id;
  seenIdx = (seenIdx + 1) % 10;
}

// =====================================================
//  省電功能
// =====================================================

void adjustTxPower() {
  if (lastRxRSSI > -70) {
    radio.setOutputPower(14);
  } else if (lastRxRSSI > -90) {
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

// =====================================================
//  LoRa 封包發送
//  格式: pktId|pairCode|VT-XXX|SOS|B85|BPM72
//        pktId|pairCode|VT-XXX|ACK|B85|BPM72
//  必須匹配 rescue.ino loop() 的解析邏輯
// =====================================================

void sendVictimPing() {
  if (!csmaBackoff()) return;

  String pktId  = String(random(0xFFFF), HEX);
  String type   = isSOS ? "SOS" : "ACK";
  String packet = pktId + "|" + pairCode + "|" + NODE_ID + "|" + type +
                  "|B" + String(batteryPercent) +
                  "|BPM" + String((int)currentHeartRate);

  radio.clearDio1Action();
  radio.standby();
  delay(5);
  int state = radio.transmit(packet);
  if (state == RADIOLIB_ERR_NONE) {
    const char* hrSrc = (hrMode == HR_MODE_GARMIN)
      ? (garminConnected ? "Garmin" : "Garmin(searching)")
      : "Sim";
    Serial.printf("[TX] %s %s HR:%d BAT:%d%% [%s]\n",
                  NODE_ID.c_str(), type.c_str(),
                  (int)currentHeartRate, batteryPercent, hrSrc);
    digitalWrite(LED_BUILTIN, HIGH);
    delay(50);
    digitalWrite(LED_BUILTIN, LOW);
  }
  radio.setDio1Action(onRxFlag);
  radio.startReceive(RADIOLIB_SX126X_RX_TIMEOUT_INF);
}

// =====================================================
//  PRG 按鍵（Heltec WiFi LoRa 32 V3: GPIO 0, active LOW）
//    短按 (300ms ~ 2s)  → SOS 開關
//    長按 (>= 2 s)      → 切換 HR 模式 (Sim ↔ Garmin)
//    < 300ms 彈跳       → 忽略
// =====================================================

void checkSOSButton() {
  bool currentState = digitalRead(0);

  // 按下前緣：無條件更新計時（確保長按從本次按下開始計算）
  if (currentState == LOW && lastButtonState == HIGH) {
    pressStartMs = millis();
    pressHandled = false;
  }

  // 持續按住：長按觸發（只觸發一次）
  if (currentState == LOW && !pressHandled &&
      (millis() - pressStartMs) >= LONG_PRESS_MS) {
    pressHandled = true;
    toggleHRMode();
    wakeOLED();
  }

  // 放開後緣：短按 = SOS（過濾 < DEBOUNCE_MS 的彈跳）
  if (currentState == HIGH && lastButtonState == LOW) {
    unsigned long dur = millis() - pressStartMs;
    if (dur >= DEBOUNCE_MS && !pressHandled) {
      isSOS = !isSOS;
      wakeOLED();
      Serial.println(isSOS ? "[SOS] >>> ACTIVATED <<<" : "[SOS] Cancelled");
    }
    pressHandled = false;
  }

  lastButtonState = currentState;
}

// =====================================================
//  OLED 顯示
// =====================================================

void updateDisplay() {
  display.clear();
  display.setFont(ArialMT_Plain_10);

  // 標題列
  String pairStr = "[" + pairCode + "]";
  display.drawString(0, 0, pairStr + " " + NODE_ID);
  if (isSOS) {
    String sosStr = "SOS!";
    display.drawString(128 - display.getStringWidth(sosStr), 0, sosStr);
  }

  // 心率（大字體）
  display.setFont(ArialMT_Plain_24);
  int hr = (int)currentHeartRate;  // volatile 讀取一次
  if (hr > 0) {
    display.drawString(0, 12, String(hr) + " bpm");
  } else {
    display.drawString(0, 12, "-- bpm");
  }

  // 狀態列：SOS 狀態 + HR 模式標籤
  display.setFont(ArialMT_Plain_10);
  String hrSource;
  if (hrMode == HR_MODE_GARMIN) {
    hrSource = garminConnected ? "[Garmin OK]" : "[Garmin...]";  // 搜尋中
  } else {
    hrSource = "[Sim]";
  }
  String sosStr = isSOS ? "!! SOS !!" : "Normal";
  display.drawString(0, 38, sosStr + " " + hrSource);

  // 搜救端偵測（10 秒內有收到 RESCUE ping）
  bool rescueNearby = (millis() - lastRescueRx < 10000);
  display.drawString(0, 49, rescueNearby ? "Rescue nearby" : "No rescue signal");

  // 電量
  String batStr = String(batteryPercent) + "% " + String(batteryVoltage, 2) + "V";
  display.drawString(128 - display.getStringWidth(batStr), 49, batStr);

  // 長按進度條：底部 4px，顯示切換模式的進度
  if (digitalRead(0) == LOW && !pressHandled && pressStartMs > 0) {
    unsigned long held = millis() - pressStartMs;
    if (held >= DEBOUNCE_MS) {
      int barW = (int)min(held * 128UL / LONG_PRESS_MS, 128UL);
      display.fillRect(0, 60, barW, 4);
    }
  }

  display.display();
}

// =====================================================
//  setup()
// =====================================================

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
  display.drawString(0, 0, "Victim v1.0");
  display.display();

  generateNodeID();
  display.drawString(0, 10, "ID: " + NODE_ID);
  display.display();

  readBattery();
  initHeartRate();
  pinMode(LED_BUILTIN, OUTPUT);
  pinMode(0, INPUT_PULLUP); // PRG button

  // Watchdog（與 rescue.ino 一致）
  esp_task_wdt_init(WDT_TIMEOUT, true);
  esp_task_wdt_add(NULL);

  // LoRa 初始化
  display.drawString(0, 20, "Radio Init...");
  display.display();
  int16_t state = radio.begin();
  if (state != RADIOLIB_ERR_NONE) {
    display.drawString(0, 30, "Radio FAIL!");
    display.display();
    while (1) delay(1000);
  }
  display.drawString(0, 30, "Radio OK");
  display.display();

  radio.setDio1Action(onRxFlag);

  // LoRa L4 設定（與 rescue.ino 預設一致）
  radio.setFrequency(RF_FREQ);
  radio.setOutputPower(22);
  radio.setSpreadingFactor(LORA_SF);
  radio.setBandwidth(LORA_BW);
  radio.setCodingRate(LORA_CR);
  radio.startReceive(RADIOLIB_SX126X_RX_TIMEOUT_INF);

  display.drawString(0, 40, "LoRa Ready (L4)");
  display.display();

  // 載入已儲存的 HR 模式
  prefs.begin("victim-v", true);
  String savedMode = prefs.getString("hrmode", "sim");
  prefs.end();
  if (savedMode == "garmin") {
    startGarminMode();
  } else {
    startSimMode();
  }

  Serial.println("[BOOT] Victim node: " + NODE_ID + " Pair: " + pairCode);
  Serial.println("[INFO] Serial 指令: pair:XXXX | mode:sim | mode:garmin");
  Serial.println("[INFO] 按鍵: 短按=SOS, 長按 2s=切換 HR 模式");
  Serial.println("[MODE] HR mode: " + savedMode);
  lastInteraction = millis();
  bootTime = millis();
  delay(1500);
  updateDisplay();
}

// =====================================================
//  loop()
// =====================================================

void loop() {
  heltec_loop();
  esp_task_wdt_reset();

  // 1. 檢查 SOS 按鍵
  checkSOSButton();

  // 1.2 處理 Garmin BLE（只在 Garmin 模式下運作）
  if (hrMode == HR_MODE_GARMIN) {
    handleBLE();
  }

  // 1.5 檢查 Serial 指令
  if (Serial.available()) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    if (cmd.startsWith("pair:")) {
      String p = cmd.substring(5);
      p.toUpperCase();
      if (p.length() >= 1 && p.length() <= 8) {
        pairCode = p;
        prefs.begin("victim-v", false);
        prefs.putString("pair", pairCode);
        prefs.end();
        Serial.println("[PAIR] -> " + pairCode);
      }
    } else if (cmd == "mode:sim") {
      startSimMode();
    } else if (cmd == "mode:garmin") {
      startGarminMode();
    }
  }

  // 2. 更新心率
  updateHeartRate();

  // 3. 接收搜救端的 RESCUE ping
  if (rxFlag) {
    rxFlag = false;
    String packet;
    int state = radio.readData(packet);

    if (state == RADIOLIB_ERR_NONE && packet.length() > 0) {
      int sep1 = packet.indexOf('|');
      int sep2 = packet.indexOf('|', sep1 + 1);
      int sep3 = packet.indexOf('|', sep2 + 1);
      int sep4 = packet.indexOf('|', sep3 + 1);

      if (sep1 > 0 && sep2 > 0 && sep3 > 0 && sep4 > 0) {
        String pId    = packet.substring(0, sep1);
        String rxPair = packet.substring(sep1 + 1, sep2);
        String sender = packet.substring(sep2 + 1, sep3);
        String type   = packet.substring(sep3 + 1, sep4);

        // 配對碼過濾
        if (rxPair != pairCode) {
          radio.startReceive(RADIOLIB_SX126X_RX_TIMEOUT_INF);
          return;
        }

        if (!isDuplicate(pId) && type == "RESCUE") {
          markSeen(pId);
          lastRescueRx = millis();
          lastRxRSSI = radio.getRSSI();
          wakeOLED();
          Serial.println("[RX] Rescue ping from: " + sender);
          // LED 閃爍確認搜救端在範圍內
          digitalWrite(LED_BUILTIN, HIGH);
          delay(100);
          digitalWrite(LED_BUILTIN, LOW);
        }
      }
    }
    radio.startReceive(RADIOLIB_SX126X_RX_TIMEOUT_INF);
  }

  // 4. 定期發送受困者封包（SOS=3s, 正常=15s）
  unsigned long pingInterval = isSOS ? PING_INTERVAL_SOS : PING_INTERVAL_NORMAL;
  if (millis() - lastPing >= pingInterval) {
    lastPing = millis();
    readBattery();
    adjustTxPower();
    sendVictimPing();
  }

  // 5. 更新 OLED 顯示
  if (millis() - lastDisplayUpdate >= 500) {
    lastDisplayUpdate = millis();
    if (oledOn) updateDisplay();
  }

  // 6. OLED 自動關閉（30 秒無互動）
  if (oledOn && millis() - lastInteraction > OLED_AUTO_OFF_MS) {
    display.displayOff();
    oledOn = false;
  }

  // 7. 省電：非 SOS 模式下，TX 後 1 秒關閉 radio（下次 TX 前 standby 喚醒）
  if (!isSOS && millis() - lastPing > 1000) {
    radio.sleep();
  }
}
