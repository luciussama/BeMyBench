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
/// O BMyBench mede frames/s do kernel Metal. A conversão para 3DMark
/// Time Spy Graphics e Geekbench 6 Metal é linear, calibrada no
/// dispositivo âncora (o mesmo que gerou o score de referência).
class GpuReferenceData {
  final String anchorDevice;
  final double anchorFps;
  final double anchorTimeSpy;
  final double anchorGb6Metal;
  final List<GpuReferenceDevice> devices;
  final String disclaimer;

  const GpuReferenceData({
    required this.anchorDevice,
    required this.anchorFps,
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

    final data = GpuReferenceData(
      anchorDevice: (anchor['device'] as String?) ?? 'BMyBench anchor',
      anchorFps: (anchor['bmb_fps'] as num).toDouble(),
      anchorTimeSpy: (anchor['time_spy_graphics'] as num).toDouble(),
      anchorGb6Metal: (anchor['gb6_metal'] as num).toDouble(),
      devices: list,
      disclaimer: json['disclaimer'] as String? ?? '',
    );
    _cache = data;
    return data;
  }

  double estimateTimeSpy(double fps) => anchorTimeSpy * (fps / anchorFps);

  double estimateGb6Metal(double fps) => anchorGb6Metal * (fps / anchorFps);

  /// Percentual de GPUs de referência abaixo do resultado informado.
  double percentile(double fps, {String vendor = 'Todos'}) {
    final pool = _filter(vendor);
    if (pool.isEmpty) return 0;
    final target = estimateTimeSpy(fps);
    final below = pool.where((d) => d.timeSpy < target).length;
    return below / pool.length * 100;
  }

  GpuReferenceDevice? nearest(double fps, {String vendor = 'Todos'}) {
    final pool = _filter(vendor);
    if (pool.isEmpty) return null;
    final target = estimateTimeSpy(fps);
    return pool.reduce(
      (a, b) =>
          (a.timeSpy - target).abs() <= (b.timeSpy - target).abs() ? a : b,
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
