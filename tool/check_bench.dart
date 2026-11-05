// Script de verificação manual dos benchmarks (fora do app).
//
//   ../../flutter/bin/dart run tool/check_bench.dart

import 'dart:io';

import 'package:bemybench/features/benchmark/benchmark_runner.dart';

Future<void> main() async {
  stdout.writeln('--- BMyBench :: Benchmark Probe ---');
  stdout.writeln('threads: ${BenchmarkRunner.defaultThreads}');

  stdout.writeln('\n[CPU] rodando 1s...');
  final cpu = await BenchmarkRunner.cpu(durationMs: 1000);
  stdout.writeln('single: ${cpu.singleMops.toStringAsFixed(1)} Mops/s');
  stdout.writeln('multi : ${cpu.multiMops.toStringAsFixed(1)} Mops/s (${cpu.threads} threads)');
  stdout.writeln('score : ${cpu.score.toStringAsFixed(1)}');

  stdout.writeln('\n[Memoria] 128 MB...');
  final mem = await BenchmarkRunner.memory(sizeMb: 128);
  stdout.writeln('escrita : ${mem.writeGbps.toStringAsFixed(2)} GB/s');
  stdout.writeln('leitura : ${mem.readGbps.toStringAsFixed(2)} GB/s');
  stdout.writeln('copia   : ${mem.copyGbps.toStringAsFixed(2)} GB/s');
  stdout.writeln('latencia: ${mem.latencyNs.toStringAsFixed(1)} ns');

  stdout.writeln('\n[Disco] 128 MB...');
  final disk = await BenchmarkRunner.disk(sizeMb: 128);
  stdout.writeln('escrita : ${disk.writeMbps.toStringAsFixed(0)} MB/s');
  stdout.writeln('leitura : ${disk.readMbps.toStringAsFixed(0)} MB/s');
}
