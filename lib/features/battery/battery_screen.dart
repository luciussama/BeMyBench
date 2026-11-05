import 'package:flutter/material.dart';

import 'battery_service.dart';

class BatteryScreen extends StatefulWidget {
  const BatteryScreen({super.key});

  @override
  State<BatteryScreen> createState() => _BatteryScreenState();
}

class _BatteryScreenState extends State<BatteryScreen> {
  final _service = BatteryService();
  BatteryInfo? _info;
  Map<String, String> _data = {};
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final info = await _service.collect();
      if (!mounted) return;
      setState(() {
        _info = info;
        _data = info?.toDisplayMap() ?? {};
        _loading = false;
        if (info == null) {
          _error = 'Bateria não detectada ou leitura ainda não implementada neste sistema.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Color _healthColor(double health) {
    if (health >= 90) return Colors.green;
    if (health >= 80) return Colors.orange;
    return Colors.red;
  }

  String _healthLabel(double health) {
    if (health >= 90) return 'Excelente';
    if (health >= 80) return 'Boa';
    if (health >= 70) return 'Degradada';
    return 'Substituir';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_info == null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            Center(child: Text(_error.isEmpty ? 'Sem dados de bateria' : _error)),
          ],
        ),
      );
    }

    final info = _info!;
    final color = _healthColor(info.health);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    '${info.percentage}%',
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(info.isCharging ? 'Carregando' : (info.externalConnected ? 'Conectado (AC)' : 'Descarregando')),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: info.percentage / 100,
                      minHeight: 12,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(
                            '${info.health.toStringAsFixed(1)}%',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
                          ),
                          const Text('Saúde'),
                          Text(_healthLabel(info.health), style: TextStyle(color: color)),
                        ],
                      ),
                      Column(
                        children: [
                          Text('${info.cycleCount}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          const Text('Ciclos'),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final entry in _data.entries)
            Card(
              child: ListTile(
                title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: Text(entry.value),
              ),
            ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Teste de descarga (V1.1)'),
              subtitle: const Text('Mede autonomia real de 100% até 20%. Fica para a próxima versão.'),
            ),
          ),
        ],
      ),
    );
  }
}
