package com.example.bemybench.gpu

import android.opengl.GLES20

/**
 * Renderizador compartilhado entre o benchmark off-screen e o overlay 3D ao
 * vivo. Sempre desenha internamente em 1920x1080 (independente do tamanho real
 * da tela), o que garante que a taxa de quadros exibida no HUD seja comparável
 * ao resultado numérico do benchmark.
 *
 * Pipeline de render (5 passes), espelhando o backend macOS/Windows:
 *   1. cena volumétrica (raymarching + fBm) em textura RGBA8
 *   2. bright pass em meia resolução
 *   3. blur horizontal
 *   4. blur vertical
 *   5. composite (bloom + tonemap ACES + vinheta + gamma)
 *
 * Deve ser criado e usado somente em uma thread com contexto OpenGL corrente.
 */
internal class SceneRenderer(
    val width: Int = 1920,
    val height: Int = 1080,
) {
    private val quad = GlUtil.fullscreenQuad()
    private val uniformCache = HashMap<Int, HashMap<String, Int>>()
    private val attribCache = HashMap<Int, Int>()

    private var computeProgram = 0
    private var sceneProgram = 0
    private var brightProgram = 0
    private var blurProgram = 0
    private var compositeProgram = 0

    private val textures = IntArray(5)
    private val framebuffers = IntArray(5)

    private val halfWidth = (width / 2).coerceAtLeast(1)
    private val halfHeight = (height / 2).coerceAtLeast(1)

    var ready = false
        private set

    fun init() {
        if (ready) return

        computeProgram = GlUtil.program(GlslSources.VERTEX, GlslSources.COMPUTE, "compute")
        sceneProgram = GlUtil.program(GlslSources.VERTEX, GlslSources.SCENE, "scene")
        brightProgram = GlUtil.program(GlslSources.VERTEX, GlslSources.BRIGHT, "bright")
        blurProgram = GlUtil.program(GlslSources.VERTEX, GlslSources.BLUR, "blur")
        compositeProgram = GlUtil.program(GlslSources.VERTEX, GlslSources.COMPOSITE, "composite")

        // Alvos: cena, bright, blurA, blurB, final
        createTarget(0, width, height)
        createTarget(1, halfWidth, halfHeight)
        createTarget(2, halfWidth, halfHeight)
        createTarget(3, halfWidth, halfHeight)
        createTarget(4, width, height)

        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glDisable(GLES20.GL_BLEND)
        GLES20.glDisable(GLES20.GL_DITHER)
        GLES20.glClearColor(0.02f, 0.01f, 0.01f, 1.0f)
        ready = true
    }

    fun release() {
        if (!ready) return
        GLES20.glDeleteProgram(computeProgram)
        GLES20.glDeleteProgram(sceneProgram)
        GLES20.glDeleteProgram(brightProgram)
        GLES20.glDeleteProgram(blurProgram)
        GLES20.glDeleteProgram(compositeProgram)
        GLES20.glDeleteFramebuffers(framebuffers.size, framebuffers, 0)
        GLES20.glDeleteTextures(textures.size, textures, 0)
        uniformCache.clear()
        attribCache.clear()
        ready = false
    }

    private fun createTarget(slot: Int, targetWidth: Int, targetHeight: Int) {
        val tex = IntArray(1)
        GLES20.glGenTextures(1, tex, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, tex[0])
        GLES20.glTexParameteri(
            GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR
        )
        GLES20.glTexParameteri(
            GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR
        )
        GLES20.glTexParameteri(
            GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE
        )
        GLES20.glTexParameteri(
            GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE
        )
        GLES20.glTexImage2D(
            GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA,
            targetWidth, targetHeight, 0,
            GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, null
        )

        val fbo = IntArray(1)
        GLES20.glGenFramebuffers(1, fbo, 0)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fbo[0])
        GLES20.glFramebufferTexture2D(
            GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0,
            GLES20.GL_TEXTURE_2D, tex[0], 0
        )
        val status = GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER)
        if (status != GLES20.GL_FRAMEBUFFER_COMPLETE) {
            throw IllegalStateException(
                "Framebuffer incompleto (0x${Integer.toHexString(status)})."
            )
        }
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, 0)

        textures[slot] = tex[0]
        framebuffers[slot] = fbo[0]
    }

    private fun uniform(program: Int, name: String): Int {
        val map = uniformCache.getOrPut(program) { HashMap() }
        return map.getOrPut(name) { GLES20.glGetUniformLocation(program, name) }
    }

    private fun drawQuad(program: Int) {
        val position = attribCache.getOrPut(program) {
            GLES20.glGetAttribLocation(program, "aPos")
        }
        if (position < 0) return
        GLES20.glEnableVertexAttribArray(position)
        quad.position(0)
        GLES20.glVertexAttribPointer(position, 2, GLES20.GL_FLOAT, false, 0, quad)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(position)
    }

    private fun bindTarget(slot: Int, targetWidth: Int, targetHeight: Int) {
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, framebuffers[slot])
        GLES20.glViewport(0, 0, targetWidth, targetHeight)
    }

    private fun bindTexture(unit: Int, texture: Int) {
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0 + unit)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
    }

    /** Executa um passo do teste de compute (equivalente ao dispatch). */
    fun drawCompute() {
        init()
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, framebuffers[0])
        GLES20.glViewport(0, 0, width, height)
        GLES20.glUseProgram(computeProgram)
        drawQuad(computeProgram)
    }

    /**
     * Renderiza um quadro completo da cena vulcânica.
     *
     * [present] desenha o composite direto no framebuffer padrão (tela),
     * aplicando letterbox para preservar o aspecto 16:9. Caso contrário o
     * composite vai para a textura final do contexto off-screen.
     */
    fun drawSceneFrame(
        timeSeconds: Float,
        present: Boolean,
        viewWidth: Int,
        viewHeight: Int,
    ) {
        init()

        // Pass 1 — cena volumétrica em 1920x1080
        bindTarget(0, width, height)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        GLES20.glUseProgram(sceneProgram)
        GLES20.glUniform1f(uniform(sceneProgram, "uTime"), timeSeconds)
        GLES20.glUniform2f(
            uniform(sceneProgram, "uResolution"),
            width.toFloat(), height.toFloat()
        )
        drawQuad(sceneProgram)

        // Pass 2 — bright pass em meia resolução
        bindTarget(1, halfWidth, halfHeight)
        GLES20.glUseProgram(brightProgram)
        bindTexture(0, textures[0])
        GLES20.glUniform1i(uniform(brightProgram, "uTex"), 0)
        GLES20.glUniform1f(uniform(brightProgram, "uThreshold"), 0.62f)
        drawQuad(brightProgram)

        // Pass 3 — blur horizontal
        bindTarget(2, halfWidth, halfHeight)
        GLES20.glUseProgram(blurProgram)
        bindTexture(0, textures[1])
        GLES20.glUniform1i(uniform(blurProgram, "uTex"), 0)
        GLES20.glUniform2f(
            uniform(blurProgram, "uTexel"),
            1.0f / halfWidth, 1.0f / halfHeight
        )
        GLES20.glUniform2f(uniform(blurProgram, "uDir"), 1.0f, 0.0f)
        drawQuad(blurProgram)

        // Pass 4 — blur vertical
        bindTarget(3, halfWidth, halfHeight)
        GLES20.glUseProgram(blurProgram)
        bindTexture(0, textures[2])
        GLES20.glUniform2f(uniform(blurProgram, "uDir"), 0.0f, 1.0f)
        drawQuad(blurProgram)

        // Pass 5 — composite
        if (present) {
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
            applyLetterbox(viewWidth, viewHeight)
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        } else {
            bindTarget(4, width, height)
        }
        GLES20.glUseProgram(compositeProgram)
        bindTexture(0, textures[0])
        bindTexture(1, textures[3])
        GLES20.glUniform1i(uniform(compositeProgram, "uScene"), 0)
        GLES20.glUniform1i(uniform(compositeProgram, "uBloom"), 1)
        drawQuad(compositeProgram)

        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
    }

    private fun applyLetterbox(viewWidth: Int, viewHeight: Int) {
        if (viewWidth <= 0 || viewHeight <= 0) {
            GLES20.glViewport(0, 0, width, height)
            return
        }
        val targetAspect = width.toFloat() / height.toFloat()
        val viewAspect = viewWidth.toFloat() / viewHeight.toFloat()
        val drawWidth: Int
        val drawHeight: Int
        if (viewAspect > targetAspect) {
            drawHeight = viewHeight
            drawWidth = (viewHeight * targetAspect).toInt().coerceAtLeast(1)
        } else {
            drawWidth = viewWidth
            drawHeight = (viewWidth / targetAspect).toInt().coerceAtLeast(1)
        }
        GLES20.glViewport(
            (viewWidth - drawWidth) / 2,
            (viewHeight - drawHeight) / 2,
            drawWidth,
            drawHeight
        )
    }
}
