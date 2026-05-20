package com.linkguard.hq.ble

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONObject
import java.util.UUID

// BLE UUIDs matching HQ LoRa firmware
object HQLoRaBLE {
    val SERVICE_UUID: UUID      = UUID.fromString("4FAFC201-1FB5-459E-8FCC-C5C9C331915B")
    val STATUS_UUID: UUID       = UUID.fromString("BEB5483E-36E1-4688-B7F5-EA07361B26B8")
    val COMMAND_UUID: UUID      = UUID.fromString("BEB5483E-36E1-4688-B7F5-EA07361B26BB")
    val LORA_COMMAND_UUID: UUID = UUID.fromString("BEB5483E-36E1-4688-B7F5-EA07361B26BC")
    val CCCD_UUID: UUID         = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
}

data class HQLoRaNode(
    val id: String,
    val bat: Int,
    val rssi: Double,
    val snr: Double,
    val online: Boolean
)

data class HQLoRaStatus(
    val id: String,
    val freq: Double,
    val bat: Int,
    val vbat: Double,
    val lvl: Int,
    val pair: String,
    val uptime: Int,
    val hqNodes: List<HQLoRaNode>,
    val cmdCount: Int
)

data class HQDiscoveredDevice(
    val address: String,
    val name: String,
    val rssi: Int
)

@SuppressLint("MissingPermission")
class HQBluetoothManager(private val context: Context) {

    private val _isScanning = MutableStateFlow(false)
    val isScanning: StateFlow<Boolean> = _isScanning

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected

    private val _isPoweredOn = MutableStateFlow(false)
    val isPoweredOn: StateFlow<Boolean> = _isPoweredOn

    private val _discoveredDevices = MutableStateFlow<List<HQDiscoveredDevice>>(emptyList())
    val discoveredDevices: StateFlow<List<HQDiscoveredDevice>> = _discoveredDevices

    private val _connectedDeviceName = MutableStateFlow<String?>(null)
    val connectedDeviceName: StateFlow<String?> = _connectedDeviceName

    private val _loraStatus = MutableStateFlow<HQLoRaStatus?>(null)
    val loraStatus: StateFlow<HQLoRaStatus?> = _loraStatus

    var onStatusUpdate: ((HQLoRaStatus) -> Unit)? = null
    var onLoRaCommand: ((String) -> Unit)? = null

    private val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    private val bluetoothAdapter: BluetoothAdapter? = bluetoothManager?.adapter
    private val scanner = bluetoothAdapter?.bluetoothLeScanner

    private var connectedGatt: BluetoothGatt? = null
    private var commandCharacteristic: BluetoothGattCharacteristic? = null
    private var targetDevice: BluetoothDevice? = null

    private var statusBuffer = StringBuilder()
    private var reconnectScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var reconnectDelay = 2000L
    private var reconnectJob: Job? = null

    init {
        _isPoweredOn.value = bluetoothAdapter?.isEnabled == true
    }

    // Scanning

    fun startScanning() {
        if (scanner == null || bluetoothAdapter?.isEnabled != true) return
        _isScanning.value = true
        _discoveredDevices.value = emptyList()

        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(HQLoRaBLE.SERVICE_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        scanner.startScan(listOf(filter), settings, scanCallback)
    }

    fun stopScanning() {
        try { scanner?.stopScan(scanCallback) } catch (_: Exception) {}
        _isScanning.value = false
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            val address = device.address
            val current = _discoveredDevices.value
            if (current.none { it.address == address }) {
                _discoveredDevices.value = current + HQDiscoveredDevice(
                    address = address,
                    name = device.name ?: "HQ LoRa",
                    rssi = result.rssi
                )
            }
        }
    }

    // Connection

    fun connect(device: HQDiscoveredDevice) {
        stopScanning()
        connectedGatt?.close()
        val btDevice = bluetoothAdapter?.getRemoteDevice(device.address) ?: return
        targetDevice = btDevice
        reconnectGatt(btDevice)
    }

    private fun reconnectGatt(btDevice: BluetoothDevice) {
        btDevice.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
    }

    fun disconnect() {
        reconnectJob?.cancel()
        reconnectDelay = 2000L
        targetDevice = null
        connectedGatt?.disconnect()
        connectedGatt?.close()
        connectedGatt = null
        _isConnected.value = false
        _connectedDeviceName.value = null
        _loraStatus.value = null
        commandCharacteristic = null
    }

    // Send commands

    fun sendLevelChange(level: Int) = sendBLE("setlvl:$level")
    fun sendPairChange(pair: String) = sendBLE("setpair:$pair")
    fun sendCommand(cmdId: String, type: String, priority: Int, title: String, detail: String) =
        sendBLE("cmd:$cmdId:$type:$priority:$title:$detail")
    fun sendBroadcast(msgType: String, payload: String) = sendBLE("broadcast:$msgType:$payload")

    private fun sendBLE(text: String) {
        val char = commandCharacteristic ?: return
        val gatt = connectedGatt ?: return
        char.value = text.toByteArray(Charsets.UTF_8)
        gatt.writeCharacteristic(char)
    }

    fun destroy() {
        reconnectJob?.cancel()
        reconnectScope.cancel()
        disconnect()
    }

    // GATT callback

    private val gattCallback: BluetoothGattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    connectedGatt = gatt
                    _isConnected.value = true
                    _connectedDeviceName.value = gatt.device.name ?: "HQ LoRa"
                    reconnectJob?.cancel()
                    reconnectDelay = 2000L
                    gatt.discoverServices()
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    _isConnected.value = false
                    commandCharacteristic = null
                    _loraStatus.value = null
                    statusBuffer.clear()
                    // Auto-reconnect with exponential backoff (2s → 60s)
                    if (targetDevice != null) {
                        reconnectJob?.cancel()
                        reconnectJob = reconnectScope.launch {
                            delay(reconnectDelay)
                            reconnectDelay = (reconnectDelay * 2).coerceAtMost(60000L)
                            targetDevice?.let { reconnectGatt(it) }
                        }
                    }
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) return
            val service = gatt.getService(HQLoRaBLE.SERVICE_UUID) ?: return

            service.getCharacteristic(HQLoRaBLE.STATUS_UUID)?.let { char ->
                gatt.setCharacteristicNotification(char, true)
                char.getDescriptor(HQLoRaBLE.CCCD_UUID)?.let { desc ->
                    desc.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    gatt.writeDescriptor(desc)
                }
            }

            service.getCharacteristic(HQLoRaBLE.COMMAND_UUID)?.let { char ->
                commandCharacteristic = char
            }

            service.getCharacteristic(HQLoRaBLE.LORA_COMMAND_UUID)?.let { char ->
                gatt.setCharacteristicNotification(char, true)
                char.getDescriptor(HQLoRaBLE.CCCD_UUID)?.let { desc ->
                    desc.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    gatt.writeDescriptor(desc)
                }
            }
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            val data = characteristic.value ?: return
            val text = String(data, Charsets.UTF_8)

            when (characteristic.uuid) {
                HQLoRaBLE.STATUS_UUID -> {
                    if (text.startsWith("{")) {
                        statusBuffer.clear()
                        statusBuffer.append(text)
                    } else {
                        statusBuffer.append(text)
                    }
                    // Try to parse complete JSON
                    val json = statusBuffer.toString()
                    if (json.contains("}")) {
                        try {
                            val parsed = parseLoRaStatus(json)
                            _loraStatus.value = parsed
                            onStatusUpdate?.invoke(parsed)
                            statusBuffer.clear()
                        } catch (_: Exception) {
                            // Incomplete JSON, wait for more data
                        }
                    }
                }
                HQLoRaBLE.LORA_COMMAND_UUID -> {
                    onLoRaCommand?.invoke(text)
                }
            }
        }
    }

    private fun parseLoRaStatus(json: String): HQLoRaStatus {
        val obj = JSONObject(json)
        val nodesArray = obj.optJSONArray("hqNodes") ?: org.json.JSONArray()
        val nodes = mutableListOf<HQLoRaNode>()
        for (i in 0 until nodesArray.length()) {
            val n = nodesArray.getJSONObject(i)
            nodes.add(HQLoRaNode(
                id = n.optString("id", ""),
                bat = n.optInt("bat", 0),
                rssi = n.optDouble("rssi", 0.0),
                snr = n.optDouble("snr", 0.0),
                online = n.optBoolean("online", false)
            ))
        }
        return HQLoRaStatus(
            id = obj.optString("id", ""),
            freq = obj.optDouble("freq", 0.0),
            bat = obj.optInt("bat", 0),
            vbat = obj.optDouble("vbat", 0.0),
            lvl = obj.optInt("lvl", 0),
            pair = obj.optString("pair", ""),
            uptime = obj.optInt("uptime", 0),
            hqNodes = nodes,
            cmdCount = obj.optInt("cmdCount", 0)
        )
    }
}
