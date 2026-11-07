import 'package:flutter/material.dart';

import 'core/platform/platform_detector.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/top_nav.dart';
import 'features/battery/battery_screen.dart';
import 'features/benchmark/benchmark_screen.dart';
import 'features/hardware/hardware_screen.dart';
import 'features/history/history_screen.dart';
import 'features/sensors/sensors_screen.dart';
import 'features/stress/stress_screen.dart';
import 'features/system_tweaks/system_tweaks_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PlatformDetector.init();
  runApp(const BMyBenchApp());
}

class BMyBenchApp extends StatelessWidget {
  const BMyBenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isTouch = PlatformDetector.isTouchscreen();
    return MaterialApp(
      title: 'BMyBench',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(isTouch: isTouch),
      darkTheme: AppTheme.dark(isTouch: isTouch),
      themeMode: ThemeMode.dark,
      scrollBehavior: const AppScrollBehavior(),
      home: const _HomeShell(),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;

  static const _baseTitles = ['Hardware', 'Sensores', 'Bateria', 'Benchmark', 'Estresse', 'Histórico'];
  static const _wideBreakpoint = 860.0;

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= _wideBreakpoint;
    final supportsTweaks = PlatformDetector.supportsSystemTweaks;

    final titles = [
      ..._baseTitles,
      if (supportsTweaks) 'Ajustes',
    ];

    // Garante que o índice não estoure caso o suporte mude dinamicamente
    final safeIndex = _index < titles.length ? _index : 0;

    final pages = <Widget>[
      HardwareScreen(onRunCpu: () => _select(3)),
      const SensorsScreen(),
      const BatteryScreen(),
      const BenchmarkScreen(),
      const StressScreen(),
      const HistoryScreen(),
      if (supportsTweaks) const SystemTweaksScreen(),
    ];

    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: KeyedSubtree(key: ValueKey(safeIndex), child: pages[safeIndex]),
    );

    if (isWide) {
      return Scaffold(
        body: Column(
          children: [
            TopNav(items: titles, selected: safeIndex, onSelect: _select),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('BMyBench — ${titles[safeIndex]}'),
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: _select,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.memory), label: 'Hardware'),
          const NavigationDestination(icon: Icon(Icons.thermostat), label: 'Sensores'),
          const NavigationDestination(icon: Icon(Icons.battery_std), label: 'Bateria'),
          const NavigationDestination(icon: Icon(Icons.speed), label: 'Bench'),
          const NavigationDestination(icon: Icon(Icons.whatshot), label: 'Estresse'),
          const NavigationDestination(icon: Icon(Icons.history), label: 'Histórico'),
          if (supportsTweaks)
            const NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Ajustes'),
        ],
      ),
    );
  }
}
