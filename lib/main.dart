import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'core/platform/platform_detector.dart';
import 'features/system_info/system_info_screen.dart';
import 'features/sensors/sensors_screen.dart';
import 'features/battery/battery_screen.dart';
import 'features/benchmark/benchmark_screen.dart';

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
      themeMode: ThemeMode.system,
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

  static const _titles = [
    'Sistema',
    'Sensores',
    'Bateria',
    'Benchmark',
  ];

  @override
  Widget build(BuildContext context) {
    final isTouch = PlatformDetector.isTouchscreen();
    final pages = const [
      SystemInfoScreen(),
      SensorsScreen(),
      BatteryScreen(),
      BenchmarkScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('BMyBench — ${_titles[_index]}'),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        height: isTouch ? 80 : 64,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.computer), label: 'Sistema'),
          NavigationDestination(icon: Icon(Icons.thermostat), label: 'Sensores'),
          NavigationDestination(icon: Icon(Icons.battery_std), label: 'Bateria'),
          NavigationDestination(icon: Icon(Icons.speed), label: 'Benchmark'),
        ],
      ),
    );
  }
}
