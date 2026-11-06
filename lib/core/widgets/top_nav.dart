import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Navegação superior (desktop). No mobile/touch o shell usa NavigationBar.
class TopNav extends StatefulWidget {
  final List<String> items;
  final int selected;
  final ValueChanged<int> onSelect;

  const TopNav({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  @override
  State<TopNav> createState() => _TopNavState();
}

class _TopNavState extends State<TopNav> {
  final ScrollController _scrollController = ScrollController();

  static const _icons = [
    Icons.memory,
    Icons.thermostat,
    Icons.battery_std,
    Icons.speed,
    Icons.whatshot,
    Icons.history,
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.borderSoft)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.grid_view_rounded, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          const Text(
            'BMyBench',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 24),
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
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    for (var i = 0; i < widget.items.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _NavPill(
                          icon: _icons[i % _icons.length],
                          label: widget.items[i],
                          active: i == widget.selected,
                          onTap: () => widget.onSelect(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavPill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.accent.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: active ? AppColors.accent : AppColors.textMuted,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
