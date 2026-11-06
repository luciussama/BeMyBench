import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/dashboard.dart';
import '../battery/battery_service.dart';
import '../benchmark/gpu_benchmark.dart';
import '../cleaner/clean_disk_dialog.dart';
import '../cleaner/ram_boost_dialog.dart';
import '../sensors/sensors_service.dart';
import '../storage/storage_panel.dart';
import 'hardware_models.dart';
import 'hardware_service.dart';

/// Tela "Hardware" granular com inspeção detalhada por subsistema.
/// Adapta a leitura e exibição com base na plataforma (macOS, Linux, Windows, Android).
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
  GpuInfo? _gpuInfo;
  Timer? _timer;
  bool _loading = true;

  // Categoria ativa
  int _selectedCategoryIndex = 0;

  static const _categories = [
    ('Visão Geral', Icons.dashboard_outlined),
    ('Processador', Icons.memory),
    ('Memória RAM', Icons.layers_outlined),
    ('Gráficos & Telas', Icons.videogame_asset_outlined),
    ('Placa-Mãe & EFI', Icons.developer_board),
    ('USB & Conexões', Icons.usb),
    ('Armazenamento', Icons.storage),
    ('Rede', Icons.wifi),
    ('Plataformas', Icons.devices_other),
  ];

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
    final gpu = await GpuBenchmarkService().info();
    if (!mounted) return;
    setState(() {
      _info = info;
      _sensors = sensors;
      _battery = battery;
      _gpuInfo = gpu;
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
        final wide = constraints.maxWidth >= 960;
        final pad = wide ? 24.0 : 16.0;

        return ListView(
          padding: EdgeInsets.all(pad),
          children: [
            _HeroCard(
              info: _info!,
              wide: wide,
              onRunCpu: widget.onRunCpu,
              onCleanDisk: () => CleanDiskDialog.show(
                context,
                onCompleted: () => _bootstrap(),
              ),
              onBoostRam: () => RamBoostDialog.show(
                context,
                onCompleted: () => _tickSensors(),
              ),
            ),
            const SizedBox(height: 18),
            _StatusTiles(
              wide: wide,
              sensors: _sensors,
              info: _info!,
              battery: _battery,
              gpu: _gpuInfo,
            ),
            const SizedBox(height: 20),

            // Barra de abas/filtros de categorias
            _CategoryTabBar(
              selectedIndex: _selectedCategoryIndex,
              categories: _categories,
              onSelect: (index) => setState(() => _selectedCategoryIndex = index),
            ),
            const SizedBox(height: 18),

            // Conteúdo dinâmico da categoria selecionada
            _buildCategoryContent(_selectedCategoryIndex, wide),
          ],
        );
      },
    );
  }

  Widget _buildCategoryContent(int index, bool wide) {
    final info = _info!;

    switch (index) {
      case 0:
        return _OverviewTab(info: info, battery: _battery, wide: wide);
      case 1:
        return _CpuTab(cpu: info.cpu, wide: wide);
      case 2:
        return _MemoryTab(memory: info.memory, wide: wide);
      case 3:
        return _GpuTab(gpu: info.gpu, wide: wide);
      case 4:
        return _MotherboardTab(motherboard: info.motherboard, wide: wide);
      case 5:
        return _UsbTab(usbControllers: info.usbControllers, wide: wide);
      case 6:
        return _StorageTab(disks: info.storageDisks, wide: wide);
      case 7:
        return _NetworkTab(adapters: info.networkAdapters, wide: wide);
      case 8:
        return _PeculiaritiesTab(peculiarities: info.peculiarities, wide: wide);
      default:
        return _OverviewTab(info: info, battery: _battery, wide: wide);
    }
  }
}

// ---------------------------------------------------------------------------
// Barra de navegação por categorias
// ---------------------------------------------------------------------------

class _CategoryTabBar extends StatefulWidget {
  final int selectedIndex;
  final List<(String, IconData)> categories;
  final ValueChanged<int> onSelect;

  const _CategoryTabBar({
    required this.selectedIndex,
    required this.categories,
    required this.onSelect,
  });

  @override
  State<_CategoryTabBar> createState() => _CategoryTabBarState();
}

class _CategoryTabBarState extends State<_CategoryTabBar> {
  final ScrollController _scrollController = ScrollController();
  late List<GlobalKey> _itemKeys;

  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  bool _hasOverflow = false;

  @override
  void initState() {
    super.initState();
    _itemKeys = List.generate(widget.categories.length, (_) => GlobalKey());
    _scrollController.addListener(_updateScrollMetrics);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollMetrics();
      _scrollToIndex(widget.selectedIndex);
    });
  }

  @override
  void didUpdateWidget(covariant _CategoryTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categories.length != widget.categories.length) {
      _itemKeys = List.generate(widget.categories.length, (_) => GlobalKey());
    }
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _scrollToIndex(widget.selectedIndex);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollMetrics());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollMetrics);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollMetrics() {
    if (!mounted || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final canLeft = pos.pixels > 4;
    final canRight = pos.pixels < (pos.maxScrollExtent - 4);
    final hasOverflow = pos.maxScrollExtent > 4;

    if (canLeft != _canScrollLeft ||
        canRight != _canScrollRight ||
        hasOverflow != _hasOverflow) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
        _hasOverflow = hasOverflow;
      });
    }
  }

  void _scrollDelta(double delta) {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToIndex(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index < 0 || index >= _itemKeys.length) return;
      final ctx = _itemKeys[index].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _updateScrollMetrics();
        return false;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollMetrics());
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                if (_hasOverflow) ...[
                  _ScrollNavButton(
                    icon: Icons.chevron_left,
                    tooltip: 'Rolar abas para a esquerda',
                    enabled: _canScrollLeft,
                    onTap: () => _scrollDelta(-220),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent && _scrollController.hasClients) {
                        final delta = event.scrollDelta.dy != 0
                            ? event.scrollDelta.dy
                            : event.scrollDelta.dx;
                        final target = (_scrollController.offset + delta).clamp(
                          0.0,
                          _scrollController.position.maxScrollExtent,
                        );
                        _scrollController.jumpTo(target);
                      }
                    },
                    child: RawScrollbar(
                      controller: _scrollController,
                      thumbColor: AppColors.accent.withValues(alpha: 0.35),
                      radius: const Radius.circular(4),
                      thickness: 3,
                      padding: const EdgeInsets.only(bottom: 2),
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            for (var i = 0; i < widget.categories.length; i++) ...[
                              _CategoryChip(
                                key: _itemKeys[i],
                                label: widget.categories[i].$1,
                                icon: widget.categories[i].$2,
                                isSelected: widget.selectedIndex == i,
                                onTap: () {
                                  widget.onSelect(i);
                                  _scrollToIndex(i);
                                },
                              ),
                              if (i != widget.categories.length - 1)
                                const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_hasOverflow) ...[
                  const SizedBox(width: 8),
                  _ScrollNavButton(
                    icon: Icons.chevron_right,
                    tooltip: 'Rolar abas para a direita',
                    enabled: _canScrollRight,
                    onTap: () => _scrollDelta(220),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ScrollNavButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _ScrollNavButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: enabled ? AppColors.card : AppColors.card.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 34,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: enabled ? AppColors.border : AppColors.borderSoft.withValues(alpha: 0.4),
              ),
            ),
            child: Icon(
              icon,
              size: 20,
              color: enabled ? AppColors.accent : AppColors.textMuted.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.accent.withValues(alpha: 0.15) : AppColors.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.borderSoft,
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppColors.accent : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card Herói
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  final HardwareInfo info;
  final bool wide;
  final VoidCallback? onRunCpu;
  final VoidCallback? onCleanDisk;
  final VoidCallback? onBoostRam;

  const _HeroCard({
    required this.info,
    required this.wide,
    this.onRunCpu,
    this.onCleanDisk,
    this.onBoostRam,
  });

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
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
            fontSize: wide ? 32 : 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Kernel / Release: ${info.kernel} (${info.arch})  ·  '
          'Modelo: ${info.motherboard.modelName} (${info.model})  ·  '
          'Chip: ${info.chip}  ·  ${info.cores} threads',
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
          onPressed: onCleanDisk,
          icon: const Icon(Icons.cleaning_services_outlined, size: 18),
          label: const Text('Limpar Disco'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onBoostRam,
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
// Tiles de status superiores
// ---------------------------------------------------------------------------

class _StatusTiles extends StatelessWidget {
  final bool wide;
  final SensorsSnapshot? sensors;
  final HardwareInfo info;
  final BatteryInfo? battery;
  final GpuInfo? gpu;

  const _StatusTiles({
    required this.wide,
    required this.sensors,
    required this.info,
    required this.battery,
    this.gpu,
  });

  @override
  Widget build(BuildContext context) {
    final cpu = sensors?.cpuUsagePercent ?? 0;
    final ramPct = sensors?.ramUsagePercent ?? 0;
    final ramUsed = sensors?.ramUsedLabel ?? '—';
    final diskPct = info.diskTotalBytes == 0 ? 0.0 : 100 - info.diskFreePercent;

    final tiles = <Widget>[
      MetricTile(
        icon: Icons.memory,
        color: AppColors.accent,
        label: 'Carga da CPU',
        value: sensors == null ? '—' : '${cpu.toStringAsFixed(0)}%',
        trailing: battery != null ? '${battery!.cycleCount} ciclos' : null,
        progress: cpu / 100,
        valueColor: AppColors.loadColor(cpu),
      ),
      MetricTile(
        icon: Icons.layers_outlined,
        color: AppColors.orange,
        label: 'Memória RAM',
        value: sensors == null ? '—' : '$ramUsed / ${info.ramTotalLabel}',
        trailing: info.memory.type,
        progress: ramPct / 100,
        valueColor: AppColors.loadColor(ramPct),
      ),
      MetricTile(
        icon: Icons.view_in_ar,
        color: AppColors.violet,
        label: 'GPU',
        value: gpu?.name.replaceAll('Apple ', '') ?? info.chip.replaceAll('Apple ', ''),
        trailing: gpu == null ? 'unificada' : (gpu!.unifiedMemory ? 'unificada' : 'dedicada'),
        progress: null,
      ),
      MetricTile(
        icon: Icons.storage,
        color: AppColors.green,
        label: 'Disco livre',
        value: info.diskTotalBytes == 0 ? '—' : info.diskFreeLabel,
        trailing: info.diskTotalBytes == 0 ? null : 'de ${info.diskTotalLabel}',
        progress: diskPct / 100,
        valueColor: diskPct > 85 ? AppColors.red : AppColors.green,
      ),
    ];

    return MetricGrid(tiles: tiles);
  }
}

// ---------------------------------------------------------------------------
// ABA 0: Visão Geral
// ---------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  final HardwareInfo info;
  final BatteryInfo? battery;
  final bool wide;

  const _OverviewTab({
    required this.info,
    required this.battery,
    required this.wide,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _RealtimeCard(info: info, battery: battery)),
              const SizedBox(width: 16),
              const Expanded(flex: 2, child: _LimitsCard()),
            ],
          )
        else ...[
          _RealtimeCard(info: info, battery: battery),
          const SizedBox(height: 16),
          const _LimitsCard(),
        ],
        const SizedBox(height: 16),
        const StoragePanel(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ABA 1: Processador
// ---------------------------------------------------------------------------

class _CpuTab extends StatelessWidget {
  final DetailedCpuInfo cpu;
  final bool wide;

  const _CpuTab({required this.cpu, required this.wide});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                icon: Icons.memory,
                eyebrow: 'DETALHES DO PROCESSADOR',
                title: 'Arquitetura e Núcleos do Processador',
                description:
                    'Detalhamento profundo da topologia de núcleos, hierarquia de cache L1/L2/L3 e extensões de instruções suportadas.',
              ),
              const SizedBox(height: 20),
              _DetailRow(label: 'Processador / Chip', value: cpu.brandName, isBold: true),
              _DetailRow(label: 'Arquitetura', value: cpu.architecture),
              _DetailRow(
                label: 'Topologia de Núcleos',
                value:
                    '${cpu.totalCores} núcleos físicos (${cpu.performanceCores} Performance + ${cpu.efficiencyCores} Efficiency)',
              ),
              _DetailRow(label: 'Threads Lógicas', value: '${cpu.totalThreads} threads'),
              _DetailRow(label: 'Cluster de Alto Desempenho', value: '${cpu.performanceCores}x núcleos ${cpu.pCoreName}'),
              _DetailRow(label: 'Cluster de Alta Eficiência', value: '${cpu.efficiencyCores}x núcleos ${cpu.eCoreName}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hierarquia de Memória Cache (L1 / L2 / L3)',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _DetailRow(label: 'Cache L1 (Instruções + Dados)', value: cpu.l1Label),
              _DetailRow(label: 'Cache L2 (Compartilhado)', value: cpu.l2Label),
              _DetailRow(label: 'Cache L3 (Nível Superior)', value: cpu.l3Label),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Conjuntos de Instruções & Aceleradores de Hardware',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final inst in cpu.instructionSets)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.cardAlt,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.borderSoft),
                      ),
                      child: Text(
                        inst,
                        style: const TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600),
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
}

// ---------------------------------------------------------------------------
// ABA 2: Memória RAM
// ---------------------------------------------------------------------------

class _MemoryTab extends StatelessWidget {
  final DetailedMemoryInfo memory;
  final bool wide;

  const _MemoryTab({required this.memory, required this.wide});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                icon: Icons.layers_outlined,
                eyebrow: 'DETALHAMENTO DE MEMÓRIA',
                title: 'Configuração e Módulos de RAM',
                description:
                    'Especificações técnicas da memória instalada, padrão de barramento, canais e fabricante dos chips.',
              ),
              const SizedBox(height: 20),
              _DetailRow(label: 'Capacidade Total', value: memory.totalGbLabel, isBold: true),
              _DetailRow(label: 'Tipo de Memória', value: memory.type),
              _DetailRow(label: 'Velocidade / Barramento', value: memory.speed),
              _DetailRow(label: 'Fabricante dos Módulos / Chips', value: memory.manufacturer),
              _DetailRow(label: 'Form Factor Físico', value: memory.formFactor),
              _DetailRow(label: 'Topologia de Canais', value: memory.topology),
              _DetailRow(label: 'Slots Físicos Ocupados', value: '${memory.occupiedSlots} de ${memory.slotCount}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppPanel(
          color: const Color(0xFF101B24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 20, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Peculiaridade de Arquitetura de Memória',
                      style: TextStyle(color: AppColors.accent, fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      memory.platformExplanation,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ABA 3: Gráficos & Telas
// ---------------------------------------------------------------------------

class _GpuTab extends StatelessWidget {
  final DetailedGpuInfo gpu;
  final bool wide;

  const _GpuTab({required this.gpu, required this.wide});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                icon: Icons.videogame_asset_outlined,
                eyebrow: 'DETALHE DA GPU',
                title: 'Acelerador Gráfico & Displays',
                description:
                    'Mapeamento detalhado dos núcleos de sombreamento, suporte a APIs modernas e telas conectadas.',
              ),
              const SizedBox(height: 20),
              _DetailRow(label: 'Modelo da GPU', value: gpu.model, isBold: true),
              _DetailRow(label: 'Fabricante', value: gpu.vendor),
              _DetailRow(label: 'Núcleos de Render / Compute', value: '${gpu.coreCount} núcleos gráficos dedicados'),
              _DetailRow(label: 'Alocação de V-RAM', value: gpu.vramLabel),
              _DetailRow(label: 'Barramento / Conexão', value: gpu.busInterface),
              _DetailRow(label: 'APIs Gráficas Suportadas', value: gpu.apiSupport),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Monitores e Displays Conectados',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              for (final disp in gpu.displays) ...[
                _DetailRow(label: 'Nome da Tela', value: disp.name, isBold: true),
                _DetailRow(label: 'Resolução', value: disp.resolution),
                _DetailRow(label: 'Taxa de Atualização', value: disp.refreshRate),
                _DetailRow(label: 'Gama de Cores', value: disp.colorSpace),
                _DetailRow(label: 'Tipo', value: disp.isBuiltIn ? 'Display Integrado' : 'Monitor Externo'),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ABA 4: Placa-Mãe & EFI
// ---------------------------------------------------------------------------

class _MotherboardTab extends StatelessWidget {
  final SystemMotherboardInfo motherboard;
  final bool wide;

  const _MotherboardTab({required this.motherboard, required this.wide});

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            icon: Icons.developer_board,
            eyebrow: 'MAINBOARD & FIRMWARE',
            title: 'Placa-Mãe / Placa Lógica do Sistema',
            description:
                'Identificação da placa de circuito do sistema, firmware EFI/BIOS, chipset e identificadores exclusivos de hardware.',
          ),
          const SizedBox(height: 20),
          _DetailRow(label: 'Fabricante da Placa', value: motherboard.manufacturer, isBold: true),
          _DetailRow(label: 'Modelo do Sistema', value: motherboard.modelName),
          _DetailRow(label: 'Identificador do Modelo (Board ID)', value: motherboard.modelIdentifier),
          _DetailRow(label: 'Part / Model Number', value: motherboard.modelNumber),
          _DetailRow(label: 'Versão da Firmware EFI / Boot ROM', value: motherboard.firmwareVersion),
          _DetailRow(label: 'Versão do Carregador do OS', value: motherboard.osLoaderVersion),
          _DetailRow(label: 'Chipset do Sistema', value: motherboard.chipset),
          _DetailRow(label: 'Família do Dispositivo', value: motherboard.systemFamily),
          _DetailRow(label: 'UUID da Plataforma de Hardware', value: motherboard.platformUuid),
          _DetailRow(label: 'Número de Série', value: motherboard.serialNumber),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ABA 5: USB & Conexões
// ---------------------------------------------------------------------------

class _UsbTab extends StatelessWidget {
  final List<UsbControllerItem> usbControllers;
  final bool wide;

  const _UsbTab({required this.usbControllers, required this.wide});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                icon: Icons.usb,
                eyebrow: 'DETALHES DE CONEXÕES & BARRAMENTOS',
                title: 'Barramentos USB e Thunderbolt',
                description:
                    'Controladoras de host xHCI, barramentos Thunderbolt 4 / USB4 e portas físicas do dispositivo.',
              ),
              const SizedBox(height: 18),
              if (usbControllers.isEmpty)
                const Text(
                  'Nenhuma controladora USB detectada.',
                  style: TextStyle(color: AppColors.textMuted),
                )
              else
                for (var i = 0; i < usbControllers.length; i++) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.cardAlt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderSoft),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.cable, size: 18, color: AppColors.accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                usbControllers[i].name,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Padrão: ${usbControllers[i].speedStandard}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        if (usbControllers[i].connectedDevices.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          for (final dev in usbControllers[i].connectedDevices)
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 4),
                              child: Row(
                                children: [
                                  const Icon(Icons.arrow_right, size: 16, color: AppColors.green),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      dev,
                                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ABA 6: Armazenamento
// ---------------------------------------------------------------------------

class _StorageTab extends StatelessWidget {
  final List<StorageDiskItem> disks;
  final bool wide;

  const _StorageTab({required this.disks, required this.wide});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                icon: Icons.storage,
                eyebrow: 'DISCOS & VOLUMES',
                title: 'Mídia de Armazenamento e Partições',
                description: 'Inspeção de interfaces de disco NVMe, sistema de arquivos APFS e capacidade particionada.',
              ),
              const SizedBox(height: 18),
              if (disks.isEmpty)
                const Text(
                  'Nenhum volume montado encontrado.',
                  style: TextStyle(color: AppColors.textMuted),
                )
              else
                for (final d in disks) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.cardAlt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderSoft),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.album_outlined, size: 18, color: AppColors.green),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                d.name,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '${d.usedPercent.toStringAsFixed(0)}% usado',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ponto de Montagem: ${d.mountPoint}  ·  Interface: ${d.interfaceType}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        Text(
                          'Sistema de Arquivos: ${d.fileSystem}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (d.usedPercent / 100).clamp(0, 1),
                            minHeight: 6,
                            backgroundColor: AppColors.borderSoft,
                            color: d.usedPercent > 85 ? AppColors.red : AppColors.green,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Livre: ${d.freeGbLabel} de ${d.totalGbLabel}',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ABA 7: Rede
// ---------------------------------------------------------------------------

class _NetworkTab extends StatelessWidget {
  final List<NetworkAdapterItem> adapters;
  final bool wide;

  const _NetworkTab({required this.adapters, required this.wide});

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            icon: Icons.wifi,
            eyebrow: 'INTERFACE DE CONECTIVIDADE',
            title: 'Adaptadores de Rede e Endereçamento',
            description: 'Mapeamento de interfaces Wi-Fi, Ethernet, endereços físicos (MAC) e IPv4 ativo.',
          ),
          const SizedBox(height: 18),
          if (adapters.isEmpty)
            const Text(
              'Nenhum adaptador de rede ativo identificado.',
              style: TextStyle(color: AppColors.textMuted),
            )
          else
            for (final a in adapters) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: a.isActive ? AppColors.accent.withValues(alpha: 0.35) : AppColors.borderSoft,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          a.typeName.contains('Wi-Fi') ? Icons.wifi : Icons.settings_ethernet,
                          size: 18,
                          color: a.isActive ? AppColors.accent : AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            a.typeName,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: a.isActive
                                ? AppColors.green.withValues(alpha: 0.15)
                                : AppColors.textMuted.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            a.isActive ? 'Conectado' : 'Inativo',
                            style: TextStyle(
                              color: a.isActive ? AppColors.green : AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _DetailRow(label: 'Dispositivo / Interface', value: a.interfaceName),
                    _DetailRow(label: 'Endereço MAC Físico', value: a.macAddress),
                    if (a.ipAddress != null)
                      _DetailRow(label: 'Endereço IPv4 Local', value: a.ipAddress!, isBold: true),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ABA 8: Peculiaridades de Plataforma
// ---------------------------------------------------------------------------

class _PeculiaritiesTab extends StatelessWidget {
  final List<PlatformHardwarePeculiarity> peculiarities;
  final bool wide;

  const _PeculiaritiesTab({required this.peculiarities, required this.wide});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                icon: Icons.devices_other,
                eyebrow: 'DIAGNÓSTICO CROSS-PLATFORM',
                title: 'Peculiaridades por Sistema Operacional',
                description:
                    'Explicação transparente das diferenças arquiteturais entre Mac, Windows, Linux e Android na exposição de recursos de hardware.',
              ),
              const SizedBox(height: 18),
              for (final p in peculiarities) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: p.isApplicableToCurrentPlatform
                          ? AppColors.accent.withValues(alpha: 0.3)
                          : AppColors.borderSoft,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            p.isApplicableToCurrentPlatform
                                ? Icons.verified_outlined
                                : Icons.phonelink_setup,
                            size: 16,
                            color: p.isApplicableToCurrentPlatform ? AppColors.accent : AppColors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              p.title,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: p.isApplicableToCurrentPlatform
                                  ? AppColors.accent.withValues(alpha: 0.12)
                                  : AppColors.card,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: p.isApplicableToCurrentPlatform
                                    ? AppColors.accent.withValues(alpha: 0.4)
                                    : AppColors.borderSoft,
                              ),
                            ),
                            child: Text(
                              p.tag,
                              style: TextStyle(
                                color: p.isApplicableToCurrentPlatform ? AppColors.accent : AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        p.description,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Componente auxiliar de linha de detalhe
// ---------------------------------------------------------------------------

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const _DetailRow({
    required this.label,
    required this.value,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isBold ? AppColors.accent : AppColors.textPrimary,
                fontSize: 13,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painéis inferiores da aba Visão Geral
// ---------------------------------------------------------------------------

class _RealtimeCard extends StatelessWidget {
  final HardwareInfo info;
  final BatteryInfo? battery;

  const _RealtimeCard({required this.info, required this.battery});

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      ('Núcleos', '${info.cores} threads reais (${info.cpu.performanceCores}P + ${info.cpu.efficiencyCores}E)'),
      ('Memória', '${info.ramTotalLabel} ${info.memory.type} (${info.memory.manufacturer})'),
      if (battery != null)
        ('Bateria', '${battery!.health.toStringAsFixed(1)}% de saúde · ${battery!.cycleCount} ciclos'),
      ('Sensores', 'CPU, RAM e Temperaturas atualizados a cada 2 segundos'),
      ('Benchmark', 'Motor em Rust com score próprio (FFI nativo) e FurMark 3D Metal'),
    ];

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle_outline, size: 16, color: AppColors.accent),
              SizedBox(width: 8),
              Text(
                'Lido em tempo real no seu hardware',
                style: TextStyle(color: AppColors.accent, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.45),
                        children: [
                          TextSpan(
                            text: '${item.$1}: ',
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
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
      ),
    );
  }
}

class _LimitsCard extends StatelessWidget {
  const _LimitsCard();

  @override
  Widget build(BuildContext context) {
    const items = <(String, String)>[
      ('Slots DIMM avulsos', 'Inexistentes em SoC Apple Silicon (memória unificada on-package)'),
      ('Leitura de SPD de RAM', 'Disponível no Windows via WMI; no Linux requer permissão de root'),
      ('Smartphones (Android)', 'APIs do sistema isolam o hardware profundo por sandbox SELinux'),
      ('Limpeza e atualizações', 'Chegam na V1.1 com whitelist e confirmação'),
    ];

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: AppColors.orange),
              SizedBox(width: 8),
              Text(
                'Limites e peculiaridades por plataforma',
                style: TextStyle(color: AppColors.orange, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.remove_circle_outline, size: 15, color: AppColors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.45),
                        children: [
                          TextSpan(
                            text: '${item.$1}: ',
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
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
      ),
    );
  }
}
