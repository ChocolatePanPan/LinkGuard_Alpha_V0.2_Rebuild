// =====================================================
//  LinkGuard HQ — LoRa 指揮中心韌體
//  頻率: 912 MHz（與救援/受困端 910 MHz 分離，避免干擾）
//  硬體: Heltec WiFi LoRa 32 V3
//  功能: 透過 BLE 連接 HQ App，發送指揮命令至其他 HQ 節點
// =====================================================

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
#define PING_INTERVAL 5000
#define BLE_NOTIFY_INTERVAL 2000

// === BLE UUID（HQ 專用，與 Field 端不同以避免混淆）===
#define SERVICE_UUID        "4FAFC201-1FB5-459E-8FCC-C5C9C331915B"
#define STATUS_CHAR_UUID    "BEB5483E-36E1-4688-B7F5-EA07361B26B8"
#define COMMAND_CHAR_UUID   "BEB5483E-36E1-4688-B7F5-EA07361B26BB"
#define LORA_CMD_CHAR_UUID  "BEB5483E-36E1-4688-B7F5-EA07361B26BC"

// === HQ LoRa 頻率：912 MHz ===
static const float RF_FREQ = 912.0;
static const int CSMA_MIN_BE = 2;
static const int CSMA_MAX_BE = 4;
static const int CSMA_MAX_RETRY = 3;
static const int CSMA_SLOT_TIME = 5;
static const int CSMA_CAD_TIMEOUT = 30;
static const float CSMA_RSSI_FLOOR = -100.0;

// === LoRa Profiles ===
struct LoRaProfile {
  int sf;
  float bw;
  int cr;
  String label;
};
LoRaProfile profiles[9] = {
    {7, 500.0, 5, "L0:極速"},
    {7, 250.0, 5, "L1:高速"},
    {8, 250.0, 5, "L2:敏捷"},
    {9, 250.0, 6, "L3:平衡"},
    {9, 125.0, 6, "L4:標準"},   // <-- 預設
    {10, 125.0, 7, "L5:穿透"},
    {10, 62.5, 8, "L6:強穿"},
    {11, 62.5, 8, "L7:極限"},
    {12, 62.5, 8, "L8:最遠"}
};
int curLvl = 4;

String NODE_ID = "";
String pairCode = "HQ00";  // HQ 配對碼（與 Field 不同）
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

// === HQ 節點追蹤（其他 HQ LoRa 裝置）===
struct HQNode {
  String id;
  int battery;
  float rssi;
  float snr;
  unsigned long lastSeen;
};
HQNode hqNodes[10];
int hqNodeCount = 0;

// === 命令歷史記錄 ===
struct CmdRecord {
  String cmdId;
  String title;
  unsigned long time;
};
CmdRecord cmdHistory[20];
int cmdHistoryCount = 0;

// === BLE 全域變數 ===
BLEServer *pServer = NULL;
BLECharacteristic *pStatusChar = NULL;
BLECharacteristic *pCommandChar = NULL;
BLECharacteristic *pLoRaCmdChar = NULL;
bool bleDeviceConnected = false;
bool bleOldConnected = false;
unsigned long lastBLENotify = 0;

// === Serial 命令緩衝 ===
String serialBuffer = "";

String seenIds[20];
int seenIdx = 0;

void generateNodeID() {
  prefs.begin("hq-node", false);
  String savedID = prefs.getString("node_id", "");
  pairCode = prefs.getString("pair", "HQ00");
  if (savedID.length() > 0) {
    NODE_ID = savedID;
  } else {
    randomSeed(ESP.getEfuseMac() + millis());
    uint16_t id = random(0x100, 0xFFF);
    String base = "HQ-" + String(id, HEX);
    base.toUpperCase();
    prefs.putString("node_id", base);
    NODE_ID = base;
  }
  prefs.end();
}

void readBattery() {
  float samples[5];
  for (int i = 0; i < 5; i++) {
    samples[i] = heltec_vbat();
    delay(2);
  }
  for (int i = 0; i < 4; i++)
    for (int j = i + 1; j < 5; j++)
      if (samples[j] < samples[i]) { float t = samples[i]; samples[i] = samples[j]; samples[j] = t; }
  float voltage = samples[2];
  if (voltage < 2.5 || voltage > 4.5) return;
  if (batteryVoltage < 1.0) {
    batteryVoltage = voltage;
  } else {
    batteryVoltage = batteryVoltage * 0.85 + voltage * 0.15;
  }
  float pct = (batteryVoltage - VBAT_EMPTY) / (VBAT_FULL - VBAT_EMPTY) * 100.0;
  batteryPercent = (int)constrain(pct, 0, 100);
  batteryLow = (batteryVoltage < VBAT_LOW_WARN);
}

void setLevel(int l) {
  if (l < 0) l = 0;
  if (l > 8) l = 8;
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
  while (!cadDone && (millis() - start < CSMA_CAD_TIMEOUT)) delay(1);
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

bool isDuplicate(String id) {
  for (int i = 0; i < 20; i++)
    if (seenIds[i] == id) return true;
  return false;
}

void markSeen(String id) {
  seenIds[seenIdx] = id;
  seenIdx = (seenIdx + 1) % 20;
}

void updateHQNode(String id, int bat, float rssi, float snr) {
  unsigned long now = millis();
  for (int i = 0; i < hqNodeCount; i++) {
    if (hqNodes[i].id == id) {
      hqNodes[i].battery = bat;
      hqNodes[i].rssi = rssi;
      hqNodes[i].snr = snr;
      hqNodes[i].lastSeen = now;
      return;
    }
  }
  if (hqNodeCount < 10) {
    hqNodes[hqNodeCount] = {id, bat, rssi, snr, now};
    hqNodeCount++;
  }
}

void addCmdHistory(String cmdId, String title) {
  if (cmdHistoryCount < 20) {
    cmdHistory[cmdHistoryCount] = {cmdId, title, millis()};
    cmdHistoryCount++;
  } else {
    for (int i = 0; i < 19; i++) cmdHistory[i] = cmdHistory[i + 1];
    cmdHistory[19] = {cmdId, title, millis()};
  }
}

// === HQ Ping（廣播自身存在）===
void sendHQPing() {
  String pktId = String(random(0xFFFF), HEX);
  String packet = pktId + "|" + pairCode + "|" + NODE_ID + "|HQPING|B" + String(batteryPercent);
  radio.clearDio1Action();
  radio.standby();
  delay(5);
  radio.transmit(packet);
  radio.setDio1Action(onRxFlag);
  radio.startReceive(RADIOLIB_SX126X_RX_TIMEOUT_INF);
}

// === 發送 LoRa 指揮命令（HQ → HQ 節點間廣播）===
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
    addCmdHistory(cmdId, title);
    notifyBLECommand(cmdId, type, pri, title, detail, NODE_ID);
  } else {
    Serial.println("[TX-CMD] FAIL: " + String(state));
  }
}

// === 發送 LoRa 廣播訊息（HQ → HQ 節點間通訊）===
void sendLoRaBroadcast(String msgType, String payload) {
  String pktId = String(random(0xFFFF), HEX);
  String packet = pktId + "|" + pairCode + "|" + NODE_ID + "|" + msgType + "|" + payload;
  if (!csmaBackoff()) return;
  radio.clearDio1Action();
  radio.standby();
  delay(5);
  radio.transmit(packet);
  radio.setDio1Action(onRxFlag);
  radio.startReceive(RADIOLIB_SX126X_RX_TIMEOUT_INF);
  Serial.println("[TX] " + msgType + ": " + payload);
}

void notifyBLECommand(String cmdId, String type, int pri, String title, String detail, String sender) {
  if (!bleDeviceConnected || !pLoRaCmdChar) return;
  String json = "{\"cmd_id\":\"" + cmdId + "\",\"type\":\"" + type +
                "\",\"pri\":" + String(pri) +
                ",\"title\":\"" + title +
                "\",\"detail\":\"" + detail +
                "\",\"sender\":\"" + sender + "\"}";
  pLoRaCmdChar->setValue(json.c_str());
  pLoRaCmdChar->notify();
}

// === 處理 Serial 命令（Mac HQ App 直接 USB 連線）===
void processSerialCommand(String line) {
  line.trim();
  if (line.startsWith("CMD:")) {
    String payload = line.substring(4);
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
    Serial.println(buildStatusJSON());
  } else if (line == "PING") {
    Serial.println("PONG:" + NODE_ID);
  } else if (line.startsWith("SETPAIR:")) {
    String p = line.substring(8);
    p.toUpperCase();
    if (p.length() >= 1 && p.length() <= 8) {
      pairCode = p;
      prefs.begin("hq-node", false);
      prefs.putString("pair", pairCode);
      prefs.end();
      Serial.println("OK:PAIR=" + pairCode);
    }
  } else if (line.startsWith("SETLVL:")) {
    int l = line.substring(7).toInt();
    setLevel(l);
    Serial.println("OK:LVL=" + String(curLvl));
  } else if (line.startsWith("BROADCAST:")) {
    // 格式: BROADCAST:msgType:payload
    String data = line.substring(10);
    int s1 = data.indexOf(':');
    if (s1 > 0) {
      String msgType = data.substring(0, s1);
      String payload = data.substring(s1 + 1);
      sendLoRaBroadcast(msgType, payload);
      Serial.println("OK:BROADCAST");
    }
  }
}

String buildStatusJSON() {
  String j = "{";
  j += "\"id\":\"" + NODE_ID + "\",";
  j += "\"freq\":" + String(RF_FREQ, 1) + ",";
  j += "\"bat\":" + String(batteryPercent) + ",";
  j += "\"vbat\":" + String(batteryVoltage, 2) + ",";
  j += "\"lvl\":" + String(curLvl) + ",";
  j += "\"pair\":\"" + pairCode + "\",";
  j += "\"uptime\":" + String((millis() - bootTime) / 1000) + ",";
  j += "\"hqNodes\":[";
  unsigned long now = millis();
  bool first = true;
  for (int i = 0; i < hqNodeCount; i++) {
    bool online = (now - hqNodes[i].lastSeen < 30000);
    if (!first) j += ",";
    first = false;
    j += "{\"id\":\"" + hqNodes[i].id + "\"";
    j += ",\"bat\":" + String(hqNodes[i].battery);
    j += ",\"rssi\":" + String(hqNodes[i].rssi, 0);
    j += ",\"snr\":" + String(hqNodes[i].snr, 1);
    j += ",\"online\":" + String(online ? "true" : "false");
    j += "}";
  }
  j += "],\"cmdCount\":" + String(cmdHistoryCount);
  j += "}";
  return j;
}

void updateDisplay() {
  display.clear();
  display.setFont(ArialMT_Plain_10);

  display.drawString(0, 0, "[HQ] " + NODE_ID);
  String info = pairCode + " L" + String(curLvl) + " " + String(RF_FREQ, 0) + "MHz";
  display.drawString(128 - display.getStringWidth(info), 0, info);

  display.setFont(ArialMT_Plain_16);
  String freqStr = String(RF_FREQ, 1) + " MHz";
  display.drawString(0, 14, freqStr);

  display.setFont(ArialMT_Plain_10);

  // 顯示 HQ 節點數量
  String nodeStr = "HQ Nodes: " + String(hqNodeCount);
  display.drawString(0, 32, nodeStr);

  String cmdStr = "Cmds sent: " + String(cmdHistoryCount);
  display.drawString(0, 42, cmdStr);

  // 電池與 BLE
  String batStr = String(batteryPercent) + "% " + String(batteryVoltage, 2) + "V";
  if (bleDeviceConnected) batStr += " [BLE]";
  display.drawString(128 - display.getStringWidth(batStr), 52, batStr);

  display.display();
}

// === BLE 回呼 ===
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) { bleDeviceConnected = true; }
  void onDisconnect(BLEServer *pServer) { bleDeviceConnected = false; }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    String val = pChar->getValue().c_str();
    if (val.startsWith("setlvl:")) {
      int l = val.substring(7).toInt();
      setLevel(l);
      Serial.println("[BLE] Level -> L" + String(curLvl));
    } else if (val.startsWith("setpair:")) {
      String p = val.substring(8);
      p.toUpperCase();
      if (p.length() >= 1 && p.length() <= 8) {
        pairCode = p;
        prefs.begin("hq-node", false);
        prefs.putString("pair", pairCode);
        prefs.end();
        Serial.println("[BLE] Pair -> " + pairCode);
      }
    } else if (val.startsWith("cmd:")) {
      // 格式: cmd:cmdId:type:pri:title:detail
      String payload = val.substring(4);
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
      }
    } else if (val.startsWith("broadcast:")) {
      // 格式: broadcast:msgType:payload
      String data = val.substring(10);
      int s1 = data.indexOf(':');
      if (s1 > 0) {
        String msgType = data.substring(0, s1);
        String payload = data.substring(s1 + 1);
        sendLoRaBroadcast(msgType, payload);
      }
    }
  }
};

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
  display.drawString(0, 0, "HQ LoRa v1.0");
  display.drawString(0, 10, String(RF_FREQ, 1) + " MHz");
  display.display();

  generateNodeID();
  display.drawString(0, 20, "ID: " + NODE_ID);
  display.display();

  readBattery();
  pinMode(LED_BUILTIN, OUTPUT);

  esp_task_wdt_init(WDT_TIMEOUT, true);
  esp_task_wdt_add(NULL);

  display.drawString(0, 30, "Radio Init...");
  display.display();
  int16_t state = radio.begin();
  if (state != RADIOLIB_ERR_NONE) {
    display.drawString(0, 40, "Radio FAIL!");
    display.display();
    while (1) delay(1000);
  }
  display.drawString(0, 40, "Radio OK @ 912MHz");
  display.display();

  radio.setDio1Action(onRxFlag);
  setLevel(4);

  // === BLE 初始化 ===
  BLEDevice::init(NODE_ID.c_str());
  BLEDevice::setMTU(517);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  pStatusChar = pService->createCharacteristic(
      STATUS_CHAR_UUID, BLECharacteristic::PROPERTY_READ |
                          BLECharacteristic::PROPERTY_NOTIFY);
  pStatusChar->addDescriptor(new BLE2902());

  pCommandChar = pService->createCharacteristic(
      COMMAND_CHAR_UUID, BLECharacteristic::PROPERTY_WRITE);
  pCommandChar->setCallbacks(new CommandCallbacks());

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

  Serial.println("[HQ-BLE] Ready: " + NODE_ID + " @ " + String(RF_FREQ, 1) + "MHz");

  display.clear();
  display.drawString(0, 50, "Ready");
  display.display();
  bootTime = millis();
  delay(1500);
  updateDisplay();
}

void loop() {
  heltec_loop();
  esp_task_wdt_reset();

  // === 接收 LoRa 封包 ===
  if (rxFlag) {
    rxFlag = false;
    String packet;
    int state = radio.readData(packet);

    if (state == RADIOLIB_ERR_NONE && packet.length() > 0) {
      lastRSSI = radio.getRSSI();
      lastSNR = radio.getSNR();
      lastRxTime = millis();

      Serial.printf("[RX-RAW] RSSI:%.0f SNR:%.1f -> %s\n",
                    lastRSSI, lastSNR,
                    packet.substring(0, min((int)packet.length(), 80)).c_str());

      int sep1 = packet.indexOf('|');
      int sep2 = packet.indexOf('|', sep1 + 1);
      int sep3 = packet.indexOf('|', sep2 + 1);
      int sep4 = packet.indexOf('|', sep3 + 1);

      if (sep1 > 0 && sep2 > 0 && sep3 > 0) {
        String pId = packet.substring(0, sep1);
        String rxPair = packet.substring(sep1 + 1, sep2);
        String sender = packet.substring(sep2 + 1, sep3);
        String type = (sep4 > 0) ? packet.substring(sep3 + 1, sep4)
                                 : packet.substring(sep3 + 1);

        // 配對碼過濾
        if (rxPair != pairCode) {
          Serial.printf("[RX] Pair mismatch: got '%s' expect '%s'\n",
                        rxPair.c_str(), pairCode.c_str());
          radio.startReceive(RADIOLIB_SX126X_RX_TIMEOUT_INF);
          return;
        }

        // === HQPING: 其他 HQ 節點心跳 ===
        if (!isDuplicate(pId) && type == "HQPING" && sender != NODE_ID) {
          markSeen(pId);
          int batIdx = packet.indexOf("|B", sep4 > 0 ? sep4 : sep3);
          int bat = 0;
          if (batIdx > 0) {
            String batStr = packet.substring(batIdx + 2);
            int nextPipe = batStr.indexOf('|');
            if (nextPipe > 0) batStr = batStr.substring(0, nextPipe);
            bat = batStr.toInt();
          }
          updateHQNode(sender, bat, lastRSSI, lastSNR);
          Serial.printf("[RX-HQ] %s BAT:%d%% RSSI:%.0f\n", sender.c_str(), bat, lastRSSI);
        }

        // === CMD: 來自其他 HQ 節點的命令 ===
        if (!isDuplicate(pId) && type == "CMD" && sender != NODE_ID && sep4 > 0) {
          markSeen(pId);
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
            notifyBLECommand(cmdId, cmdType, cmdPri, cmdTitle, cmdDetail, sender);
            Serial.println("CMD_RX:" + cmdId + ":" + cmdType + ":" +
                           String(cmdPri) + ":" + cmdTitle + ":" + cmdDetail +
                           ":" + sender);
          }
        }
      }
    }
    radio.startReceive(RADIOLIB_SX126X_RX_TIMEOUT_INF);
  }

  // === 定期 HQ Ping ===
  if (millis() - lastPing >= PING_INTERVAL) {
    lastPing = millis();
    readBattery();
    sendHQPing();
  }

  // === 更新顯示 ===
  if (millis() - lastDisplayUpdate >= 1000) {
    lastDisplayUpdate = millis();
    updateDisplay();
  }

  // === BLE Notify ===
  if (bleDeviceConnected && (millis() - lastBLENotify >= BLE_NOTIFY_INTERVAL)) {
    lastBLENotify = millis();
    String statusJson = buildStatusJSON();
    pStatusChar->setValue(statusJson.c_str());
    pStatusChar->notify();
  }

  // === Serial ===
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (serialBuffer.length() > 0) {
        processSerialCommand(serialBuffer);
        serialBuffer = "";
      }
    } else {
      serialBuffer += c;
      if (serialBuffer.length() > 256) serialBuffer = "";
    }
  }

  // BLE 斷線重新廣播
  if (!bleDeviceConnected && bleOldConnected) {
    delay(500);
    pServer->startAdvertising();
    Serial.println("[BLE] Restart advertising");
  }
  bleOldConnected = bleDeviceConnected;

  // 清理超時 HQ 節點（120 秒）
  unsigned long now = millis();
  for (int i = hqNodeCount - 1; i >= 0; i--) {
    if (now - hqNodes[i].lastSeen > 120000) {
      for (int j = i; j < hqNodeCount - 1; j++) hqNodes[j] = hqNodes[j + 1];
      hqNodeCount--;
    }
  }
}
