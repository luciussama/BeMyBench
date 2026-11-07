import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/native/native_core.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/dashboard.dart';
import '../history/bench_record.dart';
import '../history/history_store.dart';
import '../sensors/sensors_service.dart';
import 'benchmark_models.dart';
import 'benchmark_runner.dart';
import 'comparison_panel.dart';
import 'gpu_benchmark.dart';
import 'gpu_comparison_panel.dart';

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  final _sensors = SensorsService();

  final Set<String> _selected = {
    'cpu',
    'mem',
    'disk',
    if (GpuBenchmarkService.isSupported) 'gpu',
    if (GpuBenchmarkService.isSupported) 'gpu_render',
  };

  bool _show3dWindow = true;

  bool _running = false;
  String _current = '';
  String? _error;

  CpuBenchResult? _cpu;
  MemoryBenchResult? _mem;
  DiskBenchResult? _disk;
  GpuBenchResult? _gpuCompute;
  GpuBenchResult? _gpuRender;

  int _done = 0;
  int _elapsedSec = 0;
  Timer? _elapsedTimer;
  Timer? _chartTimer;

  final List<double> _cpuHistory = [];

  @override
  void initState() {
    super.initState();
    _startChartSampling();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _chartTimer?.cancel();
    unawaited(GpuBenchmarkService().close3dWindow());
    super.dispose();
  }

  void _startChartSampling() {
    _chartTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      try {
        final v = await _sensors.cpuPercentQuick();
        if (!mounted) return;
        setState(() {
          _cpuHistory.add(v);
          if (_cpuHistory.length > 90) _cpuHistory.removeAt(0);
        });
      } catch (_) {}
    });
  }

  double get _totalScore =>
      (_cpu?.score ?? 0) +
      (_mem?.score ?? 0) +
      (_disk?.score ?? 0) +
      (_gpuCompute?.score ?? 0) +
      (_gpuRender?.score ?? 0);

  String _fmtScore(double v) {
    if (v >= 100000) return '${(v / 1000).toStringAsFixed(0)}k';
    if (v >= 10000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  String _fmtTime(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _runAll() async {
    if (_running || _selected.isEmpty) return;

    setState(() {
      _running = true;
      _error = null;
      _done = 0;
      _elapsedSec = 0;
      _cpu = null;
      _mem = null;
      _disk = null;
      _gpuCompute = null;
      _gpuRender = null;
      _current = '';
    });

    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSec++);
    });

    try {
      if (_selected.contains('cpu')) {
        setState(() => _current = 'CPU');
        final r = await BenchmarkRunner.cpu(durationMs: 1000);
        if (!mounted) return;
        setState(() {
          _cpu = r;
          _done++;
        });
      }
      if (_selected.contains('mem')) {
        setState(() => _current = 'Memória');
        final r = await BenchmarkRunner.memory();
        if (!mounted) return;
        setState(() {
          _mem = r;
          _done++;
        });
      }
      if (_selected.contains('disk')) {
        setState(() => _current = 'Disco');
        final r = await BenchmarkRunner.disk();
        if (!mounted) return;
        setState(() {
          _disk = r;
          _done++;
        });
      }

      final hasGpuTests = _selected.contains('gpu') || _selected.contains('gpu_render');
      if (hasGpuTests && _show3dWindow) {
        unawaited(GpuBenchmarkService().open3dWindow(mode: 'benchmark'));
      }

      if (_selected.contains('gpu')) {
        setState(() => _current = 'GPU compute');
        final r = await GpuBenchmarkService().run(durationMs: 1500);
        if (!mounted) return;
        setState(() {
          _gpuCompute = r;
          _done++;
        });
      }
      if (_selected.contains('gpu_render')) {
        setState(() => _current = 'GPU render');
        final r = await GpuBenchmarkService().runRender(durationMs: 1500);
        if (!mounted) return;
        setState(() {
          _gpuRender = r;
          _done++;
        });
      }

      if (hasGpuTests && _show3dWindow) {
        unawaited(GpuBenchmarkService().close3dWindow());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      unawaited(GpuBenchmarkService().close3dWindow());
      _elapsedTimer?.cancel();
      if (_error == null && _done > 0 && mounted) {
        // Salva a execução no histórico local (falha de persistência não trava a UI)
        final record = BenchRecord(
          timestamp: DateTime.now(),
          cpuScore: _cpu?.score,
          cpuSingleMops: _cpu?.singleMops,
          cpuMultiMops: _cpu?.multiMops,
          memScore: _mem?.score,
          diskScore: _disk?.score,
          gpuComputeScore: _gpuCompute?.score,
          gpuRenderScore: _gpuRender?.score,
          gpuRenderOnePercentLow: _gpuRender?.onePercentLowFps,
          totalScore: _totalScore,
          gpuDevice: _gpuRender?.device ?? _gpuCompute?.device,
          osLabel: Platform.isMacOS ? 'macOS' : Platform.operatingSystem,
        );
        try {
          await BenchHistoryStore().append(record);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _running = false;
          _current = '';
        });
      }
    }
  }

  void _toggle(String key) {
    if (_running) return;
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
    });
  }

  String get _statusLabel {
    if (_running) return 'EXECUTANDO';
    if (_error != null) return 'ERRO';
    if (_done > 0) return 'CONCLUÍDO';
    return 'PRONTO';
  }

  Color get _statusColor {
    if (_running) return AppColors.orange;
    if (_error != null) return AppColors.red;
    if (_done > 0) return AppColors.green;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final totalTests = _selected.length;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // ---------------- Cabeçalho + CTA ----------------
        AppPanel(
          padding: const EdgeInsets.all(22),
          child: SectionHeader(
            icon: Icons.bolt,
            eyebrow: 'BMYBENCH STRESS PROTOCOL',
            eyebrowColor: AppColors.accent,
            title: 'Benchmark de hardware',
            description:
                'Executa os testes selecionados em sequência, medindo CPU, memória, disco '
                '${Platform.isMacOS ? "e GPU (compute + renderização Metal off-screen)" : (Platform.isAndroid ? "e aceleradores do dispositivo" : "e subsistemas de hardware")}. '
                'O resultado é salvo automaticamente no Histórico. O gráfico abaixo mostra a atividade real da CPU.',
            action: GradientActionButton(
              label: _running ? 'EXECUTANDO...' : 'INICIAR TESTES',
              icon: _running ? Icons.hourglass_top : Icons.play_arrow,
              onPressed: _running ? null : _runAll,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---------------- Seleção de testes ----------------
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FeatureChip(
              label: 'CPU (inteiros + float)',
              color: AppColors.accent,
              selected: _selected.contains('cpu'),
              enabled: !_running,
              onTap: () => _toggle('cpu'),
            ),
            FeatureChip(
              label: 'Memória (banda + latência)',
              color: AppColors.orange,
              selected: _selected.contains('mem'),
              enabled: !_running,
              onTap: () => _toggle('mem'),
            ),
            FeatureChip(
              label: 'Disco (sequencial)',
              color: AppColors.green,
              selected: _selected.contains('disk'),
              enabled: !_running,
              onTap: () => _toggle('disk'),
            ),
            FeatureChip(
              label: GpuBenchmarkService.isSupported
                  ? 'GPU compute (Metal)'
                  : 'GPU compute (em breve)',
              color: AppColors.violet,
              selected: _selected.contains('gpu'),
              enabled: !_running && GpuBenchmarkService.isSupported,
              onTap: () => _toggle('gpu'),
            ),
            FeatureChip(
              label: GpuBenchmarkService.isSupported
                  ? 'GPU render (jogos)'
                  : 'GPU render (em breve)',
              color: AppColors.red,
              selected: _selected.contains('gpu_render'),
              enabled: !_running && GpuBenchmarkService.isSupported,
              onTap: () => _toggle('gpu_render'),
            ),
            if (GpuBenchmarkService.isSupported && !Platform.isAndroid)
              FeatureChip(
                label: 'Janela 3D (Ao Vivo)',
                color: AppColors.orange,
                selected: _show3dWindow,
                enabled: !_running,
                onTap: () => setState(() => _show3dWindow = !_show3dWindow),
              ),
          ],
        ),
        const SizedBox(height: 20),

        // ---------------- Tiles ----------------
        MetricGrid(
          tiles: [
            MetricTile(
              icon: Icons.emoji_events_outlined,
              color: AppColors.accent,
              label: 'Score total',
              value: _done > 0 ? _fmtScore(_totalScore) : '—',
              caption: 'soma dos testes executados',
              valueColor: AppColors.accent,
            ),
            MetricTile(
              icon: Icons.checklist,
              color: AppColors.green,
              label: 'Testes',
              value: '$_done/$totalTests',
              caption: _running ? 'executando $_current' : 'selecionados',
              progress: totalTests == 0 ? 0 : _done / totalTests,
            ),
            MetricTile(
              icon: Icons.timer_outlined,
              color: AppColors.orange,
              label: 'Tempo',
              value: _fmtTime(_elapsedSec),
              caption: _running ? 'em execução' : 'última execução',
            ),
            MetricTile(
              icon: Icons.verified_outlined,
              color: _statusColor,
              label: 'Status',
              value: _statusLabel,
              caption: _error == null
                  ? '${BenchmarkRunner.defaultThreads} threads · Rust ${_safeVersion()}'
                  : 'veja o erro abaixo',
              valueColor: _statusColor,
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (_error != null) ...[
          AppPanel(
            color: const Color(0xFF2A1518),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: AppColors.red, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.red, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ---------------- Gráfico ----------------
        LineChartPanel(
          title: 'Atividade da CPU',
          legend: 'CPU (%)',
          icon: Icons.monitor_heart_outlined,
          values: _cpuHistory,
          maxValue: 100,
          emptyLabel:
              'Pressione "INICIAR TESTES" para gerar o gráfico dinâmico.',
          height: 190,
        ),
        const SizedBox(height: 16),

        // ---------------- Resultados detalhados ----------------
        if (_done > 0) ...[
          _ResultsPanel(
            cpu: _cpu,
            mem: _mem,
            disk: _disk,
            gpuCompute: _gpuCompute,
            gpuRender: _gpuRender,
          ),
          if (_cpu != null) ...[
            const SizedBox(height: 16),
            ComparisonPanel(cpu: _cpu!),
          ],
          if (_gpuCompute != null || _gpuRender != null) ...[
            const SizedBox(height: 16),
            GpuComparisonPanel(
              compute: _gpuCompute,
              render: _gpuRender,
            ),
          ],
        ],
      ],
    );
  }

  String _safeVersion() {
    try {
      return NativeCore.instance.version;
    } catch (_) {
      return 'n/d';
    }
  }
}

class _ResultsPanel extends StatelessWidget {
  final CpuBenchResult? cpu;
  final MemoryBenchResult? mem;
  final DiskBenchResult? disk;
  final GpuBenchResult? gpuCompute;
  final GpuBenchResult? gpuRender;

  const _ResultsPanel({
    this.cpu,
    this.mem,
    this.disk,
    this.gpuCompute,
    this.gpuRender,
  });

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.table_chart_outlined,
                  size: 16, color: AppColors.textSecondary),
              SizedBox(width: 8),
              Text(
                'Resultados detalhados',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (cpu != null) ...[
            _row('CPU single-core', '${cpu!.singleMops.toStringAsFixed(1)} Mops/s'),
            _row('CPU multi-core (${cpu!.threads} threads)',
                '${cpu!.multiMops.toStringAsFixed(1)} Mops/s'),
            _row('CPU score', cpu!.score.toStringAsFixed(1), strong: true),
          ],
          if (mem != null) ...[
            const Divider(height: 22),
            _row('RAM escrita', '${mem!.writeGbps.toStringAsFixed(2)} GB/s'),
            _row('RAM leitura', '${mem!.readGbps.toStringAsFixed(2)} GB/s'),
            _row('RAM cópia (R+W)', '${mem!.copyGbps.toStringAsFixed(2)} GB/s'),
            _row('RAM latência', '${mem!.latencyNs.toStringAsFixed(1)} ns'),
            _row('Memória score', mem!.score.toStringAsFixed(1), strong: true),
          ],
          if (disk != null) ...[
            const Divider(height: 22),
            _row('Disco escrita', '${disk!.writeMbps.toStringAsFixed(0)} MB/s'),
            _row('Disco leitura', '${disk!.readMbps.toStringAsFixed(0)} MB/s'),
            _row('Disco score', disk!.score.toStringAsFixed(0), strong: true),
          ],
          if (gpuCompute != null) ...[
            const Divider(height: 22),
            _row('GPU compute', gpuCompute!.device),
            _row(
              'GPU compute frames/s',
              '${gpuCompute!.fps.toStringAsFixed(1)} fps',
            ),
            _row(
              'GPU compute resolução',
              '${gpuCompute!.width}x${gpuCompute!.height} · '
                  '${gpuCompute!.iterations} iter',
            ),
            _row(
              'GPU compute score',
              gpuCompute!.score.toStringAsFixed(0),
              strong: true,
            ),
          ],
          if (gpuRender != null) ...[
            const Divider(height: 22),
            _row('GPU render (jogos)', gpuRender!.device),
            _row(
              'GPU render frames/s',
              '${gpuRender!.fps.toStringAsFixed(1)} fps',
            ),
            if (gpuRender!.hasFrameStats) ...[
              _row(
                'GPU render 1% low',
                '${gpuRender!.onePercentLowFps.toStringAsFixed(1)} fps',
              ),
              _row(
                'GPU render p99',
                '${gpuRender!.p99FrameMs.toStringAsFixed(2)} ms',
              ),
            ],
            _row(
              'GPU render cena',
              '${gpuRender!.instances} cubos · '
                  '${gpuRender!.trianglesPerFrame} triângulos',
            ),
            if (gpuRender!.msaaSamples > 0)
              _row(
                'GPU render pipeline',
                'MSAA ${gpuRender!.msaaSamples}x · HDR '
                    '${gpuRender!.hdr ? 'sim' : 'não'} · bloom '
                    '${gpuRender!.bloom ? 'sim' : 'não'} · '
                    '${gpuRender!.passes} passes',
              ),
            _row(
              'GPU render score',
              gpuRender!.score.toStringAsFixed(0),
              strong: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: strong ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: strong ? AppColors.accent : AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
