# BMyBench (Be My Bench)

[![CI](https://github.com/luciussama/BeMyBench/actions/workflows/ci.yml/badge.svg)](https://github.com/luciussama/BeMyBench/actions/workflows/ci.yml)

**Diagnóstico de hardware e benchmark, cross-platform.** Diagnóstico de hardware + benchmark com score próprio + saúde de bateria + (futuro) auxílio de desempenho.

> Repositório público para referência. **Não há licença e contribuições externas não estão abertas no momento.**
> **MVP = ler e medir.** Ações destrutivas (limpar, atualizar, estressar sem limite) ficam para a V1.1.
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
| 2 — GPU Metal (compute + render HDR) + comparação | ✅ |
| 2 — Estresse contínuo de GPU (aba Estresse) | ✅ |
| CI — GitHub Actions (analyze + testes + build macOS) | ✅ |
| 3 — MVP+ (RAM single/dual, saúde SSD, temp, updates) | ⏳ |
| V1.1 — Cleaner, Updater, teste térmico de GPU, teste de descarga | ⏳ |

## Como rodar

Pré-requisitos: Xcode, Flutter SDK (3.47.9) e Rust (stable).

```bash
git clone https://github.com/luciussama/BeMyBench.git
cd BeMyBench

# build + compila o core Rust + embute a dylib + assina e abre o app
./tool/package_macos.sh

# desenvolvimento com hot reload
flutter run -d macos
```

> A dylib é carregada de `Contents/Frameworks/` no bundle. Em desenvolvimento, há fallback
> para `rust/target/release/`. Também é possível forçar com
> `--dart-define=BMB_CORE_LIB=/caminho/libbemybench_core.dylib`.

## Principais comandos

```bash
flutter analyze
flutter test
dart run tool/check_battery.dart     # leitura real da bateria
dart run tool/check_sensors.dart     # CPU/RAM em tempo real
dart run tool/check_bench.dart       # benchmarks fora da UI
cd rust && cargo test --release      # testes do core
```

## Fluxo de trabalho

A `main` é a linha estável. Cada iteração a partir de agora acontece em uma
**branch própria** e só entra em `main` via Pull Request:

```bash
git checkout -b iter/<nome-da-iteracao>
# ... trabalho ...
git push -u origin iter/<nome-da-iteracao>
gh pr create --base main
```

- A `main` exige Pull Request e CI verde para aceitar mudanças (proteção de branch)
- Releases são marcadas com tags anotadas (`git tag -a v2 -m "..."`)
- O `v1` marca o ponto de partida deste fluxo
- Uso pessoal e de referência; sem licença e sem contribuições externas no momento

## CI (GitHub Actions)

A cada push em `main` e em cada Pull Request, o workflow
[`ci.yml`](.github/workflows/ci.yml) executa:

| Job | Plataforma | O que faz |
|---|---|---|
| `Flutter analyze + test` | Ubuntu + macOS | `flutter pub get` → `flutter analyze` → `flutter test` |
| `Rust (core)` | Ubuntu | `cargo test --release` em `rust/` |
| `Build macOS app` | macOS | `cargo build --release` → `flutter build macos --debug` (sem assinatura) |

O badge no topo do README reflete o status atual da branch `main`.

## Metodologia do benchmark

Score próprio — **não** replica suítes de referência de terceiros.

- **CPU:** mistura de inteiros (xorshift), ponto flutuante e acesso a memória local, em janela
  fixa de tempo. Score = Mops/s single-core + Mops/s multi-core.
- **Memória:** banda sequencial de escrita/leitura/cópia (GB/s) + latência de acesso aleatório
  via pointer chasing (ns).
- **Disco:** leitura/escrita sequencial em arquivo temporário, removido ao final.
- **GPU compute (macOS):** kernel Metal de compute (FMA + sin/cos/sqrt) sobre
  1920×1080 off-screen, medido pelo tempo de GPU do command buffer.
- **Aba Estresse:** roda o mesmo render em passos de 1 s (30 s / 60 s / contínuo),
  registra fps ao longo do tempo e carga da CPU, e infere thermal throttling pela
  queda entre o pico e o pior valor amostrado.
- **GPU render (macOS):** pipeline HDR completo em 1920×1080 off-screen — MSAA 4×
  com resolve, HDR `rgba16Float`, 1.024 cubos instanciados com depth, iluminação
  difusa/especular, céu procedural, bloom (bright pass + blur separável em meia
  resolução) e tonemap ACES com gamma. São 5 passes por frame. Mede fps médio e
  frame pacing (1% low e p99).
- **Score:** frames/s × 100. A conversão para o score gráfico de referência (rasterização) usa o teste
  de **render**; o score de compute de referência usa o teste de **compute**. Ambas são lineares,
  calibradas no dispositivo âncora de `assets/data/reference_gpu.json` — são
  estimativas, não resultados oficiais.

Referência medida neste MacBook (Apple M5, 8-core GPU):
`GPU compute ≈ 263 fps` · `GPU render ≈ 272 fps` · `1% low ≈ 220` · `p99 ≈ 4,6 ms` ·
scores ≈ 26.3k / 27.3k · conversão estimada `score gráfico de referência ≈ 3.000` · `score de compute de referência ≈ 61.000`.
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
    system_info/  sensors/  battery/  benchmark/  stress/
    performance/                 # stubs V1.1 (cleaner, updater, ram_disk)
macos/Runner/GpuBenchmark.swift  # kernel Metal off-screen (MethodChannel)
rust/src/lib.rs                  # CPU + memória (C ABI)
integration_test/                # GPU channel em app real (flutter test -d macos)
.github/workflows/ci.yml         # analyze + testes + build macOS
tool/                            # probes e package_macos.sh
docs/                            # planejamento
journal.json                     # diário de contexto
```
