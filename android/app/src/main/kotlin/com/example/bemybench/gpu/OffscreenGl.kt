package com.example.bemybench.gpu

import android.app.ActivityManager
import android.content.Context
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.round

/**
 * Backend off-screen de GPU do Android (EGL + OpenGL ES 2.0).
 *
 * Reproduz o mesmo contrato do canal `bemybench/gpu` usado no macOS (Metal) e
 * no Windows (Direct3D 11), devolvendo os mesmos campos de resultado:
 * fps, score, passes, frame times (p99 / 1% low) etc.
 *
 * Deve ser utilizado sempre na mesma thread (o contexto EGL é criado e mantido
 * corrente nela). O [GpuBenchmarkChannel] garante isso executando tudo em um
 * único executor.
 */
internal class OffscreenGl(private val context: Context) {

    private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var surface: EGLSurface = EGL14.EGL_NO_SURFACE
    private var config: EGLConfig? = null

    private var renderer: SceneRenderer? = null
    private var gpuName: String = "GPU"

    companion object {
        const val WIDTH = 1920
        const val HEIGHT = 1080

        /** Iterações do teste de compute (equivalente ao macOS). */
        const val COMPUTE_ITERATIONS = 48

        /** Passos de raymarching da cena volumétrica. */
        const val SCENE_STEPS = 32

        /** Passes do pipeline de render. */
        const val RENDER_PASSES = 5
    }

    // ---------------------------------------------------------------- EGL ---

    private fun ensureContext() {
        if (display != EGL14.EGL_NO_DISPLAY && eglContext != EGL14.EGL_NO_CONTEXT) return

        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        if (display == EGL14.EGL_NO_DISPLAY) {
            throw IllegalStateException("EGL indisponível neste dispositivo.")
        }

        val version = IntArray(2)
        if (!EGL14.eglInitialize(display, version, 0, version, 1)) {
            display = EGL14.EGL_NO_DISPLAY
            throw IllegalStateException("Falha ao inicializar o EGL.")
        }

        val configAttribs = intArrayOf(
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_DEPTH_SIZE, 0,
            EGL14.EGL_NONE
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfig = IntArray(1)
        if (!EGL14.eglChooseConfig(display, configAttribs, 0, configs, 0, 1, numConfig, 0) ||
            numConfig[0] == 0 ||
            configs[0] == null
        ) {
            throw IllegalStateException("Nenhum EGLConfig compatível com OpenGL ES 2.0.")
        }
        config = configs[0]

        eglContext = EGL14.eglCreateContext(
            display, config, EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0
        )
        if (eglContext == EGL14.EGL_NO_CONTEXT) {
            throw IllegalStateException(
                "Falha ao criar o contexto EGL (0x${Integer.toHexString(EGL14.eglGetError())})."
            )
        }

        val surfaceAttribs = intArrayOf(
            EGL14.EGL_WIDTH, 16,
            EGL14.EGL_HEIGHT, 16,
            EGL14.EGL_NONE
        )
        surface = EGL14.eglCreatePbufferSurface(display, config, surfaceAttribs, 0)
        if (surface == EGL14.EGL_NO_SURFACE) {
            throw IllegalStateException("Falha ao criar a superfície EGL off-screen.")
        }

        if (!EGL14.eglMakeCurrent(display, surface, surface, eglContext)) {
            throw IllegalStateException("Falha ao ativar o contexto OpenGL off-screen.")
        }

        val rendererName = GLES20.glGetString(GLES20.GL_RENDERER)?.trim()
        if (!rendererName.isNullOrEmpty()) {
            gpuName = rendererName
        }
    }

    private fun ensureRenderer(): SceneRenderer {
        ensureContext()
        val existing = renderer
        if (existing != null && existing.ready) return existing
        val created = SceneRenderer(WIDTH, HEIGHT)
        created.init()
        renderer = created
        return created
    }

    private fun memoryClassMb(): Int {
        return try {
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            manager.memoryClass
        } catch (_: Throwable) {
            0
        }
    }

    private fun vendorName(): String =
        GLES20.glGetString(GLES20.GL_VENDOR)?.trim() ?: "Desconhecido"

    private fun glVersion(): String =
        GLES20.glGetString(GLES20.GL_VERSION)?.trim() ?: "OpenGL ES"

    // ------------------------------------------------------------ métodos ---

    /** Nome da GPU; inicializa o contexto off-screen se ainda não existir. */
    fun deviceName(): String {
        ensureContext()
        return gpuName
    }

    /** Informações da GPU (mesmo contrato do backend macOS/Windows). */
    fun info(): Map<String, Any> {
        ensureContext()
        // Compila os shaders já no primeiro uso para confirmar o suporte.
        ensureRenderer()
        return mapOf(
            "available" to true,
            "render_available" to true,
            "name" to gpuName,
            "vendor" to vendorName(),
            "api" to glVersion(),
            "unified_memory" to true,
            "recommended_working_set_mb" to memoryClassMb(),
            "max_threads_per_group" to 0,
            "width" to WIDTH,
            "height" to HEIGHT,
            "iterations" to COMPUTE_ITERATIONS,
            "render_iterations" to SCENE_STEPS,
            "scene_instances" to 1,
            "hdr" to false,
            "msaa_samples" to 0,
            "bloom" to true,
            "passes" to RENDER_PASSES,
        )
    }

    /** Teste de compute: 48 iterações de ALU por pixel em 1080p. */
    fun runCompute(durationMs: Int): Map<String, Any> {
        val scene = ensureRenderer()
        val targetSeconds = max(durationMs, 200) / 1000.0

        var frames = 0
        val startedNs = System.nanoTime()
        var elapsedSeconds = 0.0

        while (true) {
            scene.drawCompute()
            GLES20.glFinish()
            frames++
            elapsedSeconds = (System.nanoTime() - startedNs) / 1_000_000_000.0
            if (elapsedSeconds >= targetSeconds && frames >= 8) break
        }

        val fps = if (elapsedSeconds > 0) frames / elapsedSeconds else 0.0
        val score = fps * 100.0

        return mapOf(
            "available" to true,
            "kind" to "compute",
            "device" to gpuName,
            "width" to WIDTH,
            "height" to HEIGHT,
            "iterations" to COMPUTE_ITERATIONS,
            "frames" to frames,
            "elapsed_ms" to (elapsedSeconds * 1000.0).toLong(),
            "fps" to round2(fps),
            "pixels_per_second" to round2(fps * WIDTH * HEIGHT),
            "score" to round1(score),
            "gpu_time_used" to true,
        )
    }

    /**
     * Teste de render: cena volumétrica em 1080p com pipeline de 5 passes,
     * medindo o tempo de cada quadro para calcular p99 e 1% low.
     */
    fun runRender(durationMs: Int): Map<String, Any> {
        val scene = ensureRenderer()
        val targetSeconds = max(durationMs, 200) / 1000.0

        val frameDurations = ArrayList<Double>(2048)
        var frames = 0
        val startedNs = System.nanoTime()
        var elapsedSeconds = 0.0

        while (true) {
            val frameStart = System.nanoTime()
            scene.drawSceneFrame(
                timeSeconds = frames * 0.016f,
                present = false,
                viewWidth = 0,
                viewHeight = 0,
            )
            GLES20.glFinish()
            frameDurations.add((System.nanoTime() - frameStart) / 1_000_000.0)
            frames++
            elapsedSeconds = (System.nanoTime() - startedNs) / 1_000_000_000.0
            if (elapsedSeconds >= targetSeconds && frames >= 10) break
        }

        val fps = if (elapsedSeconds > 0) frames / elapsedSeconds else 0.0
        val avgMs = if (frames > 0) elapsedSeconds * 1000.0 / frames else 0.0

        val sorted = frameDurations.sorted()
        val p99Ms = percentile(sorted, 0.99) ?: avgMs * 1.15
        val p999Ms = percentile(sorted, 0.999) ?: avgMs * 1.30
        val oneLow = if (p99Ms > 0) 1000.0 / p99Ms else fps * 0.88
        val pointOneLow = if (p999Ms > 0) 1000.0 / p999Ms else fps * 0.78

        return mapOf(
            "available" to true,
            "kind" to "render",
            "device" to gpuName,
            "width" to WIDTH,
            "height" to HEIGHT,
            "iterations" to SCENE_STEPS,
            "frames" to frames,
            "elapsed_ms" to (elapsedSeconds * 1000.0).toLong(),
            "fps" to round2(fps),
            "pixels_per_second" to round2(fps * WIDTH * HEIGHT),
            "score" to round1(fps * 100.0),
            "gpu_time_used" to true,
            "instances" to 1,
            "triangles_per_frame" to 2,
            "shading_iterations" to SCENE_STEPS,
            "msaa_samples" to 0,
            "hdr" to false,
            "bloom" to true,
            "passes" to RENDER_PASSES,
            "avg_frame_ms" to round2(avgMs),
            "p99_frame_ms" to round2(p99Ms),
            "p999_frame_ms" to round2(p999Ms),
            "one_percent_low_fps" to round2(oneLow),
            "point_one_percent_low_fps" to round2(pointOneLow),
            "frame_time_samples" to frameDurations.size,
        )
    }

    /** Libera contexto EGL e recursos. Chamado quando a Activity é destruída. */
    fun release() {
        renderer?.release()
        renderer = null
        if (display != EGL14.EGL_NO_DISPLAY) {
            EGL14.eglMakeCurrent(
                display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT
            )
            if (surface != EGL14.EGL_NO_SURFACE) {
                EGL14.eglDestroySurface(display, surface)
            }
            if (eglContext != EGL14.EGL_NO_CONTEXT) {
                EGL14.eglDestroyContext(display, eglContext)
            }
            EGL14.eglTerminate(display)
        }
        surface = EGL14.EGL_NO_SURFACE
        eglContext = EGL14.EGL_NO_CONTEXT
        display = EGL14.EGL_NO_DISPLAY
    }

    private fun percentile(sorted: List<Double>, fraction: Double): Double? {
        if (sorted.size < 10) return null
        val index = min(sorted.size - 1, max(0, ceil(sorted.size * fraction).toInt() - 1))
        return sorted[index]
    }

    private fun round2(value: Double): Double = round(value * 100.0) / 100.0

    private fun round1(value: Double): Double = round(value * 10.0) / 10.0
}
