import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Painel base: borda sutil, fundo de card, cantos arredondados.
class AppPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  const AppPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = AppColors.card,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: child,
    );
  }
}

/// Cabeçalho de seção: eyebrow + título + descrição + ação opcional.
class SectionHeader extends StatelessWidget {
  final IconData icon;
  final String eyebrow;
  final Color eyebrowColor;
  final String title;
  final String? description;
  final Widget? action;

  const SectionHeader({
    super.key,
    required this.icon,
    required this.eyebrow,
    required this.title,
    this.description,
    this.action,
    this.eyebrowColor = AppColors.accent,
  });

  @override
  Widget build(BuildContext context) {
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: eyebrowColor),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                eyebrow,
                style: TextStyle(
                  color: eyebrowColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 8),
          Text(
            description!,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ],
    );

    if (action == null) return texts;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 700) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: texts),
              const SizedBox(width: 20),
              action!,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [texts, const SizedBox(height: 14), action!],
        );
      },
    );
  }
}

/// Botão grande com gradiente (CTA principal).
class GradientActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final List<Color> colors;

  const GradientActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.colors = const [Color(0xFF0EA5B7), Color(0xFF22D3EE)],
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: const Color(0xFF04212A)),
                  const SizedBox(width: 9),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF04212A),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chip selecionável com cor própria (estilo "teste incluído").
class FeatureChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final Color color;
  final VoidCallback? onTap;

  const FeatureChip({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = enabled ? color : AppColors.textMuted;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: selected ? c.withValues(alpha: 0.10) : AppColors.cardAlt,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? c.withValues(alpha: 0.55) : AppColors.borderSoft,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: selected ? c : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: selected ? c : AppColors.textMuted,
                      width: 1.4,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 12, color: Color(0xFF04212A))
                      : null,
                ),
                const SizedBox(width: 9),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tile de métrica: rótulo, valor grande, detalhe e barra opcional.
class MetricTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? caption;
  final String? trailing;
  final double? progress;
  final Color? valueColor;

  const MetricTile({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.caption,
    this.trailing,
    this.progress,
    this.valueColor,
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
              Icon(icon, size: 15, color: color),
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
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress!.clamp(0, 1),
                minHeight: 5,
                backgroundColor: AppColors.borderSoft,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Grade de tiles responsiva: 4 colunas (wide) ou 2x2.
class MetricGrid extends StatelessWidget {
  final List<Widget> tiles;

  const MetricGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
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
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += 2) {
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tiles[i]),
                  const SizedBox(width: 12),
                  if (i + 1 < tiles.length) Expanded(child: tiles[i + 1]),
                ],
              ),
            ),
          );
          if (i + 2 < tiles.length) rows.add(const SizedBox(height: 12));
        }
        return Column(children: rows);
      },
    );
  }
}

/// Painel de gráfico de linha com legenda e estado vazio.
class LineChartPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final String legend;
  final List<double> values;
  final double maxValue;
  final String emptyLabel;
  final double height;

  const LineChartPanel({
    super.key,
    required this.title,
    required this.legend,
    required this.values,
    this.maxValue = 100,
    this.emptyLabel = 'Aguardando dados...',
    this.height = 190,
    this.icon = Icons.show_chart,
    this.color = AppColors.accent,
  });

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      color: AppColors.cardAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                legend,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: height,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: values.length < 2
                ? Center(
                    child: Text(
                      emptyLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  )
                : CustomPaint(
                    painter: _LineChartPainter(
                      values: values,
                      maxValue: maxValue,
                      color: color,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final double maxValue;
  final Color color;

  _LineChartPainter({
    required this.values,
    required this.maxValue,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 44.0;
    const rightPad = 10.0;
    const topPad = 12.0;
    const bottomPad = 22.0;

    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;
    if (chartW <= 0 || chartH <= 0) return;

    final gridPaint = Paint()
      ..color = AppColors.borderSoft
      ..strokeWidth = 1;

    const labelStyle = TextStyle(
      color: AppColors.textMuted,
      fontSize: 9,
    );

    // Linhas de grade + rótulos
    for (var i = 0; i <= 4; i++) {
      final y = topPad + chartH * (i / 4);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
      final value = (maxValue * (1 - i / 4)).round();
      final tp = TextPainter(
        text: TextSpan(text: '$value', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 6, y - tp.height / 2));
    }

    // Linha
    final points = <Offset>[];
    final n = values.length;
    for (var i = 0; i < n; i++) {
      final x = leftPad + chartW * (n == 1 ? 0 : i / (n - 1));
      final v = values[i].clamp(0.0, maxValue);
      final y = topPad + chartH * (1 - v / maxValue);
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    final fill = Path.from(path)
      ..lineTo(points.last.dx, topPad + chartH)
      ..lineTo(points.first.dx, topPad + chartH)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );

    // Ponto final
    canvas.drawCircle(points.last, 2.6, Paint()..color = color);

    // Rótulo eixo X
    final endLabel = TextPainter(
      text: const TextSpan(text: 'agora', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    endLabel.paint(
      canvas,
      Offset(size.width - rightPad - endLabel.width, size.height - bottomPad + 6),
    );
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.values != values || old.maxValue != maxValue || old.color != color;
}

/// Conveniência: calcula escala "bonita" para o eixo.
double niceMax(double value) {
  if (value <= 0) return 1;
  final magnitude = math.pow(10, (math.log(value) / math.ln10).floor()).toDouble();
  final normalized = value / magnitude;
  final step = normalized <= 1
      ? 1
      : normalized <= 2
          ? 2
          : normalized <= 5
              ? 5
              : 10;
  return step * magnitude;
}
