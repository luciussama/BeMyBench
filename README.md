# BMyBench (Be My Bench)

**AIDA64 moderno, cross-platform.** Diagnóstico + Benchmark + Saúde de bateria + (futuro) Auxílio de desempenho.

> MVP = somente leitura/medir. V1.1 = agir (limpar, atualizar, estressar).
> Ver [`../BMyBench_MVP_Planning.md`](../BMyBench_MVP_Planning.md) e [`journal.json`](./journal.json) (diário de contexto).

## Status

Fase 0 Concluída. Estrutura Flutter gerada para macOS, Windows, Linux e Android.
Telas Sistema/Sensores/Bateria/Benchmark criadas como stub funcional.
SystemInfo faz coleta real no macOS via `sysctl`/`df`/`sw_vers`.

## Como rodar

```bash
cd BeMyBench
../flutter/bin/flutter pub get
../flutter/bin/flutter run -d macos
```
