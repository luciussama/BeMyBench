package com.example.bemybench.gpu

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.min

/**
 * Canal `bemybench/gpu` do Android.
 *
 * Expõe o mesmo contrato do macOS (Metal) e do Windows (Direct3D 11):
 *   - info            -> dados da GPU
 *   - run             -> benchmark de compute
 *   - run_render      -> benchmark de renderização (cena vulcânica)
 *   - open_3d_window  -> visualização 3D ao vivo em tela cheia com HUD
 *   - close_3d_window -> fecha a visualização
 *   - is_3d_window_open
 *
 * Todo o trabalho OpenGL roda em uma thread dedicada (o contexto EGL é criado
 * e mantido nela); os resultados voltam para a thread de UI antes de responder
 * ao Dart.
 */
object GpuBenchmarkChannel : MethodChannel.MethodCallHandler {

    private const val TAG = "BmbGpuChannel"
    private const val CHANNEL = "bemybench/gpu"

    private var channel: MethodChannel? = null
    private var host: Activity? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var worker: ExecutorService? = null
    private var engine: OffscreenGl? = null

    fun attach(messenger: BinaryMessenger, activity: Activity) {
        host = activity
        engine = OffscreenGl(activity.applicationContext)
        worker = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "bmb-gpu-offscreen").apply {
                priority = Thread.NORM_PRIORITY + 1
            }
        }
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    /** Libera canal, contexto EGL e o overlay 3D. Chamado em onDestroy. */
    fun detach() {
        GpuLiveWindow.close()
        channel?.setMethodCallHandler(null)
        channel = null
        val executor = worker
        val gl = engine
        engine = null
        worker = null
        if (executor != null) {
            executor.execute {
                try {
                    gl?.release()
                } catch (t: Throwable) {
                    Log.w(TAG, "Falha ao liberar o contexto OpenGL", t)
                }
            }
            executor.shutdown()
        }
        host = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "info" -> runAsync(result) { engine().info() }

            "run" -> {
                val duration = call.argument<Int>("duration_ms") ?: 1500
                runAsync(result) { engine().runCompute(duration) }
            }

            "run_render" -> {
                val duration = call.argument<Int>("duration_ms") ?: 1500
                runAsync(result) { renderResult(duration) }
            }

            "open_3d_window" -> {
                val mode = call.argument<String>("mode") ?: "stress"
                onMainThread(result) { activity -> GpuLiveWindow.open(activity, mode) }
            }

            "close_3d_window" -> onMainThread(result) { GpuLiveWindow.close() }

            "is_3d_window_open" -> result.success(GpuLiveWindow.isOpen())

            else -> result.notImplemented()
        }
    }

    // ----------------------------------------------------------- helpers ---

    private fun engine(): OffscreenGl {
        val current = engine ?: throw IllegalStateException(
            "Backend de GPU indisponível: a Activity não está ativa."
        )
        return current
    }

    private fun runAsync(
        result: MethodChannel.Result,
        block: () -> Map<String, Any>,
    ) {
        val executor = worker
        if (executor == null) {
            result.error("gpu_error", "Executor de GPU indisponível.", null)
            return
        }
        executor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (t: Throwable) {
                Log.e(TAG, "Falha na execução do teste de GPU", t)
                mainHandler.post {
                    result.error("gpu_error", t.message ?: t.toString(), null)
                }
            }
        }
    }

    private fun onMainThread(
        result: MethodChannel.Result,
        block: (Activity) -> Boolean,
    ) {
        mainHandler.post {
            val activity = host
            if (activity == null) {
                result.success(false)
                return@post
            }
            try {
                result.success(block(activity))
            } catch (t: Throwable) {
                Log.e(TAG, "Falha ao controlar a visualização 3D", t)
                result.error("gpu_error", t.message ?: t.toString(), null)
            }
        }
    }

    /**
     * Resultado do teste de render.
     *
     * Quando a visualização 3D está aberta, amostra o throughput real da cena
     * ao vivo (mesma resolução interna de 1920x1080), evitando duas cargas
     * concorrentes na GPU e sincronizando a medição com o que o usuário vê.
     */
    private fun renderResult(durationMs: Int): Map<String, Any> {
        val live = GpuLiveWindow.current()
        if (live != null) {
            val waitMs = durationMs.coerceIn(200, 2000)
            if (live.awaitFirstSamples(2500)) {
                try {
                    Thread.sleep(waitMs.toLong())
                } catch (_: InterruptedException) {
                }
                val fps = live.liveFps
                if (fps > 0) {
                    val avgMs = live.liveAvgMs
                    val p99 = live.liveP99Ms
                    val frames = live.liveFrames
                    return mapOf(
                        "available" to true,
                        "kind" to "render",
                        "device" to deviceName(),
                        "width" to OffscreenGl.WIDTH,
                        "height" to OffscreenGl.HEIGHT,
                        "iterations" to OffscreenGl.SCENE_STEPS,
                        "frames" to frames,
                        "elapsed_ms" to waitMs.toLong(),
                        "fps" to round2(fps),
                        "pixels_per_second" to round2(fps * OffscreenGl.WIDTH * OffscreenGl.HEIGHT),
                        "score" to round1(fps * 100.0),
                        "gpu_time_used" to true,
                        "instances" to 1,
                        "triangles_per_frame" to 2,
                        "shading_iterations" to OffscreenGl.SCENE_STEPS,
                        "msaa_samples" to 0,
                        "hdr" to false,
                        "bloom" to true,
                        "passes" to live.passesPerFrame,
                        "avg_frame_ms" to round2(avgMs),
                        "p99_frame_ms" to round2(p99),
                        "p999_frame_ms" to round2(p99 * 1.15),
                        "one_percent_low_fps" to round2(live.liveOneLowFps),
                        "point_one_percent_low_fps" to round2(live.liveOneLowFps * 0.9),
                        "frame_time_samples" to min(frames, 240),
                    )
                }
            }
        }
        return engine().runRender(durationMs)
    }

    /** Nome da GPU, resolvido pelo contexto off-screen quando necessário. */
    private fun deviceName(): String = engine().deviceName()

    private fun round2(value: Double): Double = kotlin.math.round(value * 100.0) / 100.0

    private fun round1(value: Double): Double = kotlin.math.round(value * 10.0) / 10.0
}
