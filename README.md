# BMyBench (Be My Bench) — v1.0

[![CI](https://github.com/luciussama/BeMyBench/actions/workflows/ci.yml/badge.svg)](https://github.com/luciussama/BeMyBench/actions/workflows/ci.yml)
[![Build & Release Multi-Platform Packages](https://github.com/luciussama/BeMyBench/actions/workflows/release.yml/badge.svg)](https://github.com/luciussama/BeMyBench/actions/workflows/release.yml)

**BMyBench** é uma ferramenta moderna de diagnóstico de hardware, benchmarking com motor próprio e manutenção de sistema, desenvolvida com foco em alta eficiência, segurança e interface adaptativa cross-platform (macOS, Windows, Linux e Android).

O aplicativo fecha o ciclo completo de saúde do computador:
**Diagnosticar → Medir → Limpar / Ajustar → Medir novamente**

---

## Principais Recursos por Aba

O BMyBench conta com 7 módulos principais organizados na barra de navegação superior (desktop) ou barra inferior adaptativa (touch/mobile):

1. **Hardware (Inspeção Granular por Subsistema):**
   * **Visão Geral:** Métricas em tempo real de carga de CPU, RAM, GPU e disco livre com card de status ativo.
   * **Processador:** Topologia de núcleos (Performance vs. Efficiency no Apple Silicon e Intel/AMD), hierarquia de caches L1i, L1d, L2 e L3, microarquitetura e extensões de instruções suportadas (NEON, FP16, AES, AVX2, etc.).
   * **Memória RAM:** Padrão de barramento, velocidade (MT/s), fabricante dos chips, canais e explicação educativa de arquitetura de memória unificada (UMA) on-package.
   * **Gráficos & Telas:** Detalhamento da GPU, núcleos de render/compute, V-RAM integrada/dedicada, barramento e monitores conectados (resolução nativa, taxa de atualização, perfil de cor P3).
   * **Placa-Mãe & EFI:** Fabricante, modelo de placa lógica, versão de firmware EFI/Boot ROM, chipset e identificadores UUID.
   * **USB & Conexões:** Barramentos Thunderbolt 4 / USB4 e controladoras xHCI com periféricos conectados.
   * **Armazenamento:** Partições de mídia montadas (APFS, ext4, NTFS) com interface NVMe/SATA e ocupação percentual.
   * **Rede:** Adaptadores Wi-Fi e Ethernet ativos, endereços MAC físicos e IPv4 local.
   * **Peculiaridades de Plataforma:** Matriz técnica transparente explicando diferenças de leitura de hardware entre macOS, Windows (WMI), Linux (DMI/root) e Android (sandbox SELinux).

2. **Sensores (Monitoramento Térmico e de Carga):**
   * Leitura contínua a cada 2 segundos de carga de CPU, uso de RAM, temperaturas e ventoinhas (quando expostas pela plataforma).
   * **Temperaturas separadas de CPU e GPU**, cada uma com a origem explicitada na interface: sensor real (ACPI/hwmon/zona térmica/nvidia-smi) ou modelo térmico calibrado ("estimado").
   * **Quadro de carga por núcleo:** um cartão por thread lógica com percentual e barra, resumo (média, pico, núcleos ociosos e saturados) e destaque do núcleo mais carregado. Onde o SO bloqueia a leitura de uso (`/proc/stat` no Android 12+), o painel mostra a **frequência real por núcleo** em vez de inventar percentuais.

3. **Bateria (Saúde e Ciclos):**
   * Diagnóstico aprofundado com % atual, saúde da bateria (% da capacidade de design original), contagem de ciclos, status de carga e estimativa de autonomia.

4. **Benchmark (Motor em Rust com Score Próprio):**
   * **CPU Benchmark:** Teste single-core e multi-core em janela fixa de tempo com algoritmo misto de operações inteiras (xorshift), ponto flutuante e memória local.
   * **Memória Benchmark:** Medição de largura de banda sequencial (GB/s) de leitura/escrita e latência de acesso aleatório via pointer chasing (ns).
   * **Disco Benchmark:** Medição sequencial de leitura/escrita em arquivo temporário com limpeza automática ao término.
   * **GPU Benchmark (Metal / Direct3D 11 / OpenGL ES):** Pipeline HDR off-screen completo a 1920×1080 com MSAA 4×, 1.024 cubos instanciados, iluminação difusa/especular, céu procedural, bloom e tonemap ACES. Mede FPS médio e frame pacing (1% low e p99). No Android o mesmo teste roda em OpenGL ES 2.0 (EGL off-screen) com cena volumétrica por raymarching, bloom em 5 passes e frame pacing medido por quadro.
   * **Painel Comparativo:** Banco de dados integrado de dispositivos de referência para comparação direta de performance.

5. **Estresse (Estresse Térmico e Torture Test):**
   * Renderização gráfica contínua para monitoramento de estabilidade e detecção de *thermal throttling* com carga parametrizável e HUD em tempo real.

6. **Histórico:**
   * Registro histórico local com data, pontuação de CPU, memória, disco e GPU para acompanhamento da evolução da máquina após manutenções.

7. **Ajustes do Sistema (Manutenção em 3 Pilares):**
   * **Pilar 1 — Atualização de Pacotes:** Interface visual interativa para atualização de pacotes do sistema sem abrir terminais CLI (Windows: `winget upgrade --all`; Linux: `apt`/`dnf`/`pacman` com elevação gráfica via Polkit `pkexec`; macOS: Homebrew). Omitido silenciosamente se a plataforma não tiver gerenciador ativo.
   * **Pilar 2 — Varredura por Drivers:** Verificação ativa de atualizações de drivers e firmwares oficiais (Windows Update via COM `Microsoft.Update.Session`; Linux via `fwupdmgr` LVFS e `ubuntu-drivers`; macOS via `softwareupdate`).
   * **Pilar 3 — Diagnóstico de Hardware Problemático:** Identificação imediata de hardware com driver não localizado (ex: Código 28 no Windows ou falta de módulo de kernel no Linux via `lspci -nnk`) ou com falhas operacionais (Código 10, Código 43), acompanhado de ações corretivas recomendadas.
   * **Regra de Omissão Estrita:** Sem disclaimers por plataforma. Em plataformas sem suporte (ex: Android), os recursos e a aba são completamente omitidos.

8. **Ferramentas de Desempenho Integradas na Tela de Hardware:**
   * **Limpeza Inteligente de Disco (SSD):** Modal com varredura segura de caches órfãos, temporários descartáveis e crash logs com whitelist estrita por SO, proteção de idade mínima (1 hora) e preservação de arquivos em uso.
   * **Boost de RAM:** Purga de memória virtual e descarte de buffers inativos via `/usr/sbin/purge` e pressão transitória de kernel, com telemetria antes vs. depois da liberação de RAM.

---

## Arquitetura e Stack Tecnológico

```
BeMyBench/
├── .github/workflows/
│   ├── ci.yml                 # Testes contínuos e análise estática (Ubuntu e macOS)
│   └── release.yml            # Pipeline de build e publicação multi-plataforma (4 OS)
├── android/                   # Projeto Android nativo (Gradle Kotlin DSL, Java 17, OpenGL ES)
├── docs/                      # Planejamento, arquitetura e rastreabilidade técnica
│   ├── BMyBench_MVP_Planning.md
│   ├── system_tweaks_architecture.md
│   └── CHANGELOG.md
├── lib/
│   ├── core/                  # Temas, detecção de OS/touch, FFI e widgets base
│   │   ├── native/            # Carregamento nativo com fallback multi-plataforma
│   │   ├── platform/          # Heurística touch e detecção de SO
│   │   ├── theme/             # Paleta escura "dashboard técnico" e scroll adaptativo
│   │   └── widgets/           # TopNav, Dashboard, Grid de Métricas
│   └── features/              # Arquitetura modular por funcionalidade
│       ├── battery/           # Diagnóstico e telemetria de bateria
│       ├── benchmark/         # UI e integração dos testes de CPU/RAM/Disco/GPU
│       ├── cleaner/           # Limpeza de disco e boost de RAM
│       ├── hardware/          # Inspeção granular de hardware
│       ├── history/           # Persistência de resultados anteriores
│       ├── sensors/           # Telemetria contínua
│       ├── storage/           # Detalhamento de volumes
│       ├── stress/            # Teste de tortura e estresse térmico
│       └── system_tweaks/     # Atualizador de pacotes, drivers e diagnóstico de falhas
├── macos/                     # Bundle macOS, Runner e shaders Metal (GpuBenchmark.swift)
├── rust/                      # Núcleo de benchmark de alta performance (C-ABI cdylib)
├── test/                      # Suíte de testes unitários e de widget (100% aprovados)
└── tool/                      # Scripts auxiliares de build e sondas de telemetria
```

| Camada | Tecnologia / Ferramenta |
|---|---|
| **Interface (UI)** | Flutter 3.47.9 / Dart 3.13.7 com tema adaptativo desktop/touch |
| **Motor de Benchmark** | Rust 1.99.1 via C-ABI nativa pura (`dart:ffi`), sem overhead de bridge |
| **Gráficos & Render** | Metal (macOS), Direct3D 11 + Direct2D (Windows) e OpenGL ES 2.0 + EGL (Android) |
| **Dados do Sistema** | Execução de comandos nativos de baixo nível (`sysctl`, `ioreg`, WMI, `/proc`, `lspci`) |
| **CI/CD** | GitHub Actions com runners nativos Ubuntu, macOS e Windows |

---

## Status do Projeto (v1.0 Concluída)

| Fase / Módulo | Status | Descrição |
|---|:---:|---|
| **Fase 0 — Fundação** | ✅ | Estrutura Flutter, 4 plataformas geradas, navegação e tema escuro adaptativo |
| **Fase 1 — Sistema & Bateria** | ✅ | Coleta de dados reais de sistema e telemetria completa de bateria |
| **Fase 1 — Sensores** | ✅ | Telemetria contínua de carga de CPU e uso de memória em tempo real |
| **Sensores Granulares** | ✅ | Temperaturas de CPU e GPU separadas (com origem) e quadro de carga/frequência por núcleo nas 4 plataformas |
| **Fase 2 — Benchmarks Leves** | ✅ | Benchmarks em Rust de CPU (single/multi), Memória (banda/latência) e Disco |
| **Fase 2 — GPU Metal HDR** | ✅ | Render HDR off-screen com MSAA 4×, 1.024 cubos e frame pacing (1% low/p99) |
| **Fase 2 — GPU Direct3D 11** | ✅ | Backend nativo Windows (D3D11) com HUD Direct2D/DirectWrite e VSync desligado |
| **Fase 2 — GPU OpenGL ES (Android)** | ✅ | Backend nativo Android (EGL + GLES 2.0): compute, render com bloom e visualização 3D em tela cheia com HUD |
| **Fase 2 — Estresse Contínuo** | ✅ | Teste de estresse contínuo com detecção de thermal throttling |
| **Iteração 2 — Storage & Histórico** | ✅ | Breakdown de volumes montados e persistência de histórico local |
| **Iteração 3 — Janela 3D Desvinculada** | ✅ | Suporte a VSync uncapped e HUD de telemetria gráfica |
| **Iteração 4 — Hardware Granular** | ✅ | 9 abas de hardware, eliminação de marcas proprietárias, scroll adaptativo |
| **Iteração 4 — Performance Aid** | ✅ | Limpeza inteligente de SSD com whitelist e Boost de RAM com purga de VM |
| **Iteração 5 — Ajustes do Sistema** | ✅ | Atualização de pacotes CLI, varredura de drivers e detecção de falhas |
| **Release v1.0 — CI/CD Multi-Plataforma**| ✅ | Pipeline GitHub Actions gerando APK, DMG, ZIP (Windows x64) e TAR.GZ (Linux) |

---

## Como Executar Localmente

### Pré-requisitos
* **Flutter SDK:** Versão 3.47.9 instalada
* **Rust:** Canal stable com `cargo`
* **macOS:** Xcode Command Line Tools instalados

### Compilar e Rodar no macOS
```bash
# Clona o repositório
git clone https://github.com/luciussama/BeMyBench.git
cd BeMyBench

# Compila o core Rust, embute a dylib no bundle e inicia o app
./tool/package_macos.sh

# Ou em modo desenvolvimento com hot reload
flutter run -d macos
```

### Comandos de Verificação
```bash
flutter analyze                     # Análise estática de código (0 erros/avisos)
flutter test                        # Executa todos os 30 testes unitários e de widget
cd rust && cargo test --release     # Executa testes unitários do core de benchmark
```

---

## CI/CD e Releases Automáticas

O repositório possui duas pipelines automatizadas no GitHub Actions:

1. **CI (`.github/workflows/ci.yml`):**
   * Disparada a cada `git push` ou Pull Request na branch `main`.
   * Executa `flutter analyze`, suíte completa de `flutter test` no macOS e no Ubuntu, compilação e testes unitários do core Rust e build do app macOS.

2. **Build & Release Multi-Plataforma (`.github/workflows/release.yml`):**
   * Disparada automaticamente ao criar uma tag de versão (ex: `v1.0`) ou sob demanda via interface web do GitHub Actions.
   * Compila o aplicativo e publica os 4 pacotes finais na aba **Releases**:
     * **Android:** `bemybench-android.apk` (com `libbemybench_core.so` embutido para arm64-v8a, armeabi-v7a e x86_64 via Android NDK).
     * **macOS:** `bemybench-macos.dmg` (com `libbemybench_core.dylib` embutida em `Contents/Frameworks/`).
     * **Windows:** `bemybench-windows-x64.zip` (com `bemybench_core.dll` e executável Win32).
     * **Linux:** `bemybench-linux-x64.tar.gz` (com `libbemybench_core.so` e bundle GTK3).

---

## Licença e Uso

Uso pessoal e de referência técnica. Não há licença de código aberto aberta para redistribuição comercial e contribuições externas não estão abertas no momento.
