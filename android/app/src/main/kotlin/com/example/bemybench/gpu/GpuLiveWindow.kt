package com.example.bemybench.gpu

import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import java.util.ArrayDeque
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.max
import kotlin.math.min

/**
 * Visualização 3D ao vivo do Android: um diálogo em tela cheia com
 * GLSurfaceView renderizando a mesma cena vulcânica do benchmark, mais um HUD
 * nativo com FPS, tempo de quadro, GPU e modo.
 *
 * A cena é sempre renderizada internamente em 1920x1080 e apenas apresentada
 * escalada na tela, de modo que o FPS do HUD seja comparável ao resultado
 * numérico do benchmark (mesma carga de trabalho do backend off-screen).
 */
internal class GpuLiveWindow private constructor(
    private val activity: Activity,
    private val mode: String,
) {

    companion object {
        private const val TAG = "BmbGpuLiveWindow"

        @Volatile
        private var active: GpuLiveWindow? = null

        /** Instância aberta no momento (ou `null`). */
        fun current(): GpuLiveWindow? = active

        fun isOpen(): Boolean = active != null

        /** Abre o overlay. Deve ser chamado na thread de UI. */
        fun open(activity: Activity, mode: String): Boolean {
            if (active != null) return true
            return try {
                val window = GpuLiveWindow(activity, mode)
                window.show()
                active = window
                true
            } catch (t: Throwable) {
                Log.e(TAG, "Falha ao abrir a visualização 3D", t)
                false
            }
        }

        /** Fecha o overlay. Deve ser chamado na thread de UI. */
        fun close(): Boolean {
            val window = active ?: return false
            active = null
            window.dismissQuietly()
            return true
        }
    }

    private var dialog: Dialog? = null
    private var glView: GLSurfaceView? = null
    private var renderer: LiveRenderer? = null

    private var hudTitle: TextView? = null
    private var hudFps: TextView? = null
    private var hudDetail: TextView? = null
    private var hudFooter: TextView? = null

    private val startedNs = System.nanoTime()

    // Estatísticas compartilhadas com o canal (medição do benchmark ao vivo).
    @Volatile
    var liveFps: Double = 0.0
        private set

    @Volatile
    var liveAvgMs: Double = 0.0
        private set

    @Volatile
    var liveP99Ms: Double = 0.0
        private set

    @Volatile
    var liveOneLowFps: Double = 0.0
        private set

    @Volatile
    var liveFrames: Int = 0
        private set

    /** Geometria e passes executados por quadro (para o resultado numérico). */
    val passesPerFrame: Int = OffscreenGl.RENDER_PASSES

    private fun show() {
        val dialog = Dialog(activity)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
        dialog.setCanceledOnTouchOutside(false)
        dialog.setOnDismissListener {
            releaseGlView()
            if (active === this) active = null
        }

        val density = activity.resources.displayMetrics.density
        val root = FrameLayout(activity)
        root.setBackgroundColor(Color.BLACK)

        val view = GLSurfaceView(activity)
        view.setEGLContextClientVersion(2)
        view.setEGLConfigChooser(8, 8, 8, 8, 0, 0)
        view.setPreserveEGLContextOnPause(false)
        val live = LiveRenderer()
        renderer = live
        view.setRenderer(live)
        view.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
        glView = view

        root.addView(
            view,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )

        // ------------------------------------------------------------ HUD ---
        val hud = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(
                (16 * density).toInt(),
                (14 * density).toInt(),
                (16 * density).toInt(),
                (14 * density).toInt(),
            )
            background = GradientDrawable().apply {
                cornerRadius = 18f * density
                setColor(Color.argb(210, 8, 13, 19))
                setStroke((1.4f * density).toInt(), Color.argb(130, 34, 211, 238))
            }
        }

        hudTitle = label(activity, density, 10f, Color.rgb(34, 211, 238), Typeface.BOLD).apply {
            text = if (mode == "benchmark") {
                "BMYBENCH · BENCHMARK 3D AO VIVO"
            } else {
                "BMYBENCH · ESTRESSE CONTÍNUO DE GPU"
            }
            letterSpacing = 0.12f
        }
        hudFps = label(activity, density, 30f, Color.WHITE, Typeface.BOLD).apply {
            text = "-- fps"
        }
        hudDetail = label(activity, density, 11f, Color.rgb(203, 213, 225), Typeface.NORMAL).apply {
            text = "inicializando OpenGL ES..."
            maxLines = 4
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        hudFooter = label(activity, density, 10f, Color.rgb(100, 116, 139), Typeface.NORMAL).apply {
            text = "cena 1920x1080 interna · 5 passes · bloom"
        }

        hud.addView(hudTitle)
        hud.addView(hudFps)
        hud.addView(hudDetail)
        hud.addView(hudFooter)

        val hudParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.START
        ).apply {
            setMargins((14 * density).toInt(), (14 * density).toInt(), (14 * density).toInt(), 0)
        }
        root.addView(hud, hudParams)

        // Botão de fechar (a barra de status/cutout não é garantia de acesso).
        val close = TextView(activity).apply {
            text = "✕"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.argb(190, 15, 23, 32))
                setStroke((1.2f * density).toInt(), Color.argb(140, 148, 163, 184))
            }
            contentDescription = "Fechar visualização 3D"
            setOnClickListener { dismissQuietly() }
        }
        val closeParams = FrameLayout.LayoutParams(
            (46 * density).toInt(),
            (46 * density).toInt(),
            Gravity.TOP or Gravity.END
        ).apply {
            setMargins(0, (18 * density).toInt(), (18 * density).toInt(), 0)
        }
        root.addView(close, closeParams)

        dialog.setContentView(root)
        dialog.show()

        dialog.window?.apply {
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setBackgroundDrawable(ColorDrawable(Color.BLACK))
            addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }

        this.dialog = dialog
    }

    private fun label(
        activity: Activity,
        density: Float,
        sizeSp: Float,
        color: Int,
        style: Int,
    ): TextView = TextView(activity).apply {
        setTextColor(color)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
        typeface = Typeface.create(Typeface.DEFAULT, style)
        setPadding(0, (2 * density).toInt(), 0, (2 * density).toInt())
    }

    private fun dismissQuietly() {
        val dialog = dialog ?: return
        dialog.setOnDismissListener(null)
        try {
            if (dialog.isShowing) dialog.dismiss()
        } catch (t: Throwable) {
            Log.w(TAG, "Falha ao fechar a visualização 3D", t)
        }
        this.dialog = null
        releaseGlView()
        if (active === this) active = null
    }

    private fun releaseGlView() {
        val view = glView ?: return
        glView = null
        try {
            view.onPause()
        } catch (_: Throwable) {
        }
        (view.parent as? ViewGroup)?.removeView(view)
    }

    private fun updateHud(
        gpuName: String,
        fps: Double,
        avgMs: Double,
        p99Ms: Double,
        elapsedSeconds: Long,
        frames: Int,
    ) {
        val dialog = dialog ?: return
        if (!dialog.isShowing) return
        val minutes = elapsedSeconds / 60
        val seconds = elapsedSeconds % 60
        val timeLabel = "%02d:%02d".format(minutes, seconds)
        try {
            activity.runOnUiThread {
                hudFps?.text = "%.1f fps".format(fps)
                hudDetail?.text =
                    "%.2f ms/quadro · p99 %.2f ms\n%s\n%s · %d quadros · %s".format(
                        avgMs, p99Ms, gpuName,
                        if (mode == "benchmark") "benchmark" else "estresse",
                        frames, timeLabel
                    )
                hudTitle?.text = if (mode == "benchmark") {
                    "BMYBENCH · BENCHMARK 3D AO VIVO"
                } else {
                    "BMYBENCH · ESTRESSE CONTÍNUO DE GPU"
                }
            }
        } catch (_: Throwable) {
            // Activity destruída no meio da atualização: ignora.
        }
    }

    /**
     * Renderer do GLSurfaceView. Mede o tempo de GPU de cada quadro (glFinish
     * antes da apresentação) para que o FPS exibido não seja limitado pelo
     * VSync da tela.
     */
    private inner class LiveRenderer : GLSurfaceView.Renderer {
        private var scene: SceneRenderer? = null
        private var viewWidth = 0
        private var viewHeight = 0
        private val recent = ArrayDeque<Double>()
        private var frames = 0
        private var lastHudNs = 0L
        private var failureReported = false

        override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
            // Contexto recriado: os recursos antigos deixaram de existir.
            scene = null
            recent.clear()
            frames = 0
            failureReported = false
            GLES20.glClearColor(0f, 0f, 0f, 1f)
        }

        override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
            viewWidth = width
            viewHeight = height
            GLES20.glViewport(0, 0, width, height)
        }

        override fun onDrawFrame(gl: GL10?) {
            val renderer = try {
                scene ?: SceneRenderer().also { it.init() }.also { scene = it }
            } catch (t: Throwable) {
                Log.e(TAG, "Falha ao preparar a cena ao vivo", t)
                showFailure(t.message ?: "erro desconhecido")
                return
            }

            val frameStartNs = System.nanoTime()
            try {
                renderer.drawSceneFrame(
                    timeSeconds = ((frameStartNs - startedNs) / 1_000_000_000.0).toFloat(),
                    present = true,
                    viewWidth = viewWidth,
                    viewHeight = viewHeight,
                )
                GLES20.glFinish()
            } catch (t: Throwable) {
                Log.e(TAG, "Falha ao desenhar a cena ao vivo", t)
                showFailure(t.message ?: "erro desconhecido")
                return
            }

            val frameMs = (System.nanoTime() - frameStartNs) / 1_000_000.0
            recent.addLast(frameMs)
            while (recent.size > 240) recent.removeFirst()
            frames++
            liveFrames = frames

            val avgMs = recent.average()
            liveAvgMs = avgMs
            liveFps = if (avgMs > 0) 1000.0 / avgMs else 0.0

            val sorted = recent.sorted()
            liveP99Ms = sorted[min(sorted.size - 1, max(0, (sorted.size * 0.99).toInt()))]
            liveOneLowFps = if (liveP99Ms > 0) 1000.0 / liveP99Ms else liveFps * 0.88

            val nowNs = System.nanoTime()
            if (nowNs - lastHudNs > 250_000_000L) {
                lastHudNs = nowNs
                updateHud(
                    gpuName = GLES20.glGetString(GLES20.GL_RENDERER)?.trim() ?: "GPU",
                    fps = liveFps,
                    avgMs = liveAvgMs,
                    p99Ms = liveP99Ms,
                    elapsedSeconds = (nowNs - startedNs) / 1_000_000_000L,
                    frames = frames,
                )
            }
        }

        private fun showFailure(message: String) {
            if (failureReported) return
            failureReported = true
            try {
                activity.runOnUiThread {
                    hudFps?.text = "ERRO"
                    hudDetail?.text = message
                }
            } catch (_: Throwable) {
            }
        }
    }

    /** Aguarda a primeira amostra de quadro (chamado na thread de trabalho). */
    fun awaitFirstSamples(timeoutMs: Long): Boolean {
        val deadline = System.nanoTime() + timeoutMs * 1_000_000L
        while (System.nanoTime() < deadline) {
            if (liveFrames >= 5 && liveAvgMs > 0) return true
            try {
                Thread.sleep(16)
            } catch (_: InterruptedException) {
                return liveFrames >= 5
            }
        }
        return liveFrames >= 5 && liveAvgMs > 0
    }
}
