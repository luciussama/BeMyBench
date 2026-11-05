import 'dart:convert';

import 'package:flutter/services.dart';

/// Dispositivo de referência (dados públicos aproximados).
class ReferenceDevice {
  final String name;
  final String vendor;
  final String segment;
  final int year;
  final int cores;
  final double cb23Single;
  final double cb23Multi;
  final double gb6Single;
  final double gb6Multi;

  const ReferenceDevice({
    required this.name,
    required this.vendor,
    required this.segment,
    required this.year,
    required this.cores,
    required this.cb23Single,
    required this.cb23Multi,
    required this.gb6Single,
    required this.gb6Multi,
  });
}

class ReferenceData {
  final double anchorBmbSingle;
  final double anchorBmbMulti;
  final double anchorCb23Single;
  final double anchorCb23Multi;
  final double anchorGb6Single;
  final double anchorGb6Multi;
  final List<ReferenceDevice> devices;
  final String disclaimer;

  const ReferenceData({
    required this.anchorBmbSingle,
    required this.anchorBmbMulti,
    required this.anchorCb23Single,
    required this.anchorCb23Multi,
    required this.anchorGb6Single,
    required this.anchorGb6Multi,
    required this.devices,
    required this.disclaimer,
  });

  static ReferenceData? _cache;

  static Future<ReferenceData> load() async {
    final cached = _cache;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString('assets/data/reference_cpu.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final anchor = json['anchor'] as Map<String, dynamic>;

    final list = (json['devices'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (d) => ReferenceDevice(
            name: d['name'] as String,
            vendor: d['vendor'] as String,
            segment: d['segment'] as String,
            year: (d['year'] as num).toInt(),
            cores: (d['cores'] as num).toInt(),
            cb23Single: (d['cb23_single'] as num).toDouble(),
            cb23Multi: (d['cb23_multi'] as num).toDouble(),
            gb6Single: (d['gb6_single'] as num).toDouble(),
            gb6Multi: (d['gb6_multi'] as num).toDouble(),
          ),
        )
        .toList()
      ..sort((a, b) => b.cb23Multi.compareTo(a.cb23Multi));

    final data = ReferenceData(
      anchorBmbSingle: (anchor['bmb_single_mops'] as num).toDouble(),
      anchorBmbMulti: (anchor['bmb_multi_mops'] as num).toDouble(),
      anchorCb23Single: (anchor['cb23_single'] as num).toDouble(),
      anchorCb23Multi: (anchor['cb23_multi'] as num).toDouble(),
      anchorGb6Single: (anchor['gb6_single'] as num).toDouble(),
      anchorGb6Multi: (anchor['gb6_multi'] as num).toDouble(),
      devices: list,
      disclaimer: json['disclaimer'] as String? ?? '',
    );
    _cache = data;
    return data;
  }

  /// Converte o score multi-core do BMyBench para um equivalente aproximado
  /// de Cinebench R23 multi, usando calibração linear no dispositivo âncora.
  double estimateCb23Multi(double bmbMulti) =>
      anchorCb23Multi * (bmbMulti / anchorBmbMulti);

  double estimateCb23Single(double bmbSingle) =>
      anchorCb23Single * (bmbSingle / anchorBmbSingle);

  double estimateGb6Multi(double bmbMulti) =>
      anchorGb6Multi * (bmbMulti / anchorBmbMulti);

  double estimateGb6Single(double bmbSingle) =>
      anchorGb6Single * (bmbSingle / anchorBmbSingle);

  /// Percentual de dispositivos de referência abaixo do score informado.
  double percentile(double bmbMulti, {String vendor = 'Todos'}) {
    final pool = _filter(vendor);
    if (pool.isEmpty) return 0;
    final below = pool.where((d) => d.cb23Multi < estimateCb23Multi(bmbMulti)).length;
    return below / pool.length * 100;
  }

  /// Dispositivo de referência mais próximo do score informado.
  ReferenceDevice? nearest(double bmbMulti, {String vendor = 'Todos'}) {
    final pool = _filter(vendor);
    if (pool.isEmpty) return null;
    final target = estimateCb23Multi(bmbMulti);
    return pool.reduce(
      (a, b) => (a.cb23Multi - target).abs() <= (b.cb23Multi - target).abs() ? a : b,
    );
  }

  List<ReferenceDevice> _filter(String vendor) {
    if (vendor == 'Todos') return devices;
    return devices.where((d) => d.vendor == vendor).toList();
  }

  List<ReferenceDevice> devicesFor(String vendor) => _filter(vendor);
}
