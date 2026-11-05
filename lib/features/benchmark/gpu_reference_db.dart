import 'dart:convert';

import 'package:flutter/services.dart';

/// GPU de referência com scores públicos de desempenho (aproximados).
///
/// Os valores foram compilados de rankings públicos; as marcas pertencem aos
/// seus respectivos titulares e o BMyBench não é afiliado a eles. Uso
/// factual/nominal, apenas para comparação. Fontes e marcas no JSON de dados.
class GpuReferenceDevice {
  final String name;
  final String vendor;
  final String segment;
  final int year;
  final int gpuCores;
  final double gpuRefRaster;
  final double gpuRefCompute;

  const GpuReferenceDevice({
    required this.name,
    required this.vendor,
    required this.segment,
    required this.year,
    required this.gpuCores,
    required this.gpuRefRaster,
    required this.gpuRefCompute,
  });
}

/// Base de referência de GPU.
///
/// O BMyBench mede frames/s em dois testes: compute e render. O score de
/// rasterização de referência é estimado a partir do teste de render; o
/// score de compute a partir do teste de compute. A conversão é linear,
/// calibrada no dispositivo âncora.
class GpuReferenceData {
  final String anchorDevice;
  final double anchorComputeFps;
  final double anchorRenderFps;
  final double anchorRefRaster;
  final double anchorRefCompute;
  final List<GpuReferenceDevice> devices;
  final String disclaimer;

  const GpuReferenceData({
    required this.anchorDevice,
    required this.anchorComputeFps,
    required this.anchorRenderFps,
    required this.anchorRefRaster,
    required this.anchorRefCompute,
    required this.devices,
    required this.disclaimer,
  });

  static GpuReferenceData? _cache;

  static Future<GpuReferenceData> load() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString('assets/data/reference_gpu.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final anchor = json['anchor'] as Map<String, dynamic>;

    final list = (json['devices'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (d) => GpuReferenceDevice(
            name: d['name'] as String,
            vendor: d['vendor'] as String,
            segment: d['segment'] as String,
            year: (d['year'] as num).toInt(),
            gpuCores: (d['gpu_cores'] as num).toInt(),
            gpuRefRaster: (d['gpu_ref_raster'] as num).toDouble(),
            gpuRefCompute: (d['gpu_ref_compute'] as num).toDouble(),
          ),
        )
        .toList()
      ..sort((a, b) => b.gpuRefRaster.compareTo(a.gpuRefRaster));

    final computeFps = (anchor['compute_fps'] ?? anchor['bmb_fps']) as num;

    final data = GpuReferenceData(
      anchorDevice: (anchor['device'] as String?) ?? 'BMyBench anchor',
      anchorComputeFps: computeFps.toDouble(),
      anchorRenderFps:
          (anchor['render_fps'] as num?)?.toDouble() ?? computeFps.toDouble(),
      anchorRefRaster: (anchor['public_raster'] as num).toDouble(),
      anchorRefCompute: (anchor['public_compute'] as num).toDouble(),
      devices: list,
      disclaimer: json['disclaimer'] as String? ?? '',
    );
    _cache = data;
    return data;
  }

  /// Score gráfico de referência estimado a partir do teste de render.
  double rasterRefFromRender(double fps) =>
      anchorRefRaster * (fps / anchorRenderFps);

  /// Score gráfico de referência estimado a partir do compute (fallback).
  double rasterRefFromCompute(double fps) =>
      anchorRefRaster * (fps / anchorComputeFps);

  /// Score de compute de referência estimado a partir do teste de compute.
  double computeRefFromCompute(double fps) =>
      anchorRefCompute * (fps / anchorComputeFps);

  /// Percentual de GPUs de referência abaixo do score informado.
  double percentileForRef(double refScore, {String vendor = 'Todos'}) {
    final pool = _filter(vendor);
    if (pool.isEmpty) return 0;
    final below = pool.where((d) => d.gpuRefRaster < refScore).length;
    return below / pool.length * 100;
  }

  GpuReferenceDevice? nearestForRef(double refScore,
      {String vendor = 'Todos'}) {
    final pool = _filter(vendor);
    if (pool.isEmpty) return null;
    return pool.reduce(
      (a, b) => (a.gpuRefRaster - refScore).abs() <=
              (b.gpuRefRaster - refScore).abs()
          ? a
          : b,
    );
  }

  List<GpuReferenceDevice> _filter(String vendor) {
    if (vendor == 'Todos') return devices;
    return devices.where((d) => d.vendor == vendor).toList();
  }

  List<GpuReferenceDevice> devicesFor(String vendor) => _filter(vendor);

  List<String> get vendors {
    final set = <String>{'Todos'};
    for (final d in devices) {
      set.add(d.vendor);
    }
    return set.toList();
  }
}
