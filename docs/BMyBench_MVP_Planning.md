# BMyBench — Planejamento e Rastreabilidade do Produto (v1.0 Concluída)

**Nome:** BMyBench (*Be My Bench*)  
**Conceito:** Ferramenta moderna de diagnóstico de hardware, cross-platform, com ciclo integrado de diagnóstico + benchmark + saúde da bateria + ajustes e manutenção do sistema.  
**Plataformas Suportadas:** macOS, Windows, Linux e Android — 1 codebase Flutter + Rust, 4 pacotes finais via CI/CD.

---

## 1. Visão do Produto

O BMyBench fecha o ciclo completo de performance:  
**Diagnosticar → Medir → Limpar / Ajustar → Medir de novo**

Diferencial: vai além das ferramentas tradicionais de diagnóstico que apenas listam hardware (somente leitura) ou suítes de benchmark que só entregam um número final sem ações corretivas.

---

## 2. Status de Requisitos Implementados

| # | Funcionalidade | Status | Plataformas | Implementação / Detalhes |
|---|---|:---:|---|---|
| 1 | **System Info Granular** | Concluído | macOS, Win, Linux, Android | 9 abas de hardware detalhado (Processador, RAM, GPU/Displays, Placa-Mãe, USB/Conexões, Storage, Rede, Peculiaridades). |
| 2 | **Sensores em Tempo Real** | Concluído | macOS, Linux, Windows | Carga de CPU, RAM e telemetria contínua a cada 2s via kernel Darwin e sysfs. |
| 3 | **Bateria (Saúde e Ciclos)** | Concluído | macOS (real), Win, Linux, Android | Diagnóstico de % atual, saúde (% de design), contagem de ciclos e status de carga. |
| 4 | **Benchmark CPU (Leve)** | Concluído | macOS, Win, Linux, Android | Motor em Rust nativo (single e multi-core) com score proprietário. |
| 5 | **Benchmark Memória (Leve)** | Concluído | macOS, Win, Linux, Android | Banda de leitura/escrita (GB/s) e latência por pointer chasing (ns). |
| 6 | **Benchmark Disco (Sequencial)**| Concluído | macOS, Win, Linux, Android | Leitura e escrita sequencial em arquivo temporário descartável. |
| 7 | **GPU Render & Compute HDR** | Concluído | macOS (Metal) / Windows-Linux (Vulkan) | Shaders de renderização HDR off-screen, 1.024 cubos, MSAA 4× e medição de FPS e frame pacing (1% low e p99). |
| 8 | **Detecção Touch & Adaptativo** | Concluído | Todas | Alternância automática entre `TopNav` desktop e `NavigationBar` móvel. |
| 9 | **Storage Breakdown** | Concluído | Todas | Detalhamento de volumes montados, espaço livre e capacidade usada. |
| 10 | **Histórico de Benchmarks** | Concluído | Todas | Armazenamento local persistido em JSON para acompanhamento temporal. |
| 11 | **Estresse e Torture Test** | Concluído | macOS / Linux / Windows | Carga sustentada com 16.384 instâncias, fractal browniano e monitoramento térmico. |
| 12 | **Limpeza Inteligente de Disco** | Concluído | macOS, Windows, Linux | Varredura de caches e temporários com whitelist de segurança e proteção de 1h. |
| 13 | **Boost de RAM Inteligente** | Concluído | macOS, Windows, Linux | Purga de páginas inativas de VM com medição antes vs. depois. |
| 14 | **Ajustes: Atualização de Pacotes**| Concluído | Windows (`winget`), Linux (`apt`), macOS (`brew`) | Modal visual interativo com log e progresso; omitido se o SO não tiver gerenciador. |
| 15 | **Ajustes: Varredura de Drivers** | Concluído | Windows (COM Update), Linux (`fwupd`), macOS | Pesquisa sob demanda nos canais oficiais de drivers e firmwares. |
| 16 | **Ajustes: Diagnóstico de Falhas**| Concluído | Windows (WMI PnP), Linux (`lspci`/`dmesg`), macOS | Mapeamento amigável de erros (Código 28, 10, 43) e hardware sem driver de kernel. |
| 17 | **Automação de CI/CD Release** | Concluído | GitHub Actions | Builds automatizados gerando APK (Android NDK), DMG (macOS), ZIP (Windows) e TAR.GZ (Linux). |

---

## 3. Diretriz de UX e Omissão Silenciosa

- **Sem Disclaimers Educativos:** É estritamente proibido exibir avisos como *"Aviso: Android não possui gerenciador de hardware"*.
- **Omissão Completa:** Se uma plataforma não for compatível com um determinado recurso (ex: Android para atualizadores de pacotes CLI ou macOS sem Homebrew), o botão ou a seção simplesmente não existe.

---

## 4. Estrutura de Código Final

```
BMyBench/
├── .github/workflows/
│   ├── ci.yml                 # Testes contínuos e análise estática (Ubuntu e macOS)
│   └── release.yml            # Pipeline de build e publicação multi-plataforma (4 OS)
├── android/                   # Projeto Android nativo (Gradle Kotlin DSL, Java 17)
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

---

## 5. Histórico de Execução de Fases

### Fase 0 — Fundação: CONCLUÍDA
- [x] Projeto Flutter multi-plataforma
- [x] Tema escuro adaptativo desktop vs. touchscreen
- [x] Navegação superior (TopNav) e móvel (NavigationBar)
- [x] Estruturação dos 4 pacotes nativos (macOS, Windows, Linux, Android)

### Fase 1 — Núcleo de Diagnóstico: CONCLUÍDA
- [x] System Info granular com 9 abas especializadas
- [x] Sensores de CPU e RAM em tempo real
- [x] Telemetria de bateria com cálculo de saúde e contagem de ciclos
- [x] Painel de storage breakdown

### Fase 2 — Benchmark e Estresse: CONCLUÍDA
- [x] Motor em Rust puro para CPU (single e multi-core)
- [x] Benchmark de memória (largura de banda GB/s e latência ns)
- [x] Benchmark de disco sequencial
- [x] GPU Metal/Vulkan com render HDR off-screen, 1.024 cubos e MSAA 4×
- [x] Teste de estresse contínuo com detecção de thermal throttling

### Fase 3 — Histórico e Inspeção Aprofundada: CONCLUÍDA
- [x] Histórico persistido localmente em JSON
- [x] Inspeção granular de hardware (eliminação completa de marcas de terceiros)
- [x] Navegação fluida nas abas com suporte a arraste de mouse, roda horizontal e chevrons

### Fase 4 / V1.1 — Auxílio de Desempenho e Ajustes: CONCLUÍDA
- [x] Limpeza inteligente de disco com whitelist estrita de segurança e proteção de arquivos em uso
- [x] Boost de RAM com purga de VM do kernel e telemetria antes vs. depois
- [x] Atualização de pacotes CLI (Windows winget, Linux apt, macOS Homebrew) em modal visual
- [x] Varredura sob demanda de drivers oficiais (Windows Update COM, Linux fwupd, macOS softwareupdate)
- [x] Diagnóstico de hardware com código de erro ou ausência de driver de kernel
- [x] Pipeline automatizada no GitHub Actions gerando os 4 instaladores na Release v1.0
