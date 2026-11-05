import 'dart:async';

import 'package:flutter/material.dart';

import 'sensors_service.dart';

class SensorsScreen extends StatefulWidget {
  const SensorsScreen({super.key});

  @override
  State<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends State<SensorsScreen> {
  final _service = SensorsService();
  SensorsSnapshot? _snapshot;
  Timer? _timer;
  bool _loading = true;
  bool _paused = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_paused) _tick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    try {
      final s = await _service.collect();
      if (!mounted) return;
      setState(() {
        _snapshot = s;
        _loading = false;
        _error = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Color _loadColor(double pct) {
    if (pct < 50) return Colors.green;
    if (pct < 80) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_snapshot == null) {
      return Center(child: Text(_error.isEmpty ? 'Sem dados' : _error));
    }

    final s = _snapshot!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Uso de CPU', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('${s.cpuUsagePercent.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: _loadColor(s.cpuUsagePercent),
                        )),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: s.cpuUsagePercent / 100,
                    minHeight: 10,
                    color: _loadColor(s.cpuUsagePercent),
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Uso de RAM', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('${s.ramUsagePercent.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: _loadColor(s.ramUsagePercent),
                        )),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: s.ramUsagePercent / 100,
                    minHeight: 10,
                    color: _loadColor(s.ramUsagePercent),
                  ),
                ),
                const SizedBox(height: 6),
                Text('${s.ramUsedLabel} de ${s.ramTotalLabel}'),
              ],
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.thermostat),
            title: const Text('Temperatura'),
            subtitle: const Text(
              'Não disponível: no Apple Silicon a leitura exige powermetrics com sudo. '
              'Será implementado via IOHIDEventSystemClient em código nativo (V1.1).',
            ),
            trailing: const Text('N/A'),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.mode_fan_off),
            title: const Text('Ventoinha'),
            subtitle: const Text('Sem leitura disponível neste modelo (Apple Silicon / sem SMC acessível).'),
            trailing: const Text('N/A'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _paused = !_paused),
                icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                label: Text(_paused ? 'Retomar' : 'Pausar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _tick,
                icon: const Icon(Icons.refresh),
                label: const Text('Atualizar'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            _paused ? 'Atualização pausada' : 'Atualizando a cada 2s',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
