import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/dashboard.dart';
import 'gpu_benchmark.dart';
import 'gpu_reference_db.dart';

/// Comparação do resultado de GPU com os rankings públicos de referência.
///
/// O score de rasterização é estimado preferencialmente pelo teste de
/// renderização; o de compute, pelo teste de compute.
class GpuComparisonPanel extends StatefulWidget {
  final GpuBenchResult? compute;
  final GpuBenchResult? render;

  const GpuComparisonPanel({super.key, this.compute, this.render})
      : assert(compute != null || render != null);

  @override
  State<GpuComparisonPanel> createState() => _GpuComparisonPanelState();
}

class _GpuComparisonPanelState extends State<GpuComparisonPanel> {
  String _vendor = 'Todos';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GpuReferenceData>(
      future: GpuReferenceData.load(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const AppPanel(
            child: SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        return _buildPanel(snapshot.data!);
      },
    );
  }

  Widget _buildPanel(GpuReferenceData db) {
    final compute = widget.compute;
    final render = widget.render;

    final estRaster = render != null
        ? db.rasterRefFromRender(render.fps)
        : db.rasterRefFromCompute(compute!.fps);
    final estCompute = compute == null ? null : db.computeRefFromCompute(compute.fps);
    final percentile =
        db.percentileForRef(estRaster, vendor: _vendor);
    final nearest = db.nearestForRef(estRaster, vendor: _vendor);

    final pool = db.devicesFor(_vendor);
    final shown = pool.take(9).toList();
    final maxValue = shown.isEmpty
        ? estRaster
        : shown
            .map((d) => d.gpuRefRaster)
            .fold<double>(estRaster, (a, b) => a > b ? a : b);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.videogame_asset_outlined,
                  size: 16, color: AppColors.violet),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Comparação de GPU com equipamentos similares',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'base: ${pool.length} GPUs',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _EstimatePill(
                label: 'GPU raster (ref.)',
                value: _fmt(estRaster),
                color: AppColors.violet,
              ),
              if (estCompute != null)
                _EstimatePill(
                  label: 'Compute (ref.)',
                  value: _fmt(estCompute),
                  color: AppColors.accent,
                ),
              if (render != null && render.hasFrameStats)
                _EstimatePill(
                  label: '1% low',
                  value: '${render.onePercentLowFps.toStringAsFixed(0)} fps',
                  color: AppColors.red,
                ),
              if (render != null)
                _EstimatePill(
                  label: 'GPU render (jogos)',
                  value: '${render.fps.toStringAsFixed(1)} fps',
                  color: AppColors.orange,
                ),
              if (compute != null)
                _EstimatePill(
                  label: 'Compute (BMyBench)',
                  value: '${compute.fps.toStringAsFixed(1)} fps',
                  color: AppColors.accent,
                ),
              _EstimatePill(
                label: 'Percentil',
                value: '${percentile.toStringAsFixed(0)}%',
                color: AppColors.green,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (nearest != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.violet.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(9),
                border:
                    Border.all(color: AppColors.violet.withValues(alpha: 0.25)),
              ),
              child: Text(
                'Equivalente mais próximo: ${nearest.name} '
                '(score raster de referência: ${_fmt(nearest.gpuRefRaster)})',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final v in db.vendors)
                _FilterPill(
                  label: v,
                  active: _vendor == v,
                  onTap: () => setState(() => _vendor = v),
                ),
            ],
          ),
          const SizedBox(height: 14),
          for (final d in shown)
            _RankRow(
              name: d.name,
              value: d.gpuRefRaster,
              maxValue: maxValue,
              label: _fmt(d.gpuRefRaster),
              color: _vendorColor(d.vendor),
            ),
          _RankRow(
            name: render != null
                ? 'Seu dispositivo (BMyBench render)'
                : 'Seu dispositivo (BMyBench compute)',
            value: estRaster,
            maxValue: maxValue,
            label: _fmt(estRaster),
            color: AppColors.violet,
            highlight: true,
          ),
          const SizedBox(height: 12),
          if (render == null && compute != null)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Score de raster estimado pelo teste de compute. Rode o teste de '
                'renderização para uma comparação mais fiel a jogos.',
                style: TextStyle(
                  color: AppColors.orange,
                  fontSize: 10,
                  height: 1.5,
                ),
              ),
            ),
          Text(
            '${db.disclaimer}\nA conversão é linear e calibrada em '
            '${db.anchorDevice}. O score de raster usa o teste de renderização; '
            'o de compute usa o de compute. Trate como estimativa, '
            'não como medida oficial.',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Color _vendorColor(String vendor) {
    switch (vendor) {
      case 'Apple':
        return AppColors.textSecondary;
      case 'NVIDIA':
        return AppColors.green;
      case 'AMD':
        return AppColors.orange;
      default:
        return AppColors.accent;
    }
  }

  String _fmt(double v) {
    final s = v.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _EstimatePill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _EstimatePill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          active ? AppColors.violet.withValues(alpha: 0.12) : AppColors.cardAlt,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? AppColors.violet.withValues(alpha: 0.45)
                  : AppColors.borderSoft,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.violet : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final String name;
  final double value;
  final double maxValue;
  final String label;
  final Color color;
  final bool highlight;

  const _RankRow({
    required this.name,
    required this.value,
    required this.maxValue,
    required this.label,
    required this.color,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (highlight) ...[
                const Icon(Icons.arrow_right, size: 14, color: AppColors.violet),
                const SizedBox(width: 2),
              ],
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color:
                        highlight ? AppColors.violet : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: highlight ? AppColors.violet : AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Container(
                    height: highlight ? 7 : 5,
                    decoration: BoxDecoration(
                      color: AppColors.borderSoft,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Container(
                    height: highlight ? 7 : 5,
                    width: constraints.maxWidth * ratio,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: highlight ? 1 : 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
