import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../battery/battery_service.dart';
import '../sensors/sensors_service.dart';
import 'hardware_service.dart';

/// Dashboard "Hardware": card herói + tiles de status + bloco em 2 colunas.
/// Layout inspirado em dashboards técnicos de desktop, adaptado ao BMyBench.
class HardwareScreen extends StatefulWidget {
  final VoidCallback? onRunCpu;

  const HardwareScreen({super.key, this.onRunCpu});

  @override
  State<HardwareScreen> createState() => _HardwareScreenState();
}

class _HardwareScreenState extends State<HardwareScreen> {
  final _hardwareService = HardwareService();
  final _sensorsService = SensorsService();
  final _batteryService = BatteryService();

  HardwareInfo? _info;
  SensorsSnapshot? _sensors;
  BatteryInfo? _battery;
  Timer? _timer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tickSensors());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final info = await _hardwareService.collect();
    final sensors = await _sensorsService.collect();
    final battery = await _batteryService.collect();
    if (!mounted) return;
    setState(() {
      _info = info;
      _sensors = sensors;
      _battery = battery;
      _loading = false;
    });
  }

  Future<void> _tickSensors() async {
    try {
      final s = await _sensorsService.collect();
      if (!mounted) return;
      setState(() => _sensors = s);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _info == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        final pad = wide ? 28.0 : 16.0;

        return ListView(
          padding: EdgeInsets.all(pad),
          children: [
            _HeroCard(
              info: _info!,
              wide: wide,
              onRunCpu: widget.onRunCpu,
            ),
            const SizedBox(height: 22),
            _StatusTiles(
              wide: wide,
              sensors: _sensors,
              info: _info!,
              battery: _battery,
            ),
            const SizedBox(height: 22),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _RealtimeCard(info: _info!, battery: _battery)),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: const _LimitsCard()),
                ],
              )
            else ...[
              _RealtimeCard(info: _info!, battery: _battery),
              const SizedBox(height: 16),
              const _LimitsCard(),
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Card herói
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  final HardwareInfo info;
  final bool wide;
  final VoidCallback? onRunCpu;

  const _HeroCard({
    required this.info,
    required this.wide,
    this.onRunCpu,
  });

  void _soon(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what chega na V1.1 (com confirmação e whitelist).')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 4,
          children: [
            Text(
              '${info.hostname}.local',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                letterSpacing: 0.3,
              ),
            ),
            Text(
              '·  ${info.archLabel}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.circle, size: 7, color: AppColors.green),
                SizedBox(width: 5),
                Text(
                  'Ativo',
                  style: TextStyle(color: AppColors.green, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          info.osLabel,
          style: TextStyle(
            fontSize: wide ? 34 : 26,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Kernel / Release: ${info.kernel} (${info.arch})  ·  '
          'Modelo: ${info.model}  ·  Chip: ${info.chip}  ·  '
          '${info.cores} threads',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    );

    final buttons = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: onRunCpu,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Testar CPU'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: const Color(0xFF04212A),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _soon(context, 'Limpeza de disco'),
          icon: const Icon(Icons.cleaning_services_outlined, size: 18),
          label: const Text('Limpar Disco'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _soon(context, 'Boost de RAM'),
          icon: const Icon(Icons.bolt, size: 18),
          label: const Text('Boost RAM'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.orange,
            side: BorderSide(color: AppColors.orange.withValues(alpha: 0.5)),
          ),
        ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(wide ? 24 : 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF121C26), Color(0xFF0D151D)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: texts),
                const SizedBox(width: 24),
                buttons,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [texts, const SizedBox(height: 18), buttons],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tiles de status
// ---------------------------------------------------------------------------

class _StatusTiles extends StatelessWidget {
  final bool wide;
  final SensorsSnapshot? sensors;
  final HardwareInfo info;
  final BatteryInfo? battery;

  const _StatusTiles({
    required this.wide,
    required this.sensors,
    required this.info,
    required this.battery,
  });

  @override
  Widget build(BuildContext context) {
    final cpu = sensors?.cpuUsagePercent ?? 0;
    final ramPct = sensors?.ramUsagePercent ?? 0;
    final ramUsed = sensors?.ramUsedLabel ?? '—';
    final diskPct = info.diskTotalBytes == 0
        ? 0.0
        : 100 - info.diskFreePercent;

    final tiles = <Widget>[
      _Tile(
        icon: Icons.memory,
        iconColor: AppColors.accent,
        label: 'Carga da CPU',
        value: sensors == null ? '—' : '${cpu.toStringAsFixed(0)}%',
        trailing: battery != null ? '${battery!.cycleCount} ciclos' : null,
        progress: cpu / 100,
        progressColor: AppColors.loadColor(cpu),
      ),
      _Tile(
        icon: Icons.layers_outlined,
        iconColor: AppColors.orange,
        label: 'Memória RAM',
        value: sensors == null ? '—' : '$ramUsed / ${info.ramTotalLabel}',
        trailing: null,
        progress: ramPct / 100,
        progressColor: AppColors.loadColor(ramPct),
      ),
      _Tile(
        icon: Icons.view_in_ar,
        iconColor: AppColors.violet,
        label: 'GPU',
        value: info.chip.replaceAll('Apple ', ''),
        trailing: 'unificada',
        progress: null,
        progressColor: AppColors.violet,
      ),
      _Tile(
        icon: Icons.storage,
        iconColor: AppColors.green,
        label: 'Disco livre',
        value: info.diskTotalBytes == 0 ? '—' : info.diskFreeLabel,
        trailing: info.diskTotalBytes == 0 ? null : 'de ${info.diskTotalLabel}',
        progress: diskPct / 100,
        progressColor: diskPct > 85 ? AppColors.red : AppColors.green,
      ),
    ];

    if (wide) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              Expanded(child: tiles[i]),
              if (i != tiles.length - 1) const SizedBox(width: 14),
            ],
          ],
        ),
      );
    }

    // Estreito: 2 por linha
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[0]),
              const SizedBox(width: 12),
              Expanded(child: tiles[1]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[2]),
              const SizedBox(width: 12),
              Expanded(child: tiles[3]),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? trailing;
  final double? progress;
  final Color progressColor;

  const _Tile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.progressColor,
    this.trailing,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress ?? 0,
              minHeight: 5,
              backgroundColor: AppColors.borderSoft,
              color: progressColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bloco inferior em duas colunas
// ---------------------------------------------------------------------------

class _RealtimeCard extends StatelessWidget {
  final HardwareInfo info;
  final BatteryInfo? battery;

  const _RealtimeCard({required this.info, required this.battery});

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      ('Núcleos', '${info.cores} threads reais via hardware'),
      ('Memória', '${info.ramTotalLabel} ${info.chip.contains('Apple') ? 'unificada' : 'instalada'}'),
      if (battery != null)
        (
          'Bateria',
          '${battery!.health.toStringAsFixed(1)}% de saúde · ${battery!.cycleCount} ciclos'
        ),
      ('Sensores', 'CPU e RAM atualizados a cada 2 segundos'),
      ('Benchmark', 'Motor em Rust com score próprio (FFI nativo)'),
    ];

    return _Panel(
      title: 'Lido em tempo real no seu hardware',
      titleColor: AppColors.accent,
      icon: Icons.check_circle_outline,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check, size: 15, color: AppColors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                      children: [
                        TextSpan(
                          text: '${item.$1}: ',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: item.$2),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LimitsCard extends StatelessWidget {
  const _LimitsCard();

  @override
  Widget build(BuildContext context) {
    const items = <(String, String)>[
      ('Temperatura e ventoinha', 'exigem acesso privilegiado no Apple Silicon'),
      ('SMART do SSD', 'requer helper com permissão de administrador'),
      ('Clock da RAM', 'não é exposto em memória unificada'),
      ('Limpeza e atualizações', 'chegam na V1.1 com whitelist e confirmação'),
    ];

    return _Panel(
      title: 'Limites por plataforma',
      titleColor: AppColors.orange,
      icon: Icons.info_outline,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.remove_circle_outline,
                    size: 15, color: AppColors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                      children: [
                        TextSpan(
                          text: '${item.$1}: ',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: item.$2),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Color titleColor;
  final IconData icon;
  final List<Widget> children;

  const _Panel({
    required this.title,
    required this.titleColor,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: titleColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
