import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/dashboard.dart';
import '../benchmark/gpu_benchmark.dart';
import '../sensors/sensors_service.dart';

/// Estresse contínuo de GPU: roda o mesmo teste de render do benchmark em
/// passos de 1 segundo e registra a taxa de fps ao longo do tempo.
///
/// A queda de fps entre o pico e o pior valor amostrado funciona como proxy
/// de thermal throttling — o macOS não expõe temperatura de GPU sem acesso
/// privilegiado.
class StressScreen extends StatefulWidget {
  const StressScreen({super.key});

  @override
  State<StressScreen> createState() => _StressScreenState();
}

class _StressScreenState extends State<StressScreen> {
  final _gpu = GpuBenchmarkService();
  final _sensors = SensorsService();

  final List<double> _fpsHistory = [];
  final List<double> _cpuHistory = [];

  Timer? _ticker;
  DateTime? _startedAt;

  /// 30, 60 ou 0 (contínuo).
  int _targetSeconds = 30;

  bool _running = false;
  bool _stopping = false;
  int _elapsed = 0;
  double _currentFps = 0;
  double _peakFps = 0;
  double _latestP99 = 0;
  double _latestOnePercentLow = 0;
  String? _error;

  @override
  void dispose() {
    _ticker?.cancel();
    _running = false;
    super.dispose();
  }

  int get _samples => _fpsHistory.length;

  double get _avgFps =>
      _fpsHistory.isEmpty
      ? 0.0
      : _fpsHistory.reduce((a, b) => a + b) / _fpsHistory.length;

  double get _minFps =>
      _fpsHistory.isEmpty
      ? 0.0
      : _fpsHistory.reduce((a, b) => a < b ? a : b);

  double get _dropPercent {
    if (_peakFps <= 0 || _minFps <= 0) return 0;
    return (_peakFps - _minFps) / _peakFps * 100;
  }

  String get _verdict {
    if (_fpsHistory.length < 5) return 'Aguardando amostras...';
    final drop = _dropPercent;
    if (drop < 8) return 'Estável — sem queda relevante';
    if (drop < 18) return 'Queda moderada — verifique thermal';
    return 'Throttling severo ou instabilidade';
  }

  Color get _verdictColor {
    if (_fpsHistory.length < 5) return AppColors.textSecondary;
    final drop = _dropPercent;
    if (drop < 8) return AppColors.green;
    if (drop < 18) return AppColors.orange;
    return AppColors.red;
  }

  Future<void> _start() async {
    if (_running) return;
    setState(() {
      _fpsHistory.clear();
      _cpuHistory.clear();
      _running = true;
      _stopping = false;
      _elapsed = 0;
      _currentFps = 0;
      _peakFps = 0;
      _latestP99 = 0;
      _latestOnePercentLow = 0;
      _error = null;
      _startedAt = DateTime.now();
    });

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final started = _startedAt;
      if (started != null) {
        setState(() => _elapsed = DateTime.now().difference(started).inSeconds);
      }
    });

    while (_running && mounted) {
      if (_targetSeconds > 0 && _elapsed >= _targetSeconds) break;
      try {
        final result = await _gpu.runRender(durationMs: 1000);
        double cpu = 0;
        try {
          cpu = await _sensors.cpuPercentQuick();
        } catch (_) {}
        if (!mounted || !_running) break;
        setState(() {
          _currentFps = result.fps;
          _peakFps = _peakFps == 0 || result.fps > _peakFps ? result.fps : _peakFps;
          _latestP99 = result.p99FrameMs;
          _latestOnePercentLow = result.onePercentLowFps;
          _fpsHistory.add(result.fps);
          _cpuHistory.add(cpu);
          if (_fpsHistory.length > 120) _fpsHistory.removeAt(0);
          if (_cpuHistory.length > 120) _cpuHistory.removeAt(0);
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = e.toString());
        break;
      }
    }

    _finish();
  }

  void _finish() {
    _ticker?.cancel();
    if (!mounted) return;
    setState(() {
      _running = false;
      _stopping = false;
      final started = _startedAt;
      _elapsed = started == null ? _elapsed : DateTime.now().difference(started).inSeconds;
    });
  }

  void _stop() {
    if (!_running) return;
    setState(() => _stopping = true);
    _running = false;
  }

  String _fmtDuration(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final maxFps = _fpsHistory.isEmpty
        ? 100.0
        : niceMax(_fpsHistory.reduce((a, b) => a > b ? a : b) * 1.15);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        AppPanel(
          padding: const EdgeInsets.all(22),
          child: SectionHeader(
            icon: Icons.whatshot,
            eyebrow: 'BMYBENCH CONTINUOUS STRESS',
            eyebrowColor: AppColors.orange,
            title: 'Estresse contínuo de GPU',
            description:
                'Renderiza a cena 3D em passos de 1 segundo e registra o fps ao '
                'longo do tempo. Uma queda entre o pico e o pior valor amostrado '
                'indica throttling térmico (proxy, já que o macOS não expõe a '
                'temperatura da GPU sem acesso privilegiado).',
            action: GradientActionButton(
              label: _running
                  ? (_stopping ? 'PARANDO...' : 'PARAR')
                  : 'INICIAR ESTRESSE',
              icon: _running ? Icons.stop_circle : Icons.play_arrow,
              onPressed: _running ? _stop : _start,
              colors: _running
                  ? const [Color(0xFF7F1D1D), Color(0xFFEF4444)]
                  : const [Color(0xFFC2410C), Color(0xFFF97316)],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Duração
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final d in const [30, 60, 0])
              FeatureChip(
                label: d == 0 ? 'Contínuo (sem limite)' : '$d segundos',
                color: d == 0 ? AppColors.red : AppColors.orange,
                selected: _targetSeconds == d,
                enabled: !_running,
                onTap: () => setState(() => _targetSeconds = d),
              ),
          ],
        ),
        const SizedBox(height: 20),

        // Tiles
        MetricGrid(
          tiles: [
            MetricTile(
              icon: Icons.speed,
              color: AppColors.orange,
              label: 'FPS atual',
              value: _samples > 0 ? _currentFps.toStringAsFixed(1) : '—',
              caption: 'média ${_samples > 0 ? _avgFps.toStringAsFixed(1) : "—"}',
              valueColor: AppColors.orange,
            ),
            MetricTile(
              icon: Icons.trending_down,
              color: _dropPercent >= 18
                  ? AppColors.red
                  : (_dropPercent >= 8 ? AppColors.orange : AppColors.green),
              label: 'Queda do pico',
              value: _samples > 0 ? '${_dropPercent.toStringAsFixed(1)}%' : '—',
              caption: _verdict,
              valueColor: _verdictColor,
            ),
            MetricTile(
              icon: Icons.timer_outlined,
              color: AppColors.accent,
              label: 'Tempo',
              value: _fmtDuration(_elapsed),
              caption: _running
                  ? (_targetSeconds == 0 ? 'contínuo' : 'de ${_fmtDuration(_targetSeconds)}')
                  : 'última execução',
            ),
            MetricTile(
              icon: Icons.numbers,
              color: AppColors.violet,
              label: 'Amostras',
              value: '$_samples',
              caption: '1 amostra por segundo',
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Gráfico de FPS
        LineChartPanel(
          title: 'FPS ao longo do estresse',
          legend: 'FPS',
          icon: Icons.monitor_heart_outlined,
          values: _fpsHistory,
          maxValue: maxFps,
          emptyLabel:
              'Inicie o estresse para gerar a curva de estabilidade.',
          color: AppColors.orange,
          height: 190,
        ),
        const SizedBox(height: 16),

        // Gráfico de CPU
        LineChartPanel(
          title: 'Carga da CPU durante o teste',
          legend: 'CPU (%)',
          icon: Icons.memory,
          values: _cpuHistory,
          maxValue: 100,
          emptyLabel:
              'Inicie o estresse para ver a CPU acompanhar a GPU.',
          color: AppColors.accent,
          height: 150,
        ),
        const SizedBox(height: 16),

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

        // Resumo
        if (_samples > 0)
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.assessment_outlined,
                        size: 16, color: AppColors.textSecondary),
                    SizedBox(width: 8),
                    Text(
                      'Resumo',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _row('Média', '${_avgFps.toStringAsFixed(1)} fps'),
                _row('Pico', '${_peakFps.toStringAsFixed(1)} fps'),
                _row('Pior amostra', '${_minFps.toStringAsFixed(1)} fps'),
                _row('p99 (último passo)',
                    '${_latestP99.toStringAsFixed(2)} ms'),
                _row(
                  '1% low (último passo)',
                  '${_latestOnePercentLow.toStringAsFixed(1)} fps',
                ),
                const Divider(height: 22),
                const Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 14, color: AppColors.textMuted),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Thermal throttling é inferido pela queda de fps. '
                        'O macOS não expõe temperatura de GPU sem execução com '
                        'privilégios (V1.1 pode usar IOKit/SMC).',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
