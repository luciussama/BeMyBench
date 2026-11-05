import 'package:flutter/material.dart';

import 'core/platform/platform_detector.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/top_nav.dart';
import 'features/battery/battery_screen.dart';
import 'features/benchmark/benchmark_screen.dart';
import 'features/hardware/hardware_screen.dart';
import 'features/sensors/sensors_screen.dart';
import 'features/stress/stress_screen.dart';

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

  static const _titles = ['Hardware', 'Sensores', 'Bateria', 'Benchmark', 'Estresse'];
  static const _wideBreakpoint = 860.0;

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= _wideBreakpoint;

    final pages = <Widget>[
      HardwareScreen(onRunCpu: () => _select(3)),
      const SensorsScreen(),
      const BatteryScreen(),
      const BenchmarkScreen(),
      const StressScreen(),
    ];

    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
    );

    if (isWide) {
      return Scaffold(
        body: Column(
          children: [
            TopNav(items: _titles, selected: _index, onSelect: _select),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('BMyBench — ${_titles[_index]}'),
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.memory), label: 'Hardware'),
          NavigationDestination(icon: Icon(Icons.thermostat), label: 'Sensores'),
          NavigationDestination(icon: Icon(Icons.battery_std), label: 'Bateria'),
          NavigationDestination(icon: Icon(Icons.speed), label: 'Benchmark'),
          NavigationDestination(icon: Icon(Icons.whatshot), label: 'Estresse'),
        ],
      ),
    );
  }
}
