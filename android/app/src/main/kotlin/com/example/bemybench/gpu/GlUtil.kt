package com.example.bemybench.gpu

import android.opengl.GLES20
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/** Utilitários mínimos de compilação de shaders e geometria. */
internal object GlUtil {

    /** Quad full-screen (TRIANGLE_STRIP) que cobre o viewport. */
    fun fullscreenQuad(): FloatBuffer {
        val data = floatArrayOf(
            -1.0f, -1.0f,
            1.0f, -1.0f,
            -1.0f, 1.0f,
            1.0f, 1.0f,
        )
        val buffer = ByteBuffer.allocateDirect(data.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        buffer.put(data)
        buffer.position(0)
        return buffer
    }

    private fun compile(type: Int, source: String, label: String): Int {
        val shader = GLES20.glCreateShader(type)
        if (shader == 0) {
            throw IllegalStateException("Não foi possível criar o shader $label.")
        }
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)

        val status = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetShaderInfoLog(shader)
            GLES20.glDeleteShader(shader)
            throw IllegalStateException("Falha ao compilar o shader $label: $log")
        }
        return shader
    }

    /** Compila e linka um programa; devolve o id do programa GL. */
    fun program(vertexSource: String, fragmentSource: String, label: String): Int {
        val vertex = compile(GLES20.GL_VERTEX_SHADER, vertexSource, "$label.vert")
        val fragment = compile(GLES20.GL_FRAGMENT_SHADER, fragmentSource, "$label.frag")
        val program = GLES20.glCreateProgram()
        if (program == 0) {
            throw IllegalStateException("Não foi possível criar o programa $label.")
        }
        GLES20.glAttachShader(program, vertex)
        GLES20.glAttachShader(program, fragment)
        GLES20.glLinkProgram(program)

        val status = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, status, 0)
        // Os shaders já foram anexados ao programa: podem ser liberados.
        GLES20.glDeleteShader(vertex)
        GLES20.glDeleteShader(fragment)
        if (status[0] == 0) {
            val log = GLES20.glGetProgramInfoLog(program)
            GLES20.glDeleteProgram(program)
            throw IllegalStateException("Falha ao linkar o programa $label: $log")
        }
        return program
    }

    fun checkGlError(where: String) {
        val error = GLES20.glGetError()
        if (error != GLES20.GL_NO_ERROR) {
            throw IllegalStateException(
                "Erro OpenGL 0x${Integer.toHexString(error)} em $where."
            )
        }
    }
}
