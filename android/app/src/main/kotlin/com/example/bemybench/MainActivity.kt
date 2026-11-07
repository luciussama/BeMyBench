package com.example.bemybench

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val BATTERY_CHANNEL = "bemybench/battery"
    private val PLATFORM_CHANNEL = "bemybench/platform"
    private val SENSORS_CHANNEL = "bemybench/sensors"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Canal de Bateria
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "get_battery") {
                val batteryData = getBatteryData()
                if (batteryData != null) {
                    result.success(batteryData)
                } else {
                    result.error("UNAVAILABLE", "Dados da bateria não disponíveis", null)
                }
            } else {
                result.notImplemented()
            }
        }

        // 2. Canal de Plataforma / Hardware
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLATFORM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "get_hardware" -> {
                    result.success(getHardwareData())
                }
                "hasTouchscreen" -> {
                    // Dispositivos Android possuem tela touch nativa
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 3. Canal de Sensores em Tempo Real
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SENSORS_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "get_sensors") {
                result.success(getSensorsData())
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getBatteryData(): Map<String, Any>? {
        val intentFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val batteryStatus = context.registerReceiver(null, intentFilter) ?: return null

        val level: Int = batteryStatus.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale: Int = batteryStatus.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        val percentage: Int = if (level >= 0 && scale > 0) (level * 100) / scale else level

        val status: Int = batteryStatus.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val isCharging: Boolean = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL

        val plugged: Int = batteryStatus.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1)
        val externalConnected: Boolean = plugged > 0

        val voltage: Int = batteryStatus.getIntExtra(BatteryManager.EXTRA_VOLTAGE, 0)
        val temperatureRaw: Int = batteryStatus.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0)
        val temperatureC: Double = temperatureRaw / 10.0

        val healthCode: Int = batteryStatus.getIntExtra(BatteryManager.EXTRA_HEALTH, BatteryManager.BATTERY_HEALTH_UNKNOWN)
        val healthLabel: String = when (healthCode) {
            BatteryManager.BATTERY_HEALTH_GOOD -> "Boa (Íntegra)"
            BatteryManager.BATTERY_HEALTH_OVERHEAT -> "Superaquecimento"
            BatteryManager.BATTERY_HEALTH_DEAD -> "Esgotada"
            BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "Sobretensão"
            BatteryManager.BATTERY_HEALTH_COLD -> "Baixa temperatura"
            else -> "Normal"
        }

        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        var chargeCounterUah = 0
        var cycleCount = 0

        if (batteryManager != null) {
            chargeCounterUah = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)
            if (Build.VERSION.SDK_INT >= 34) {
                try {
                    // BatteryManager.BATTERY_PROPERTY_CYCLE_COUNT = 7 no Android 14+
                    cycleCount = batteryManager.getIntProperty(7)
                    if (cycleCount < 0) cycleCount = 0
                } catch (_: Exception) {}
            }
        }

        val currentCapacityMah = if (chargeCounterUah > 0) chargeCounterUah / 1000 else 0
        // Estimativa padrão caso designCapacity não seja exposto diretamente por HAL de terceiros
        val estimatedDesignCapacity = if (currentCapacityMah > 0 && percentage > 0) {
            (currentCapacityMah * 100) / percentage
        } else {
            5000 // Capacidade de bateria padrão típica da linha Galaxy S / smartphones modernos (mAh)
        }

        return mapOf(
            "percentage" to percentage,
            "cycleCount" to cycleCount,
            "designCapacity" to estimatedDesignCapacity,
            "maxCapacity" to estimatedDesignCapacity,
            "currentCapacity" to if (currentCapacityMah > 0) currentCapacityMah else (estimatedDesignCapacity * percentage) / 100,
            "voltage" to voltage,
            "isCharging" to isCharging,
            "externalConnected" to externalConnected,
            "temperatureC" to temperatureC,
            "healthStatus" to healthLabel
        )
    }

    private fun getHardwareData(): Map<String, Any> {
        val actManager = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        actManager?.getMemoryInfo(memInfo)

        val statFs = StatFs(Environment.getDataDirectory().path)
        val storageTotalBytes = statFs.totalBytes
        val storageFreeBytes = statFs.availableBytes

        val soc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Build.SOC_MODEL
        } else {
            Build.HARDWARE
        }

        return mapOf(
            "manufacturer" to Build.MANUFACTURER.replaceFirstChar { it.uppercase() },
            "model" to Build.MODEL,
            "brand" to Build.BRAND.replaceFirstChar { it.uppercase() },
            "device" to Build.DEVICE,
            "board" to Build.BOARD,
            "hardware" to Build.HARDWARE,
            "socModel" to (if (soc.isNullOrEmpty()) Build.HARDWARE else soc),
            "osRelease" to "Android ${Build.VERSION.RELEASE}",
            "sdkInt" to Build.VERSION.SDK_INT,
            "cores" to Runtime.getRuntime().availableProcessors(),
            "ramTotalBytes" to memInfo.totalMem,
            "ramFreeBytes" to memInfo.availMem,
            "storageTotalBytes" to storageTotalBytes,
            "storageFreeBytes" to storageFreeBytes
        )
    }

    private fun getSensorsData(): Map<String, Any> {
        val actManager = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        actManager?.getMemoryInfo(memInfo)

        val totalRam = memInfo.totalMem
        val usedRam = totalRam - memInfo.availMem

        // Leitura de temperatura da bateria como proxy térmico confiável no Android
        val intentFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val batteryStatus: Intent? = context.registerReceiver(null, intentFilter)
        val tempRaw = batteryStatus?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
        val tempC = if (tempRaw > 0) tempRaw / 10.0 else null

        var thermalState = "Nominal"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            when (powerManager?.currentThermalStatus) {
                PowerManager.THERMAL_STATUS_NONE -> thermalState = "Nominal"
                PowerManager.THERMAL_STATUS_LIGHT -> thermalState = "Leve"
                PowerManager.THERMAL_STATUS_MODERATE -> thermalState = "Moderado"
                PowerManager.THERMAL_STATUS_SEVERE -> thermalState = "Severo (Throttling)"
                PowerManager.THERMAL_STATUS_CRITICAL -> thermalState = "Crítico"
                PowerManager.THERMAL_STATUS_EMERGENCY -> thermalState = "Emergência"
                PowerManager.THERMAL_STATUS_SHUTDOWN -> thermalState = "Desligamento"
            }
        }

        return mapOf(
            "ram_total" to totalRam,
            "ram_used" to usedRam,
            "cpu_temp" to (tempC ?: 0.0),
            "gpu_temp" to (tempC ?: 0.0),
            "has_fan" to false,
            "fan_status" to "Passivo (Câmara de vapor)",
            "thermal_state" to thermalState
        )
    }
}
