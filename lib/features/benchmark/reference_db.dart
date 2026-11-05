import 'dart:convert';

import 'package:flutter/services.dart';

/// Dispositivo de referência com scores públicos de desempenho (aproximados).
///
/// Os valores foram compilados de rankings públicos; as marcas pertencem aos
/// seus respectivos titulares e o BMyBench não é afiliado a eles. Uso
/// factual/nominal, apenas para comparação. Fontes e marcas no JSON de dados.
class ReferenceDevice {
  final String name;
  final String vendor;
  final String segment;
  final int year;
  final int cores;
  final double cpuRefSingle;
  final double cpuRefMulti;
  final double computeRefSingle;
  final double computeRefMulti;

  const ReferenceDevice({
    required this.name,
    required this.vendor,
    required this.segment,
    required this.year,
    required this.cores,
    required this.cpuRefSingle,
    required this.cpuRefMulti,
    required this.computeRefSingle,
    required this.computeRefMulti,
  });
}

class ReferenceData {
  final double anchorBmbSingle;
  final double anchorBmbMulti;
  final double anchorCpuRefSingle;
  final double anchorCpuRefMulti;
  final double anchorComputeRefSingle;
  final double anchorComputeRefMulti;
  final List<ReferenceDevice> devices;
  final String disclaimer;

  const ReferenceData({
    required this.anchorBmbSingle,
    required this.anchorBmbMulti,
    required this.anchorCpuRefSingle,
    required this.anchorCpuRefMulti,
    required this.anchorComputeRefSingle,
    required this.anchorComputeRefMulti,
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
            cpuRefSingle: (d['cpu_ref_single'] as num).toDouble(),
            cpuRefMulti: (d['cpu_ref_multi'] as num).toDouble(),
            computeRefSingle: (d['compute_ref_single'] as num).toDouble(),
            computeRefMulti: (d['compute_ref_multi'] as num).toDouble(),
          ),
        )
        .toList()
      ..sort((a, b) => b.cpuRefMulti.compareTo(a.cpuRefMulti));

    final data = ReferenceData(
      anchorBmbSingle: (anchor['bmb_single_mops'] as num).toDouble(),
      anchorBmbMulti: (anchor['bmb_multi_mops'] as num).toDouble(),
      anchorCpuRefSingle: (anchor['cpu_ref_single'] as num).toDouble(),
      anchorCpuRefMulti: (anchor['cpu_ref_multi'] as num).toDouble(),
      anchorComputeRefSingle:
          (anchor['compute_ref_single'] as num).toDouble(),
      anchorComputeRefMulti: (anchor['compute_ref_multi'] as num).toDouble(),
      devices: list,
      disclaimer: json['disclaimer'] as String? ?? '',
    );
    _cache = data;
    return data;
  }

  /// Converte o score multi-core do BMyBench para o equivalente aproximado
  /// das suítes públicas de referência de CPU, usando calibração linear.
  double estimateCpuRefMulti(double bmbMulti) =>
      anchorCpuRefMulti * (bmbMulti / anchorBmbMulti);

  double estimateCpuRefSingle(double bmbSingle) =>
      anchorCpuRefSingle * (bmbSingle / anchorBmbSingle);

  double estimateComputeRefMulti(double bmbMulti) =>
      anchorComputeRefMulti * (bmbMulti / anchorBmbMulti);

  double estimateComputeRefSingle(double bmbSingle) =>
      anchorComputeRefSingle * (bmbSingle / anchorBmbSingle);

  /// Percentual de dispositivos de referência abaixo do score informado.
  double percentile(double bmbMulti, {String vendor = 'Todos'}) {
    final pool = _filter(vendor);
    if (pool.isEmpty) return 0;
    final below =
        pool.where((d) => d.cpuRefMulti < estimateCpuRefMulti(bmbMulti)).length;
    return below / pool.length * 100;
  }

  /// Dispositivo de referência mais próximo do score informado.
  ReferenceDevice? nearest(double bmbMulti, {String vendor = 'Todos'}) {
    final pool = _filter(vendor);
    if (pool.isEmpty) return null;
    final target = estimateCpuRefMulti(bmbMulti);
    return pool.reduce(
      (a, b) => (a.cpuRefMulti - target).abs() <= (b.cpuRefMulti - target).abs()
          ? a
          : b,
    );
  }

  List<ReferenceDevice> _filter(String vendor) {
    if (vendor == 'Todos') return devices;
    return devices.where((d) => d.vendor == vendor).toList();
  }

  List<ReferenceDevice> devicesFor(String vendor) => _filter(vendor);
}
