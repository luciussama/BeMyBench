# BMyBench (Be My Bench)

**AIDA64 moderno e cross-platform.** Diagnóstico de hardware + benchmark com score próprio + saúde de bateria + (futuro) auxílio de desempenho.

> **MVP = ler e medir.** Ações destrutivas (limpar, atualizar, estressar) ficam para a V1.1.
> Planejamento completo: [`docs/BMyBench_MVP_Planning.md`](docs/BMyBench_MVP_Planning.md)
> Diário de contexto (decisões, progresso, números medidos): [`journal.json`](journal.json)

## Stack

| Camada | Tecnologia |
|---|---|
| UI | Flutter 3.47.9 / Dart 3.13.7 |
| Benchmark core | Rust 1.99.1 (cdylib, C ABI) |
| Integração | `dart:ffi` puro (sem `flutter_rust_bridge`, sem plugin) |
| Dados de sistema | `Process.run` (sysctl / ioreg / vm_stat / top / df) |

## Estado atual

| Fase | Status |
|---|---|
| 0 — Fundação (4 plataformas, tema touch, navegação) | ✅ |
| 1 — Sistema (macOS real) | ✅ |
| 1 — Bateria (macOS real) | ✅ |
| 1 — Sensores CPU/RAM (macOS/Linux) | ✅ |
| 2 — Benchmarks CPU/Memória/Disco | ✅ |
| 2 — GPU Metal (compute + render) + comparação | ✅ |
| 3 — MVP+ (RAM single/dual, saúde SSD, temp, updates) | ⏳ |
| V1.1 — Cleaner, Updater, FurMark, teste de descarga | ⏳ |

## Como rodar

Pré-requisitos: Xcode, Flutter SDK e Rust.

```bash
# build + embute a dylib + abre o app
./tool/package_macos.sh

# desenvolvimento com hot reload
flutter run -d macos
```

> A dylib é carregada de `Contents/Frameworks/` no bundle. Em desenvolvimento, há fallback
> para `rust/target/release/`. Também é possível forçar com
> `--dart-define=BMB_CORE_LIB=/caminho/libbemybench_core.dylib`.

## Comandos úteis

```bash
flutter analyze
flutter test
dart run tool/check_battery.dart     # leitura real da bateria
dart run tool/check_sensors.dart     # CPU/RAM em tempo real
dart run tool/check_bench.dart       # benchmarks fora da UI
cd rust && cargo test --release      # testes do core
```

## Metodologia do benchmark

Score próprio — **não** clona Geekbench/Cinebench.

- **CPU:** mistura de inteiros (xorshift), ponto flutuante e acesso a memória local, em janela
  fixa de tempo. Score = Mops/s single-core + Mops/s multi-core.
- **Memória:** banda sequencial de escrita/leitura/cópia (GB/s) + latência de acesso aleatório
  via pointer chasing (ns).
- **Disco:** leitura/escrita sequencial em arquivo temporário, removido ao final.
- **GPU compute (macOS):** kernel Metal de compute (FMA + sin/cos/sqrt) sobre
  1920×1080 off-screen, medido pelo tempo de GPU do command buffer.
- **GPU render (macOS):** cena 3D em 1920×1080 off-screen com 1.024 cubos
  instanciados (12.289 triângulos/frame), depth buffer, sky procedural com 24 passos
  de ruído e iluminação difusa/especular. Mede fps médio e frame pacing
  (1% low e p99). Exercita rasterização, vertex/fill rate, depth e shading.
- **Score:** frames/s × 100. A conversão para 3DMark Time Spy Graphics usa o teste
  de **render**; Geekbench 6 Metal usa o teste de **compute**. Ambas são lineares,
  calibradas no dispositivo âncora de `assets/data/reference_gpu.json` — são
  estimativas, não resultados oficiais.

Referência medida neste MacBook (Apple M5, 8-core GPU):
`GPU compute ≈ 263 fps` · `GPU render ≈ 302 fps` · `1% low ≈ 277` · `p99 ≈ 3,6 ms` ·
scores ≈ 26.3k / 30.2k · conversão estimada `Time Spy ≈ 3.000` · `GB6 Metal ≈ 61.000`.
`CPU score ≈ 4.872` · `RAM leitura ≈ 35 GB/s` · `latência ≈ 13 ns` · `SSD ≈ 3.7 GB/s leitura`.

## Armadilhas conhecidas

1. **Não coloque o projeto em `~/Documents`.** O macOS 27 protege essa pasta (TCC) e o
   `xcodebuild` falha com `disk I/O error` no `build.db`. Projeto fica em `~/repos/BeMyBench`.
2. **Não use `Size.fromHeight()` em tema de botão.** Isso vira `width: Infinity` e quebra
   qualquer botão dentro de `Row` (a tela fica preta). Use `Size(0, altura)`.
3. **Não assine o app com `codesign --deep`.** Reassinar os frameworks do Flutter quebra o bundle.

## Estrutura

```
lib/
  core/
    native/native_core.dart      # FFI: carrega a dylib Rust
    platform/platform_detector.dart
    theme/app_theme.dart         # touch vs desktop
    widgets/dashboard.dart       # painéis, tiles, chips e gráficos
  features/
    system_info/  sensors/  battery/  benchmark/
    performance/                 # stubs V1.1 (cleaner, updater, ram_disk)
macos/Runner/GpuBenchmark.swift  # kernel Metal off-screen (MethodChannel)
rust/src/lib.rs                  # CPU + memória (C ABI)
tool/                            # probes e package_macos.sh
docs/                            # planejamento
journal.json                     # diário de contexto
```
