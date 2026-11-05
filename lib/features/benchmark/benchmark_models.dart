/// Resultados dos benchmarks. Cada um traz o score próprio do BMyBench.
class CpuBenchResult {
  final double singleMops;
  final double multiMops;
  final int threads;
  final int durationMs;
  final double score;

  const CpuBenchResult({
    required this.singleMops,
    required this.multiMops,
    required this.threads,
    required this.durationMs,
    required this.score,
  });

  factory CpuBenchResult.fromJson(Map<String, dynamic> json) => CpuBenchResult(
        singleMops: (json['single_mops'] as num).toDouble(),
        multiMops: (json['multi_mops'] as num).toDouble(),
        threads: (json['threads'] as num).toInt(),
        durationMs: (json['duration_ms'] as num).toInt(),
        score: (json['score'] as num).toDouble(),
      );
}

class MemoryBenchResult {
  final double writeGbps;
  final double readGbps;
  final double copyGbps;
  final double latencyNs;
  final int sizeMb;
  final double score;

  const MemoryBenchResult({
    required this.writeGbps,
    required this.readGbps,
    required this.copyGbps,
    required this.latencyNs,
    required this.sizeMb,
    required this.score,
  });

  factory MemoryBenchResult.fromJson(Map<String, dynamic> json) =>
      MemoryBenchResult(
        writeGbps: (json['write_gbps'] as num).toDouble(),
        readGbps: (json['read_gbps'] as num).toDouble(),
        copyGbps: (json['copy_gbps'] as num).toDouble(),
        latencyNs: (json['latency_ns'] as num).toDouble(),
        sizeMb: (json['size_mb'] as num).toInt(),
        score: (json['score'] as num).toDouble(),
      );
}

class DiskBenchResult {
  final double writeMbps;
  final double readMbps;
  final int sizeMb;
  final double score;

  const DiskBenchResult({
    required this.writeMbps,
    required this.readMbps,
    required this.sizeMb,
    required this.score,
  });
}

/// Estado de execução de um teste, para a UI.
enum BenchStatus { idle, running, done, error }
