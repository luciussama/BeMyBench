import 'package:flutter/material.dart';

import '../../core/native/native_core.dart';
import 'benchmark_models.dart';
import 'benchmark_runner.dart';

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  BenchStatus _cpuStatus = BenchStatus.idle;
  BenchStatus _memStatus = BenchStatus.idle;
  BenchStatus _diskStatus = BenchStatus.idle;

  CpuBenchResult? _cpu;
  MemoryBenchResult? _mem;
  DiskBenchResult? _disk;
  String? _error;

  bool get _anyRunning =>
      _cpuStatus == BenchStatus.running ||
      _memStatus == BenchStatus.running ||
      _diskStatus == BenchStatus.running;

  Future<void> _runCpu() async {
    setState(() {
      _cpuStatus = BenchStatus.running;
      _error = null;
    });
    try {
      final r = await BenchmarkRunner.cpu(durationMs: 1000);
      if (!mounted) return;
      setState(() {
        _cpu = r;
        _cpuStatus = BenchStatus.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'CPU: $e';
        _cpuStatus = BenchStatus.error;
      });
    }
  }

  Future<void> _runMem() async {
    setState(() {
      _memStatus = BenchStatus.running;
      _error = null;
    });
    try {
      final r = await BenchmarkRunner.memory();
      if (!mounted) return;
      setState(() {
        _mem = r;
        _memStatus = BenchStatus.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Memória: $e';
        _memStatus = BenchStatus.error;
      });
    }
  }

  Future<void> _runDisk() async {
    setState(() {
      _diskStatus = BenchStatus.running;
      _error = null;
    });
    try {
      final r = await BenchmarkRunner.disk();
      if (!mounted) return;
      setState(() {
        _disk = r;
        _diskStatus = BenchStatus.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Disco: $e';
        _diskStatus = BenchStatus.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Benchmark — score próprio'),
            subtitle: Text(
              'Core em Rust (${NativeCore.isAvailable ? "carregado" : "indisponível"}) '
              '— não é Geekbench/Cinebench.\n'
              '${BenchmarkRunner.defaultThreads} threads detectadas.',
            ),
          ),
        ),
        if (_error != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Erro'),
              subtitle: Text(_error!),
            ),
          ),
        _BenchCard(
          icon: Icons.memory,
          title: 'CPU',
          subtitle: 'Single-core + multi-core (janela de 1s cada)',
          status: _cpuStatus,
          onRun: _anyRunning ? null : _runCpu,
          results: _cpu == null
              ? null
              : {
                  'Single-core': '${_cpu!.singleMops.toStringAsFixed(1)} Mops/s',
                  'Multi-core (${_cpu!.threads} threads)':
                      '${_cpu!.multiMops.toStringAsFixed(1)} Mops/s',
                  'Score': _cpu!.score.toStringAsFixed(1),
                },
        ),
        _BenchCard(
          icon: Icons.memory_outlined,
          title: 'Memória',
          subtitle: 'Banda sequencial (GB/s) + latência aleatória (ns)',
          status: _memStatus,
          onRun: _anyRunning ? null : _runMem,
          results: _mem == null
              ? null
              : {
                  'Escrita': '${_mem!.writeGbps.toStringAsFixed(2)} GB/s',
                  'Leitura': '${_mem!.readGbps.toStringAsFixed(2)} GB/s',
                  'Cópia (R+W)': '${_mem!.copyGbps.toStringAsFixed(2)} GB/s',
                  'Latência': '${_mem!.latencyNs.toStringAsFixed(1)} ns',
                  'Score': _mem!.score.toStringAsFixed(1),
                },
        ),
        _BenchCard(
          icon: Icons.storage,
          title: 'Disco',
          subtitle: 'Leitura/escrita sequencial (arquivo temporário de 256 MB)',
          status: _diskStatus,
          onRun: _anyRunning ? null : _runDisk,
          results: _disk == null
              ? null
              : {
                  'Escrita': '${_disk!.writeMbps.toStringAsFixed(0)} MB/s',
                  'Leitura': '${_disk!.readMbps.toStringAsFixed(0)} MB/s',
                  'Tamanho': '${_disk!.sizeMb} MB',
                  'Score': _disk!.score.toStringAsFixed(0),
                },
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.view_in_ar),
            title: const Text('GPU'),
            subtitle: const Text(
              'MVP: nome + FPS simples (Metal/Vulkan). FurMark completo na V1.1.',
            ),
            trailing: const Text('em breve'),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Dica: feche apps pesados para um score mais consistente.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _BenchCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final BenchStatus status;
  final VoidCallback? onRun;
  final Map<String, String>? results;

  const _BenchCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.onRun,
    this.results,
  });

  @override
  Widget build(BuildContext context) {
    final running = status == BenchStatus.running;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
                if (running)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: onRun,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(results == null ? 'Rodar' : 'Rodar de novo'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            if (running) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (results != null && !running) ...[
              const Divider(height: 24),
              for (final e in results!.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key),
                      Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
