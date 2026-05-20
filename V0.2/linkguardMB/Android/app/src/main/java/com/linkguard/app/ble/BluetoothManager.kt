package com.linkguard.app.ble

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.ParcelUuid
import com.linkguard.app.model.FirmwareLoRaCommand
import com.linkguard.app.model.FirmwareStatusResponse
import com.linkguard.app.model.FirmwareVictim
import com.linkguard.app.model.FirmwareTeamNode
import com.linkguard.app.model.FirmwareReinforcement
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONObject
import java.util.*
import java.util.LinkedList
import java.util.Queue

// === BLE 常數（對應韌體 rescue.ino UUID）===

object LinkGuardBLE {
    val SERVICE_UUID: UUID      = UUID.fromString("4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
    val STATUS_CHAR_UUID: UUID  = UUID.fromString("BEB5483E-36E1-4688-B7F5-EA07361B26A8")
    val COMMAND_CHAR_UUID: UUID = UUID.fromString("BEB5483E-36E1-4688-B7F5-EA07361B26AB")
    val LORA_CMD_CHAR_UUID: UUID = UUID.fromString("BEB5483E-36E1-4688-B7F5-EA07361B26AC")
    val CCCD_UUID: UUID         = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
}

// === 已發現的裝置 ===

data class DiscoveredDevice(
    val address: String,
    val name: String,
    val rssi: Int,
    val device: BluetoothDevice
)

// === JSON 解析 ===

object BLEDataParser {
    fun parseStatusJSON(data: ByteArray): FirmwareStatusResponse? {
        return try {
            val json = JSONObject(String(data, Charsets.UTF_8))
            val id = if (json.has("id")) json.getString("id") else null
            val dept = if (json.has("dept")) json.getString("dept") else null
            val bat = json.getInt("bat")
            val vbat = if (json.has("vbat")) json.getDouble("vbat") else null
            val lvl = json.getInt("lvl")
            val pair = if (json.has("pair")) json.getString("pair") else null
            val victimsArray = json.getJSONArray("victims")
            val victims = mutableListOf<FirmwareVictim>()
            for (i in 0 until victimsArray.length()) {
                val v = victimsArray.getJSONObject(i)
                victims.add(
                    FirmwareVictim(
                        id = v.getString("id"),
                        hr = v.getInt("hr"),
                        bat = v.getInt("bat"),
                        rssi = v.getDouble("rssi"),
                        dist = if (v.has("dist")) v.getString("dist") else null,
                        snr = if (v.has("snr")) v.getDouble("snr") else null,
                        sos = v.getBoolean("sos"),
                        online = v.getBoolean("online")
                    )
                )
            }

            // 團隊節點
            val team = if (json.has("team")) {
                val teamArray = json.getJSONArray("team")
                (0 until teamArray.length()).map { i ->
                    val t = teamArray.getJSONObject(i)
                    FirmwareTeamNode(
                        id = t.getString("id"),
                        dept = t.getString("dept"),
                        bat = t.getInt("bat"),
                        rssi = t.getDouble("rssi"),
                        vc = t.getInt("vc"),
                        online = t.getBoolean("online")
                    )
                }
            } else null

            // 增援請求
            val rf = if (json.has("rf")) {
                val rfArray = json.getJSONArray("rf")
                (0 until rfArray.length()).map { i ->
                    val r = rfArray.getJSONObject(i)
                    FirmwareReinforcement(
                        from = r.getString("from"),
                        msg = r.getString("msg"),
                        loc = r.getString("loc"),
                        ago = r.getInt("ago")
                    )
                }
            } else null

            FirmwareStatusResponse(id, dept, bat, vbat, lvl, pair, victims, team, rf)
        } catch (e: Exception) {
            null
        }
    }

    fun encodeDeptCommand(dept: String): ByteArray = "setdept:$dept".toByteArray(Charsets.UTF_8)
    fun encodeLevelCommand(level: Int): ByteArray = "setlvl:$level".toByteArray(Charsets.UTF_8)
    fun encodePairCommand(pair: String): ByteArray = "setpair:$pair".toByteArray(Charsets.UTF_8)
    fun encodeReinforcementCommand(message: String, location: String): ByteArray =
        "reinforce:$message|$location".toByteArray(Charsets.UTF_8)
    fun encodeReinforcementReply(team: String, accept: Boolean): ByteArray =
        "rf_reply:$team|${if (accept) "JOIN" else "NAK"}".toByteArray(Charsets.UTF_8)
    fun encodeTeamPing(): ByteArray = "team_ping".toByteArray(Charsets.UTF_8)
    fun encodeCommandAck(commandID: String): ByteArray = "cmd_ack:$commandID".toByteArray(Charsets.UTF_8)

    fun parseLoRaCommand(data: ByteArray): FirmwareLoRaCommand? {
        return try {
            val json = JSONObject(String(data, Charsets.UTF_8))
            FirmwareLoRaCommand(
                cmd_id = json.getString("cmd_id"),
                type = json.getString("type"),
                pri = json.optInt("pri", 0),
                title = json.getString("title"),
                detail = json.getString("detail"),
                sender = json.getString("sender")
            )
        } catch (e: Exception) {
            null
        }
    }
}

// === 藍牙管理器 ===

@SuppressLint("MissingPermission")
class BluetoothManager(private val context: Context) {

    private val bluetoothAdapter: BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as android.bluetooth.BluetoothManager).adapter

    private var scanner: BluetoothLeScanner? = null
    private var gatt: BluetoothGatt? = null
    private var commandCharacteristic: BluetoothGattCharacteristic? = null

    private val _isScanning = MutableStateFlow(false)
    val isScanning: StateFlow<Boolean> = _isScanning

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected

    private val _isPoweredOn = MutableStateFlow(false)
    val isPoweredOn: StateFlow<Boolean> = _isPoweredOn

    private val _discoveredDevices = MutableStateFlow<List<DiscoveredDevice>>(emptyList())
    val discoveredDevices: StateFlow<List<DiscoveredDevice>> = _discoveredDevices

    private val _connectedDeviceName = MutableStateFlow<String?>(null)
    val connectedDeviceName: StateFlow<String?> = _connectedDeviceName

    var onStatusUpdate: ((FirmwareStatusResponse) -> Unit)? = null
    var onLoRaCommand: ((String) -> Unit)? = null

    // BLE JSON 累積緩衝區（處理 MTU 截斷）
    private var statusBuffer = ByteArray(0)
    private var statusBufferTimestamp = 0L

    // 排隊 descriptor 寫入（Android 一次只能一個 BLE 操作）
    private val descriptorQueue: Queue<BluetoothGattDescriptor> = LinkedList()
    private var isWritingDescriptor = false

    init {
        _isPoweredOn.value = bluetoothAdapter?.isEnabled == true
    }

    // MARK: 掃描

    fun startScanning() {
        if (bluetoothAdapter?.isEnabled != true) return
        scanner = bluetoothAdapter.bluetoothLeScanner ?: return
        _isScanning.value = true
        _discoveredDevices.value = emptyList()

        val filters = listOf(
            ScanFilter.Builder()
                .setServiceUuid(ParcelUuid(LinkGuardBLE.SERVICE_UUID))
                .build()
        )
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_POWER)
            .build()

        scanner?.startScan(filters, settings, scanCallback)
    }

    fun stopScanning() {
        scanner?.stopScan(scanCallback)
        _isScanning.value = false
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            val address = device.address
            val current = _discoveredDevices.value
            if (current.none { it.address == address }) {
                _discoveredDevices.value = current + DiscoveredDevice(
                    address = address,
                    name = device.name ?: "未知裝置",
                    rssi = result.rssi,
                    device = device
                )
            }
        }
    }

    // MARK: 連線

    fun connect(device: DiscoveredDevice) {
        stopScanning()
        val newGatt = device.device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        if (newGatt == null) {
            android.util.Log.e("BLE", "connectGatt returned null for ${device.device.address}")
            _isConnected.value = false
            return
        }
        gatt = newGatt
    }

    fun disconnect() {
        gatt?.disconnect()
        gatt?.close()
        gatt = null
        _isConnected.value = false
        _connectedDeviceName.value = null
        commandCharacteristic = null
    }

    // MARK: 發送指令

    fun sendDeptChange(dept: String) {
        val char = commandCharacteristic ?: return
        val g = gatt ?: return
        char.value = BLEDataParser.encodeDeptCommand(dept)
        g.writeCharacteristic(char)
    }

    fun sendLevelChange(level: Int) {
        val char = commandCharacteristic ?: return
        val g = gatt ?: return
        char.value = BLEDataParser.encodeLevelCommand(level)
        g.writeCharacteristic(char)
    }

    fun sendPairChange(pair: String) {
        val char = commandCharacteristic ?: return
        val g = gatt ?: return
        char.value = BLEDataParser.encodePairCommand(pair)
        g.writeCharacteristic(char)
    }

    fun sendReinforcement(message: String, location: String) {
        val char = commandCharacteristic ?: return
        val g = gatt ?: return
        char.value = BLEDataParser.encodeReinforcementCommand(message, location)
        g.writeCharacteristic(char)
    }

    fun sendReinforcementReply(team: String, accept: Boolean) {
        val char = commandCharacteristic ?: return
        val g = gatt ?: return
        char.value = BLEDataParser.encodeReinforcementReply(team, accept)
        g.writeCharacteristic(char)
    }

    fun sendTeamPing() {
        val char = commandCharacteristic ?: return
        val g = gatt ?: return
        char.value = BLEDataParser.encodeTeamPing()
        g.writeCharacteristic(char)
    }

    fun sendCommandAck(commandID: String) {
        val char = commandCharacteristic ?: return
        val g = gatt ?: return
        char.value = BLEDataParser.encodeCommandAck(commandID)
        g.writeCharacteristic(char)
    }

    // MARK: GATT 回呼

    private val gattCallback = object : BluetoothGattCallback() {

        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    _isConnected.value = true
                    _connectedDeviceName.value = g.device.name ?: "LinkGuard"
                    // 先請求大 MTU 再探索服務
                    g.requestMtu(512)
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    _isConnected.value = false
                    _connectedDeviceName.value = null
                    commandCharacteristic = null
                    statusBuffer = ByteArray(0)
                    gatt?.close()
                    gatt = null
                }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            android.util.Log.d("BLE", "MTU negotiated: $mtu (status=$status)")
            g.discoverServices()
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) return
            val service = g.getService(LinkGuardBLE.SERVICE_UUID) ?: return

            // 訂閱狀態 Notify（排隊 descriptor 寫入）
            service.getCharacteristic(LinkGuardBLE.STATUS_CHAR_UUID)?.let { statusChar ->
                g.setCharacteristicNotification(statusChar, true)
                statusChar.getDescriptor(LinkGuardBLE.CCCD_UUID)?.let { desc ->
                    desc.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    descriptorQueue.add(desc)
                }
            }

            // 保存 Command 特徵
            commandCharacteristic = service.getCharacteristic(LinkGuardBLE.COMMAND_CHAR_UUID)

            // 訂閱 LoRa Command Notify（排隊 descriptor 寫入）
            service.getCharacteristic(LinkGuardBLE.LORA_CMD_CHAR_UUID)?.let { loraChar ->
                g.setCharacteristicNotification(loraChar, true)
                loraChar.getDescriptor(LinkGuardBLE.CCCD_UUID)?.let { desc ->
                    desc.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    descriptorQueue.add(desc)
                }
            }

            // 開始寫入 descriptor 佇列
            writeNextDescriptor(g)
        }

        override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            android.util.Log.d("BLE", "Descriptor write status=$status for ${descriptor.characteristic.uuid}")
            isWritingDescriptor = false
            writeNextDescriptor(g)
        }

        override fun onCharacteristicChanged(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic
        ) {
            if (characteristic.uuid == LinkGuardBLE.STATUS_CHAR_UUID) {
                val data = characteristic.value ?: return
                android.util.Log.d("BLE", "Status notify: ${data.size} bytes")

                // 累積 BLE 資料（處理 MTU 截斷導致 JSON 不完整的情況）
                // 韌體每次 notify 都是完整 JSON，但可能被 BLE 截斷
                // 檢測策略：如果 data 以 '{' 開頭，清空舊緩衝重新累積
                if (data.isNotEmpty() && data[0] == '{'.code.toByte()) {
                    statusBuffer = data
                    statusBufferTimestamp = System.currentTimeMillis()
                } else {
                    statusBuffer = statusBuffer + data
                }

                // 嘗試解析完整 JSON
                val parsed = BLEDataParser.parseStatusJSON(statusBuffer)
                if (parsed != null) {
                    statusBuffer = ByteArray(0)
                    onStatusUpdate?.invoke(parsed)
                } else if (statusBuffer.size > 4096 ||
                    System.currentTimeMillis() - statusBufferTimestamp > 3000) {
                    // 緩衝區過大或超時，放棄
                    android.util.Log.w("BLE", "Status buffer overflow/timeout (${statusBuffer.size} bytes), clearing")
                    statusBuffer = ByteArray(0)
                }
            } else if (characteristic.uuid == LinkGuardBLE.LORA_CMD_CHAR_UUID) {
                val data = characteristic.value ?: return
                onLoRaCommand?.invoke(String(data, Charsets.UTF_8))
            }
        }
    }

    private fun writeNextDescriptor(g: BluetoothGatt) {
        if (isWritingDescriptor) return
        val desc = descriptorQueue.poll() ?: return
        isWritingDescriptor = true
        g.writeDescriptor(desc)
    }
}
