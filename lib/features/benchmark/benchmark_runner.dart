import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import '../../core/native/native_core.dart';
import 'benchmark_models.dart';

/// Executa benchmarks fora da UI isolate para não travar a interface.
class BenchmarkRunner {
  static int get defaultThreads => Platform.numberOfProcessors;

  /// CPU: roda dentro de um isolate separado (o Rust cria as threads).
  static Future<CpuBenchResult> cpu({
    int durationMs = 1000,
    int? threads,
  }) {
    final t = threads ?? defaultThreads;
    return Isolate.run(() => _cpuSync(durationMs, t));
  }

  /// Memória: banda sequencial + latência de acesso aleatório.
  static Future<MemoryBenchResult> memory({
    int sizeMb = 256,
    int chaseEntries = 4 * 1024 * 1024,
  }) {
    return Isolate.run(() => _memorySync(sizeMb, chaseEntries));
  }

  /// Disco: leitura/escrita sequencial num arquivo temporário (Dart puro).
  static Future<DiskBenchResult> disk({int sizeMb = 256}) async {
    final dir = await Directory.systemTemp.createTemp('bmb_disk_');
    final file = File('${dir.path}/bench.bin');
    try {
      final data = Uint8List(sizeMb * 1024 * 1024);
      // Preenche para evitar páginas esparsas/compressão artificial
      final rnd = Random(42);
      final chunk = Uint32List.view(data.buffer);
      for (var i = 0; i < chunk.length; i++) {
        chunk[i] = rnd.nextInt(1 << 32);
      }

      final sw = Stopwatch()..start();
      await file.writeAsBytes(data, flush: true);
      sw.stop();
      final writeSecs = sw.elapsedMicroseconds / 1e6;

      final readSw = Stopwatch()..start();
      final readBack = await file.readAsBytes();
      readSw.stop();
      final readSecs = readSw.elapsedMicroseconds / 1e6;

      if (readBack.length != data.length) {
        throw StateError('leitura incompleta');
      }

      final mb = sizeMb.toDouble();
      final writeMbps = mb / writeSecs;
      final readMbps = mb / readSecs;

      return DiskBenchResult(
        writeMbps: writeMbps,
        readMbps: readMbps,
        sizeMb: sizeMb,
        score: (writeMbps + readMbps) / 10,
      );
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

CpuBenchResult _cpuSync(int durationMs, int threads) {
  final json = NativeCore.instance.runCpu(
    durationMs: durationMs,
    threads: threads,
  );
  final map = jsonDecode(json) as Map<String, dynamic>;
  return CpuBenchResult.fromJson(map);
}

MemoryBenchResult _memorySync(int sizeMb, int chaseEntries) {
  final json = NativeCore.instance.runMemory(
    sizeMb: sizeMb,
    chaseEntries: chaseEntries,
  );
  final map = jsonDecode(json) as Map<String, dynamic>;
  return MemoryBenchResult.fromJson(map);
}
