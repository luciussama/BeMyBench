import 'dart:convert';

import 'package:flutter/services.dart';

/// GPU de referência com scores públicos aproximados.
class GpuReferenceDevice {
  final String name;
  final String vendor;
  final String segment;
  final int year;
  final int gpuCores;
  final double timeSpy;
  final double gb6Metal;

  const GpuReferenceDevice({
    required this.name,
    required this.vendor,
    required this.segment,
    required this.year,
    required this.gpuCores,
    required this.timeSpy,
    required this.gb6Metal,
  });
}

/// Base de referência de GPU.
///
/// O BMyBench mede frames/s em dois testes: compute e render. O Time Spy
/// (rasterização) é estimado a partir do teste de render; o Geekbench 6
/// Metal (compute) a partir do teste de compute. A conversão é linear,
/// calibrada no dispositivo âncora.
class GpuReferenceData {
  final String anchorDevice;
  final double anchorComputeFps;
  final double anchorRenderFps;
  final double anchorTimeSpy;
  final double anchorGb6Metal;
  final List<GpuReferenceDevice> devices;
  final String disclaimer;

  const GpuReferenceData({
    required this.anchorDevice,
    required this.anchorComputeFps,
    required this.anchorRenderFps,
    required this.anchorTimeSpy,
    required this.anchorGb6Metal,
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
            timeSpy: (d['time_spy'] as num).toDouble(),
            gb6Metal: (d['gb6_metal'] as num).toDouble(),
          ),
        )
        .toList()
      ..sort((a, b) => b.timeSpy.compareTo(a.timeSpy));

    final computeFps = (anchor['compute_fps'] ?? anchor['bmb_fps']) as num;

    final data = GpuReferenceData(
      anchorDevice: (anchor['device'] as String?) ?? 'BMyBench anchor',
      anchorComputeFps: computeFps.toDouble(),
      anchorRenderFps:
          (anchor['render_fps'] as num?)?.toDouble() ?? computeFps.toDouble(),
      anchorTimeSpy: (anchor['time_spy_graphics'] as num).toDouble(),
      anchorGb6Metal: (anchor['gb6_metal'] as num).toDouble(),
      devices: list,
      disclaimer: json['disclaimer'] as String? ?? '',
    );
    _cache = data;
    return data;
  }

  /// Time Spy estimado a partir do teste de renderização.
  double timeSpyFromRender(double fps) =>
      anchorTimeSpy * (fps / anchorRenderFps);

  /// Time Spy estimado a partir do teste de compute (fallback).
  double timeSpyFromCompute(double fps) =>
      anchorTimeSpy * (fps / anchorComputeFps);

  /// Geekbench 6 Metal estimado a partir do teste de compute.
  double gb6FromCompute(double fps) => anchorGb6Metal * (fps / anchorComputeFps);

  /// Percentual de GPUs de referência abaixo do Time Spy informado.
  double percentileForTimeSpy(double timeSpy, {String vendor = 'Todos'}) {
    final pool = _filter(vendor);
    if (pool.isEmpty) return 0;
    final below = pool.where((d) => d.timeSpy < timeSpy).length;
    return below / pool.length * 100;
  }

  GpuReferenceDevice? nearestForTimeSpy(double timeSpy, {String vendor = 'Todos'}) {
    final pool = _filter(vendor);
    if (pool.isEmpty) return null;
    return pool.reduce(
      (a, b) =>
          (a.timeSpy - timeSpy).abs() <= (b.timeSpy - timeSpy).abs() ? a : b,
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
