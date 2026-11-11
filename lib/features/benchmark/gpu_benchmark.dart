import 'dart:io';

import 'package:flutter/services.dart';

/// Informações da GPU expostas pelo backend nativo (Metal, Direct3D 11 ou
/// OpenGL ES).
class GpuInfo {
  final String name;
  final bool unifiedMemory;
  final int recommendedWorkingSetMb;
  final int maxThreadsPerGroup;
  final int width;
  final int height;
  final bool renderAvailable;

  /// API gráfica reportada pelo driver (ex.: "OpenGL ES 3.2").
  final String api;

  const GpuInfo({
    required this.name,
    required this.unifiedMemory,
    required this.recommendedWorkingSetMb,
    required this.maxThreadsPerGroup,
    required this.width,
    required this.height,
    required this.renderAvailable,
    this.api = '',
  });

  factory GpuInfo.fromMap(Map<String, dynamic> map) => GpuInfo(
        name: (map['name'] as String?) ?? 'GPU',
        unifiedMemory: (map['unified_memory'] as bool?) ?? false,
        recommendedWorkingSetMb:
            (map['recommended_working_set_mb'] as num?)?.toInt() ?? 0,
        maxThreadsPerGroup:
            (map['max_threads_per_group'] as num?)?.toInt() ?? 0,
        width: (map['width'] as num?)?.toInt() ?? 1920,
        height: (map['height'] as num?)?.toInt() ?? 1080,
        renderAvailable: (map['render_available'] as bool?) ?? false,
        api: (map['api'] as String?) ?? '',
      );
}

/// Resultado do benchmark de GPU (compute ou render).
class GpuBenchResult {
  final String kind;
  final String device;
  final int width;
  final int height;
  final int iterations;
  final int frames;
  final double elapsedMs;
  final double fps;
  final double pixelsPerSecond;
  final double score;

  /// Geometria desenhada por frame (apenas render).
  final int instances;
  final int trianglesPerFrame;

  /// Pipeline HDR do teste de render.
  final int msaaSamples;
  final bool hdr;
  final bool bloom;
  final int passes;

  /// Estatísticas de frame time (apenas render).
  final double avgFrameMs;
  final double p99FrameMs;
  final double p999FrameMs;
  final double onePercentLowFps;
  final double pointOnePercentLowFps;
  final int frameTimeSamples;

  /// Passos de raymarching/shading por pixel (apenas render volumétrico).
  final int shadingIterations;

  const GpuBenchResult({
    this.kind = 'compute',
    required this.device,
    required this.width,
    required this.height,
    required this.iterations,
    required this.frames,
    required this.elapsedMs,
    required this.fps,
    required this.pixelsPerSecond,
    required this.score,
    this.instances = 0,
    this.trianglesPerFrame = 0,
    this.msaaSamples = 0,
    this.hdr = false,
    this.bloom = false,
    this.passes = 0,
    this.avgFrameMs = 0,
    this.p99FrameMs = 0,
    this.p999FrameMs = 0,
    this.onePercentLowFps = 0,
    this.pointOnePercentLowFps = 0,
    this.frameTimeSamples = 0,
    this.shadingIterations = 0,
  });

  bool get isRender => kind == 'render';

  bool get hasFrameStats => frameTimeSamples >= 10;

  /// Descrição curta do pipeline gráfico usado no teste de render.
  ///
  /// Cada backend expõe só o que realmente executa: no Android, por exemplo,
  /// não há MSAA nem HDR (OpenGL ES 2.0), mas bloom e os 5 passes existem.
  String get pipelineLabel {
    final parts = <String>[];
    if (msaaSamples > 0) parts.add('MSAA ${msaaSamples}x');
    if (hdr) parts.add('HDR');
    if (bloom) parts.add('bloom');
    if (passes > 0) parts.add('$passes passes');
    return parts.join(' · ');
  }

  /// Descrição da cena renderizada (geometria ou raymarching volumétrico).
  String get sceneLabel {
    if (instances > 1) {
      return '$instances cubos · $trianglesPerFrame triângulos';
    }
    final steps = shadingIterations > 0 ? '$shadingIterations passos · ' : '';
    return 'raymarch volumétrico · $steps$trianglesPerFrame triângulos';
  }

  factory GpuBenchResult.fromMap(Map<String, dynamic> map) => GpuBenchResult(
        kind: (map['kind'] as String?) ?? 'compute',
        device: (map['device'] as String?) ?? 'GPU',
        width: (map['width'] as num?)?.toInt() ?? 1920,
        height: (map['height'] as num?)?.toInt() ?? 1080,
        iterations: (map['iterations'] as num?)?.toInt() ?? 0,
        frames: (map['frames'] as num?)?.toInt() ?? 0,
        elapsedMs: (map['elapsed_ms'] as num?)?.toDouble() ?? 0,
        fps: (map['fps'] as num?)?.toDouble() ?? 0,
        pixelsPerSecond: (map['pixels_per_second'] as num?)?.toDouble() ?? 0,
        score: (map['score'] as num?)?.toDouble() ?? 0,
        instances: (map['instances'] as num?)?.toInt() ?? 0,
        trianglesPerFrame: (map['triangles_per_frame'] as num?)?.toInt() ?? 0,
        msaaSamples: (map['msaa_samples'] as num?)?.toInt() ?? 0,
        hdr: (map['hdr'] as bool?) ?? false,
        bloom: (map['bloom'] as bool?) ?? false,
        passes: (map['passes'] as num?)?.toInt() ?? 0,
        avgFrameMs: (map['avg_frame_ms'] as num?)?.toDouble() ?? 0,
        p99FrameMs: (map['p99_frame_ms'] as num?)?.toDouble() ?? 0,
        p999FrameMs: (map['p999_frame_ms'] as num?)?.toDouble() ?? 0,
        onePercentLowFps:
            (map['one_percent_low_fps'] as num?)?.toDouble() ?? 0,
        pointOnePercentLowFps:
            (map['point_one_percent_low_fps'] as num?)?.toDouble() ?? 0,
        frameTimeSamples: (map['frame_time_samples'] as num?)?.toInt() ?? 0,
        shadingIterations: (map['shading_iterations'] as num?)?.toInt() ?? 0,
      );
}

/// Serviço que conversa com o backend nativo de GPU.
///
/// Cada plataforma implementa o mesmo contrato de método no canal
/// `bemybench/gpu`:
/// - macOS: Metal (`GpuBenchmark.swift`)
/// - Windows: Direct3D 11 (`gpu_benchmark.cpp`)
/// - Android: OpenGL ES 2.0 (`GpuBenchmarkChannel.kt`)
class GpuBenchmarkService {
  static const MethodChannel _channel = MethodChannel('bemybench/gpu');

  static bool get isSupported =>
      Platform.isMacOS || Platform.isWindows || Platform.isAndroid;

  /// API gráfica nativa usada na plataforma atual.
  static String get backendLabel {
    if (Platform.isMacOS) return 'Metal';
    if (Platform.isWindows) return 'Direct3D 11';
    if (Platform.isAndroid) return 'OpenGL ES';
    return 'GPU';
  }

  /// Nome do recurso de visualização 3D ao vivo em cada plataforma.
  ///
  /// No desktop é uma janela flutuante independente; no Android é um overlay
  /// em tela cheia com HUD nativo.
  static String get liveViewLabel => Platform.isAndroid
      ? 'Visualização 3D (tela cheia)'
      : 'Janela 3D (Ao Vivo)';

  /// Texto de indisponibilidade usado nos chips quando não há backend.
  static String get unavailableLabel => 'GPU (indisponível)';

  Future<GpuInfo?> info() async {
    if (!isSupported) return null;
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('info');
      if (map == null || map['available'] != true) return null;
      return GpuInfo.fromMap(map);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<GpuBenchResult> run({int durationMs = 1500}) async {
    if (!isSupported) {
      throw UnsupportedError(
        'O benchmark de GPU está disponível no macOS, Windows e Android '
        'nesta versão.',
      );
    }
    final map = await _channel.invokeMapMethod<String, dynamic>(
      'run',
      {'duration_ms': durationMs},
    );
    if (map == null) {
      throw StateError('A GPU não retornou resultado.');
    }
    return GpuBenchResult.fromMap(map);
  }

  /// Benchmark de renderização (pipeline gráfico + fragment shader).
  Future<GpuBenchResult> runRender({int durationMs = 1500}) async {
    if (!isSupported) {
      throw UnsupportedError(
        'O benchmark de GPU está disponível no macOS, Windows e Android '
        'nesta versão.',
      );
    }
    final map = await _channel.invokeMapMethod<String, dynamic>(
      'run_render',
      {'duration_ms': durationMs},
    );
    if (map == null) {
      throw StateError('A GPU não retornou resultado de renderização.');
    }
    return GpuBenchResult.fromMap(map);
  }

  /// Abre a visualização 3D nativa ao vivo com HUD.
  ///
  /// No macOS e no Windows é uma janela flutuante com VSync desligado. No
  /// Android é um overlay em tela cheia (GLSurfaceView) com HUD nativo, que
  /// renderiza a mesma cena do benchmark em 1920x1080 internos.
  ///
  /// [mode]: 'benchmark' (abre só durante os testes de GPU) ou 'stress'
  /// (estresse contínuo).
  Future<bool> open3dWindow({String mode = 'stress'}) async {
    if (!isSupported) return false;
    try {
      final res = await _channel.invokeMethod<bool>('open_3d_window', {'mode': mode});
      return res ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Fecha a janela 3D nativa.
  Future<bool> close3dWindow() async {
    if (!isSupported) return false;
    try {
      final res = await _channel.invokeMethod<bool>('close_3d_window');
      return res ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Verifica se a janela 3D nativa está aberta no momento.
  Future<bool> is3dWindowOpen() async {
    if (!isSupported) return false;
    try {
      final res = await _channel.invokeMethod<bool>('is_3d_window_open');
      return res ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
