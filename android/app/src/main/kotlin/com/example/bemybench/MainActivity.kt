package com.example.bemybench

import com.example.bemybench.gpu.GpuBenchmarkChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Activity principal do BMyBench no Android.
 *
 * Registra o canal nativo `bemybench/gpu` (OpenGL ES), que fornece as
 * informações da GPU, o benchmark de compute/render e a visualização 3D ao
 * vivo com HUD.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GpuBenchmarkChannel.attach(flutterEngine.dartExecutor.binaryMessenger, this)
    }

    override fun onDestroy() {
        GpuBenchmarkChannel.detach()
        super.onDestroy()
    }
}
