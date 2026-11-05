import 'package:flutter/material.dart';

class BenchmarkScreen extends StatelessWidget {
  const BenchmarkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: ListTile(
            leading: Icon(Icons.speed),
            title: Text('Benchmark — MVP leve'),
            subtitle: Text(
              'Score próprio (não Geekbench/Cinebench).\n'
              'Core em Rust (planejado) para score consistente cross-platform.\n'
              'UI aqui é só launcher + progresso + resultado.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        _BenchmarkTile(
          icon: Icons.memory,
          title: 'CPU',
          subtitle: 'Single-core + multi-core (hash, física, render)',
          onTap: () => _toast(context, 'CPU bench: TODO — chamar rust_cpu_benchmark()'),
        ),
        _BenchmarkTile(
          icon: Icons.view_in_ar,
          title: 'Memória',
          subtitle: 'GB/s leitura/escrita + latência básica',
          onTap: () => _toast(context, 'Mem bench: TODO — chamar rust_mem_benchmark()'),
        ),
        _BenchmarkTile(
          icon: Icons.storage,
          title: 'Disco',
          subtitle: 'Leitura/escrita sequencial (arquivo temporário)',
          onTap: () => _toast(context, 'Disk bench: TODO — sequential IO temp file'),
        ),
        _BenchmarkTile(
          icon: Icons.view_in_ar,
          title: 'GPU',
          subtitle: 'MVP: nome + FPS simples 5-10s (off-screen)\nV1.1: FurMark completo (Metal/Vulkan)',
          onTap: () => _toast(context, 'GPU bench: TODO — Metal/Vulkan off-screen FPS'),
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('MVP+ (pode adiantar)'),
            subtitle: Text(
              'RAM single/dual (informativo), saúde SSD leitura, escaneador temp,\n'
              'verificador updates (somente listar) — ver BMyBench_MVP_Planning.md §4.2',
            ),
          ),
        ),
      ],
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _BenchmarkTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _BenchmarkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.play_arrow),
        onTap: onTap,
      ),
    );
  }
}
