import 'package:flutter/material.dart';

class SensorsScreen extends StatelessWidget {
  const SensorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Card(
          child: ListTile(
            leading: Icon(Icons.thermostat),
            title: Text('Sensores — MVP'),
            subtitle: Text(
              'MVP: temperatura CPU/GPU quando disponível (limitado no macOS Apple Silicon),\n'
              'uso CPU/RAM em tempo real, ventilação quando disponível.\n\n'
              'Próximo passo: polling a cada 1s + gráfico (fl_chart).',
            ),
          ),
        ),
        SizedBox(height: 12),
        PlaceholderCard(label: 'CPU temperatura', value: 'TODO: IOKit / sysctl'),
        PlaceholderCard(label: 'GPU temperatura', value: 'TODO: IOKit / Metal'),
        PlaceholderCard(label: 'Uso CPU', value: 'TODO: top / host_processor_info'),
        PlaceholderCard(label: 'Uso RAM', value: 'TODO: vm_stat / ActivityManager'),
        PlaceholderCard(label: 'Ventoinha', value: 'TODO: SMC (Intel apenas)'),
      ],
    );
  }
}

class PlaceholderCard extends StatelessWidget {
  final String label;
  final String value;
  const PlaceholderCard({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(value),
        trailing: const Icon(Icons.pending),
      ),
    );
  }
}
