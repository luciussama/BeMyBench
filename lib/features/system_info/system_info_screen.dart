import 'package:flutter/material.dart';

import 'system_info_service.dart';

class SystemInfoScreen extends StatefulWidget {
  const SystemInfoScreen({super.key});

  @override
  State<SystemInfoScreen> createState() => _SystemInfoScreenState();
}

class _SystemInfoScreenState extends State<SystemInfoScreen> {
  final _service = SystemInfoService();
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
      final data = await _service.collect();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(child: Text('Erro: $_error'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('System Info'),
              subtitle: Text(
                'MVP: coleta via sysctl/proc. Windows/Android via MethodChannel nativo (a vir).',
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in _data.entries)
            Card(
              child: ListTile(
                title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(entry.value.isEmpty ? 'N/A' : entry.value),
              ),
            ),
        ],
      ),
    );
  }
}
