import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/dashboard.dart';
import 'benchmark_models.dart';
import 'reference_db.dart';

/// Painel de comparação: converte o score BMyBench em equivalentes
/// aproximados de Cinebench R23 / Geekbench 6 e mostra o ranking.
class ComparisonPanel extends StatefulWidget {
  final CpuBenchResult cpu;

  const ComparisonPanel({super.key, required this.cpu});

  @override
  State<ComparisonPanel> createState() => _ComparisonPanelState();
}

class _ComparisonPanelState extends State<ComparisonPanel> {
  String _vendor = 'Todos';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ReferenceData>(
      future: ReferenceData.load(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const AppPanel(
            child: SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final db = snapshot.data!;
        return _buildPanel(db);
      },
    );
  }

  Widget _buildPanel(ReferenceData db) {
    final cpu = widget.cpu;
    final estCbMulti = db.estimateCb23Multi(cpu.multiMops);
    final estCbSingle = db.estimateCb23Single(cpu.singleMops);
    final estGbMulti = db.estimateGb6Multi(cpu.multiMops);
    final percentile = db.percentile(cpu.multiMops, vendor: _vendor);
    final nearest = db.nearest(cpu.multiMops, vendor: _vendor);

    final pool = db.devicesFor(_vendor);
    // Mostra os 8 primeiros e garante o "você" na lista.
    final shown = pool.take(9).toList();
    final maxValue = shown.isEmpty
        ? estCbMulti
        : shown.map((d) => d.cb23Multi).fold<double>(estCbMulti, (a, b) => a > b ? a : b);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.compare_arrows, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Comparação com equipamentos similares',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'base: ${pool.length} dispositivos',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Equivalentes estimados
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _EstimatePill(
                label: 'Cinebench R23 multi',
                value: _fmt(estCbMulti),
                color: AppColors.accent,
              ),
              _EstimatePill(
                label: 'Cinebench R23 single',
                value: _fmt(estCbSingle),
                color: AppColors.accent,
              ),
              _EstimatePill(
                label: 'Geekbench 6 multi',
                value: _fmt(estGbMulti),
                color: AppColors.violet,
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
                color: AppColors.accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
              ),
              child: Text(
                'Equivalente mais próximo: ${nearest.name} '
                '(Cinebench R23 multi de referência: ${_fmt(nearest.cb23Multi)})',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Filtro por fabricante
          Wrap(
            spacing: 8,
            children: [
              for (final v in const ['Todos', 'Apple', 'Intel', 'AMD'])
                _FilterPill(
                  label: v,
                  active: _vendor == v,
                  onTap: () => setState(() => _vendor = v),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Ranking
          for (final d in shown)
            _RankRow(
              name: d.name,
              value: d.cb23Multi,
              maxValue: maxValue,
              label: _fmt(d.cb23Multi),
              color: _vendorColor(d.vendor),
            ),
          _RankRow(
            name: 'Seu dispositivo (BMyBench)',
            value: estCbMulti,
            maxValue: maxValue,
            label: _fmt(estCbMulti),
            color: AppColors.accent,
            highlight: true,
          ),
          const SizedBox(height: 12),
          Text(
            '${db.disclaimer}\nOs equivalentes são uma conversão linear calibrada '
            'no dispositivo âncora — trate como estimativa, não como medida oficial.',
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
      case 'Intel':
        return AppColors.violet;
      default:
        return AppColors.orange;
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
            '≈ $value',
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
      color: active ? AppColors.accent.withValues(alpha: 0.12) : AppColors.cardAlt,
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
                  ? AppColors.accent.withValues(alpha: 0.45)
                  : AppColors.borderSoft,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.accent : AppColors.textSecondary,
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
                const Icon(Icons.arrow_right, size: 14, color: AppColors.accent),
                const SizedBox(width: 2),
              ],
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: highlight ? AppColors.accent : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: highlight ? AppColors.accent : AppColors.textMuted,
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
