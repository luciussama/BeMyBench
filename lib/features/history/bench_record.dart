import 'dart:convert';

/// Um registro de execução de benchmark salvo localmente.
///
/// O arquivo fica em um diretório de dados do aplicativo (ver BenchHistoryStore):
/// nada é enviado para fora da máquina.
class BenchRecord {
  final DateTime timestamp;
  final double? cpuScore;
  final double? cpuSingleMops;
  final double? cpuMultiMops;
  final double? memScore;
  final double? diskScore;
  final double? gpuComputeScore;
  final double? gpuRenderScore;
  final double? gpuRenderOnePercentLow;
  final double? totalScore;
  final String? gpuDevice;
  final String? osLabel;

  const BenchRecord({
    required this.timestamp,
    this.cpuScore,
    this.cpuSingleMops,
    this.cpuMultiMops,
    this.memScore,
    this.diskScore,
    this.gpuComputeScore,
    this.gpuRenderScore,
    this.gpuRenderOnePercentLow,
    this.totalScore,
    this.gpuDevice,
    this.osLabel,
  });

  double get displayTotal => totalScore ?? 0;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        if (cpuScore != null) 'cpu_score': cpuScore,
        if (cpuSingleMops != null) 'cpu_single_mops': cpuSingleMops,
        if (cpuMultiMops != null) 'cpu_multi_mops': cpuMultiMops,
        if (memScore != null) 'mem_score': memScore,
        if (diskScore != null) 'disk_score': diskScore,
        if (gpuComputeScore != null) 'gpu_compute_score': gpuComputeScore,
        if (gpuRenderScore != null) 'gpu_render_score': gpuRenderScore,
        if (gpuRenderOnePercentLow != null)
          'gpu_render_1_percent_low': gpuRenderOnePercentLow,
        if (totalScore != null) 'total_score': totalScore,
        if (gpuDevice != null) 'gpu_device': gpuDevice,
        if (osLabel != null) 'os_label': osLabel,
      };

  factory BenchRecord.fromJson(Map<String, dynamic> json) {
    double? d(String key) => (json[key] as num?)?.toDouble();

    return BenchRecord(
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      cpuScore: d('cpu_score'),
      cpuSingleMops: d('cpu_single_mops'),
      cpuMultiMops: d('cpu_multi_mops'),
      memScore: d('mem_score'),
      diskScore: d('disk_score'),
      gpuComputeScore: d('gpu_compute_score'),
      gpuRenderScore: d('gpu_render_score'),
      gpuRenderOnePercentLow: d('gpu_render_1_percent_low'),
      totalScore: d('total_score'),
      gpuDevice: json['gpu_device'] as String?,
      osLabel: json['os_label'] as String?,
    );
  }

  static List<BenchRecord> fromJsonList(dynamic decoded) {
    // Formato atual: {"schema": ..., "records": [...]}
    if (decoded is Map && decoded['records'] is List) {
      return _fromList(decoded['records'] as List);
    }
    // Formato legado: lista solta []
    if (decoded is List) {
      return _fromList(decoded);
    }
    return <BenchRecord>[];
  }

  static List<BenchRecord> _fromList(List list) {
    final records = <BenchRecord>[];
    for (final entry in list) {
      if (entry is Map<String, dynamic>) {
        records.add(BenchRecord.fromJson(entry));
      } else if (entry is Map) {
        records.add(BenchRecord.fromJson(Map<String, dynamic>.from(entry)));
      }
    }
    records.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return records;
  }

  String get dateLabel {
    final t = timestamp.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
  }
}

/// Detecta/recupera a chave de schema usada no arquivo de histórico.
String historySchema() => 'bmybench/history/v1';

String encodeHistory(List<BenchRecord> records) =>
    const JsonEncoder.withIndent('  ').convert({
      'schema': historySchema(),
      'records': records.map((r) => r.toJson()).toList(),
    });
