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
import com.example.bemybench.gpu.GpuBenchmarkChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Activity principal do BMyBench no Android.
 *
 * Registra os canais nativos de bateria, plataforma/hardware, sensores e GPU.
 * O canal `bemybench/gpu` (OpenGL ES) fornece as informações da GPU, o
 * benchmark de compute/render e a visualização 3D ao vivo com HUD.
 */
class MainActivity : FlutterActivity() {
    private val BATTERY_CHANNEL = "bemybench/battery"
    private val PLATFORM_CHANNEL = "bemybench/platform"
    private val SENSORS_CHANNEL = "bemybench/sensors"

    // Amostra anterior de /proc/stat para calcular a carga por núcleo.
    private var previousCoreTotal: LongArray = LongArray(0)
    private var previousCoreIdle: LongArray = LongArray(0)

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
            when (call.method) {
                "get_sensors" -> result.success(getSensorsData())
                "get_cpu_cores" -> result.success(getCpuCores())
                else -> result.notImplemented()
            }
        }

        // 4. Canal de GPU (OpenGL ES): benchmark de compute/render e visualização 3D
        GpuBenchmarkChannel.attach(flutterEngine.dartExecutor.binaryMessenger, this)
    }

    override fun onDestroy() {
        GpuBenchmarkChannel.detach()
        super.onDestroy()
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

        // Zonas térmicas do kernel: CPU e GPU separadas quando o vendor expõe.
        val zones = readThermalZones()

        // Bateria como último recurso (proxy térmico confiável no Android).
        val intentFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val batteryStatus: Intent? = context.registerReceiver(null, intentFilter)
        val tempRaw = batteryStatus?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
        val batteryTempC: Double? = if (tempRaw > 0) tempRaw / 10.0 else null

        val cpuTemp = zones.first ?: batteryTempC
        // GPU só é reportada quando existe uma zona térmica dedicada; usar a
        // bateria como "GPU" seria enganoso.
        val gpuTemp = zones.second
        val zoneSource = zones.third
        val cpuSource = when {
            zones.first != null -> zoneSource
            batteryTempC != null -> "bateria"
            else -> ""
        }
        val gpuSource = if (zones.second != null) zoneSource else ""

        var thermalState = "Nominal"
        var thermalHeadroom: Double? = null
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                val value = powerManager?.getThermalHeadroom(10)
                if (value != null && !value.isNaN() && value > 0f) {
                    thermalHeadroom = value.toDouble()
                }
            } catch (_: Throwable) {
                // Nem todo aparelho implementa o headroom térmico.
            }
        }

        return mapOf(
            "ram_total" to totalRam,
            "ram_used" to usedRam,
            "cpu_temp" to (cpuTemp ?: 0.0),
            "gpu_temp" to (gpuTemp ?: 0.0),
            "cpu_temp_source" to cpuSource,
            "gpu_temp_source" to gpuSource,
            "thermal_headroom" to (thermalHeadroom ?: -1.0),
            "has_fan" to false,
            "fan_status" to "Passivo (Câmara de vapor)",
            "thermal_state" to thermalState
        )
    }

    /**
     * Carga por núcleo lógico (0-100) lida de /proc/stat.
     *
     * Android 12+ bloqueia `/proc/stat` para apps via SELinux em muitas ROMs.
     * Nesse caso devolvemos a frequência atual de cada núcleo (`mode =
     * frequency`), que continua legível e é um indicador real de atividade por
     * núcleo — sem nunca inventar percentuais de uso.
     */
    private fun getCpuCores(): Map<String, Any> {
        val loads = readPerCoreLoads()
        if (loads.isNotEmpty()) {
            return mapOf(
                "mode" to "load",
                "core_count" to loads.size,
                "loads" to loads,
            )
        }

        val freqs = readPerCoreFrequencies()
        val maxFreq = readMaxFrequency(freqs)
        return mapOf(
            "mode" to if (freqs.isEmpty()) "unavailable" else "frequency",
            "core_count" to freqs.size,
            "loads" to emptyList<Double>(),
            "frequencies" to freqs,
            "freq_max_mhz" to maxFreq,
        )
    }

    private fun readPerCoreLoads(): List<Double> {
        val text = try {
            java.io.File("/proc/stat").readText()
        } catch (_: Throwable) {
            return emptyList()
        }

        val totals = ArrayList<Long>()
        val idles = ArrayList<Long>()
        for (line in text.lineSequence()) {
            // "cpu " é a linha agregada; "cpuN ..." são os núcleos.
            if (!line.startsWith("cpu") || line.startsWith("cpu ")) continue
            val parts = line.trim().split(Regex("\\s+"))
            if (parts.size < 5) continue
            val values = parts.drop(1).mapNotNull { it.toLongOrNull() }
            if (values.size < 4) continue
            // user nice system idle iowait irq softirq steal
            val slice = values.take(8)
            val idle = slice[3] + (slice.getOrNull(4) ?: 0L)
            totals.add(slice.sum())
            idles.add(idle)
        }
        if (totals.isEmpty()) return emptyList()

        val baselineTotal = previousCoreTotal
        val baselineIdle = previousCoreIdle
        previousCoreTotal = totals.toLongArray()
        previousCoreIdle = idles.toLongArray()
        // Primeira amostra (ou topologia mudou): ainda não há taxa.
        if (baselineTotal.size != totals.size) return emptyList()

        return totals.indices.map { index ->
            val deltaTotal = totals[index] - baselineTotal[index]
            val deltaIdle = idles[index] - baselineIdle[index]
            if (deltaTotal <= 0L) {
                0.0
            } else {
                val busy = (deltaTotal - deltaIdle).coerceAtLeast(0L).toDouble()
                (busy / deltaTotal.toDouble() * 100.0).coerceIn(0.0, 100.0)
            }
        }
    }

    /** Frequência atual de cada núcleo em MHz (ordem cpu0..cpuN). */
    private fun readPerCoreFrequencies(): List<Double> {
        val base = java.io.File("/sys/devices/system/cpu")
        val cores = base.listFiles { file ->
            Regex("cpu\\d+").matches(file.name)
        } ?: return emptyList()

        return cores
            .sortedBy { it.name.removePrefix("cpu").toIntOrNull() ?: Int.MAX_VALUE }
            .mapNotNull { core ->
                val khz = try {
                    java.io.File(core, "cpufreq/scaling_cur_freq")
                        .readText().trim().toLongOrNull()
                } catch (_: Throwable) {
                    null
                }
                khz?.let { it / 1000.0 }
            }
    }

    /** Frequência máxima de referência (MHz) para normalizar as barras. */
    private fun readMaxFrequency(observed: List<Double>): Double {
        val declared = try {
            java.io.File("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq")
                .readText().trim().toDoubleOrNull()
                ?.div(1000.0)
        } catch (_: Throwable) {
            null
        }
        val fallback = observed.maxOrNull() ?: 0.0
        return declared?.takeIf { it > 0 } ?: fallback
    }

    /**
     * Temperaturas de CPU e GPU a partir de `/sys/class/thermal`.
     *
     * Devolve (cpu, gpu, origem). O Android reporta milésimos de grau na
     * maioria dos kernels; valores > 1000 são normalizados.
     */
    private fun readThermalZones(): Triple<Double?, Double?, String> {
        var cpu: Double? = null
        var gpu: Double? = null
        var soc: Double? = null

        val zones = java.io.File("/sys/class/thermal").listFiles() ?: emptyArray()
        for (zone in zones) {
            if (!zone.name.startsWith("thermal_zone")) continue
            val type = try {
                java.io.File(zone, "type").readText().trim().lowercase()
            } catch (_: Throwable) {
                continue
            }
            val raw = try {
                java.io.File(zone, "temp").readText().trim().toDoubleOrNull()
            } catch (_: Throwable) {
                null
            } ?: continue

            val celsius = if (raw > 1000.0) raw / 1000.0 else raw
            if (celsius <= 0.0 || celsius > 200.0) continue

            when {
                type.contains("gpu") || type.contains("g3d") ->
                    gpu = maxOf(gpu ?: celsius, celsius)
                type.contains("cpu") || type.contains("core") ||
                    type.contains("cluster") || type.contains("silver") ||
                    type.contains("gold") ->
                    cpu = maxOf(cpu ?: celsius, celsius)
                type.contains("soc") || type.contains("tsens") ||
                    type.contains("board") || type.contains("ap") ->
                    soc = maxOf(soc ?: celsius, celsius)
            }
        }

        val cpuTemp = cpu ?: soc
        val gpuTemp = gpu ?: soc
        val source = if (cpuTemp != null || gpuTemp != null) "zona térmica" else ""
        return Triple(cpuTemp, gpuTemp, source)
    }
}
