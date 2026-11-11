# Histórico de Alterações e Rastreabilidade (CHANGELOG) — BMyBench

Todas as decisões técnicas, implementações de funcionalidades, correções de bugs e lançamentos de versões do projeto BMyBench estão documentados cronologicamente neste arquivo para garantir 100% de rastreabilidade diretamente no controle de versão (Git).

---

## [Não lançado] — 2026-11-11

### Corrigido
* **Benchmark de vídeo (GPU) e estresse de vídeo no Android:** os testes não existiam na plataforma — o canal `bemybench/gpu` só tinha implementação em Swift (macOS) e C++/D3D11 (Windows), e `GpuBenchmarkService.isSupported` retornava `false` no Android. O chip de GPU aparecia como "em breve" e a visualização 3D não abria.

### Adicionado
* **Backend nativo de GPU para Android (`android/app/src/main/kotlin/com/example/bemybench/gpu/`):**
  * `OffscreenGl` — contexto EGL off-screen (Pbuffer) com OpenGL ES 2.0, 1920×1080 fixos, medindo `glFinish` por quadro para calcular fps, p99, p99.9 e 1% low.
  * `SceneRenderer` — pipeline compartilhado de 5 passes (cena volumétrica por raymarching com fBm → bright pass → blur horizontal → blur vertical → composite com bloom, tonemap ACES, vinheta e gamma), usado tanto no benchmark quanto na visualização ao vivo.
  * `GpuBenchmarkChannel` — implementa o mesmo contrato do canal `bemybench/gpu`: `info`, `run`, `run_render`, `open_3d_window`, `close_3d_window` e `is_3d_window_open`. Todo o trabalho OpenGL executa em uma thread dedicada.
  * `GpuLiveWindow` — visualização 3D ao vivo em tela cheia (diálogo + `GLSurfaceView`) com HUD nativo (FPS, ms/quadro, p99, GPU, modo e cronômetro) e botão de fechar. A cena é renderizada internamente em 1920×1080 e apenas apresentada escalada na tela, mantendo o FPS do HUD comparável ao resultado numérico.
  * Quando a visualização está aberta, `run_render` amostra o throughput real da cena ao vivo (mesma estratégia do backend Windows), evitando duas cargas concorrentes na GPU.
* **Dart (`lib/features/benchmark/gpu_benchmark.dart`):** `isSupported` agora inclui Android; rótulos por API (`Metal`, `Direct3D 11`, `OpenGL ES`) e por tipo de visualização (janela flutuante no desktop, tela cheia no Android); novos campos `shadingIterations`, `pipelineLabel` e `sceneLabel` para descrever honestamente o pipeline de cada backend.
* **Tela de Benchmark/Estresse:** descrições e chips passam a refletir a API nativa da plataforma; o resumo de resultados exibe o pipeline real (MSAA/HDR/bloom/passes) e a cena (cubos instanciados ou raymarching) sem valores fixos do macOS.
* **AndroidManifest:** declaração de OpenGL ES 2.0 (`uses-feature glEsVersion`) exigida pelo benchmark e pela visualização 3D.

### Documentação
* README atualizado com o backend OpenGL ES, a nova linha do status e a contagem de testes (30).

---

## [v1.0.0] — 2026-11-06

### Adicionado
* **Ajustes do Sistema (3 Pilares de Manutenção):**
  * **Pilar 1 (Atualização de Pacotes CLI):** Interface visual interativa (`PackageUpdaterModal`) para atualização de pacotes sem terminal (Windows: `winget upgrade --all`; Linux: `apt`/`dnf`/`pacman` com elevação gráfica via Polkit `pkexec`; macOS: Homebrew).
  * **Pilar 2 (Varredura de Drivers):** Consulta nativa ao Windows Update Agent via COM (`Microsoft.Update.Session`) e `pnputil /scan-devices` no Windows; consulta ao LVFS (`fwupdmgr`) e `ubuntu-drivers` no Linux; e consulta ao `softwareupdate` no macOS.
  * **Pilar 3 (Diagnóstico de Hardware Problemático):** Mapeamento semântico amigável de erros do Gerenciador de Dispositivos via WMI `Win32_PnPEntity` (Código 28 - driver não instalado, Código 10 - falha de inicialização, Código 43 - dispositivo interrompido); detecção de dispositivos PCI sem módulo de kernel ativo no Linux via `lspci -nnk` e análise de falhas de firmware em `dmesg`.
  * **Diretriz de Design (Omissão Estrita):** Sem disclaimers educativos por plataforma. Plataformas incompatíveis omitem silenciosamente os botões ou a aba inteira.
* **Automação de CI/CD Multi-Plataforma (`.github/workflows/release.yml`):**
  * Pipeline de 5 jobs no GitHub Actions gerando binários em runners nativos:
    * `bemybench-android.apk` (Android NDK + cargo-ndk compilando Rust para `arm64-v8a`, `armeabi-v7a` e `x86_64`).
    * `bemybench-macos.dmg` (compilação de dylib, empacotamento e assinatura).
    * `bemybench-windows-x64.zip` (compilação de DLL Rust e executável Win32 no runner Windows).
    * `bemybench-linux-x64.tar.gz` (compilação com GTK3/Ninja/CMake no runner Ubuntu).
    * Publicação automática na aba GitHub Releases disparada por tag (`v*`) ou manual (`workflow_dispatch`).
* **Suporte Nativo a Android no `NativeCore`:** Suporte a `dlopen` nativo de `libbemybench_core.so` diretamente do bundle `jniLibs` do APK.

### Corrigido
* **Parsers de Drivers e Hardware no CI:**
  * Correção do parser `parseUbuntuDriversOutput` para extrair o nome limpo do driver ignorando sufixos como `- distro non-free recommended`.
  * Correção do parser `parseDmesgOutput` para capturar linhas de falha contendo `Direct firmware load for ... failed`.
  * Correção de vazamento de timer periódico em `widget_test.dart` e remoção de delay artificial de 500 ms em `SensorsService._collectLinux()`.

---

## [v0.4.0] — 2026-11-06 / 2026-11-07

### Adicionado
* **Inspeção Granular de Hardware (Substituição de Marcas Proprietárias):**
  * 9 abas especializadas em `HardwareScreen`: Visão Geral, Processador, Memória RAM, Gráficos & Telas, Placa-Mãe & EFI, USB & Conexões, Armazenamento, Rede e Peculiaridades de Plataforma.
  * Substituição de marcas registradas de terceiros (CPU-Z, GPU-Z, HWiNFO) por rótulos descritivos funcionais ("DETALHES DO PROCESSADOR", "DETALHE DA GPU", "DETALHES DE CONEXÕES & BARRAMENTOS").
  * Exposição de clusters assimétricos de P-Cores e E-Cores, hierarquia de caches L1/L2/L3 e conjuntos de instruções.
  * Explicação detalhada de arquitetura de memória unificada (UMA) on-package sem slots DIMM avulsos.
* **Ferramentas de Desempenho (Performance Aid):**
  * **Limpeza de Disco Inteligente (`CleanDiskDialog`):** Varredura segura de caches de usuário, desenvolvedor (DerivedData, Gradle, pub-cache), logs órfãos e arquivos temporários com whitelist rigorosa por sistema operacional e proteção de idade mínima (1 hora).
  * **Boost de RAM Inteligente (`RamBoostDialog`):** Purga de memória virtual e descarte de buffers inativos via `/usr/sbin/purge` e pressão transitória de kernel, com telemetria antes vs. depois da liberação.
* **Melhorias de Navegação e UX:**
  * Implementação de `AppScrollBehavior` global com suporte a rolagem por arraste de mouse, roda do mouse horizontal e botões de navegação lateral (chevrons) com auto-scroll inteligente para centralizar a aba selecionada.

---

## [v0.3.0] — 2026-11-06

### Adicionado
* **Janela Gráfica 3D Desvinculada de VSync (Metal / Vulkan):**
  * Janela nativa flutuante com renderização off-screen de alta carga.
  * Desvinculação de VSync (`Uncapped FPS`) para aferição do teto real de quadros por segundo da GPU.
  * HUD gráfico translúcido integrado na janela 3D com 6 métricas em tempo real: GPU Name, % Carga, Clock, V-RAM, Temperatura e FPS médio / 1% low.
* **Aprimoramento do Teste de Estresse (Torture Test):**
  * Saturação massiva da GPU com 16.384 instâncias geométricas, fractal browniano (fBm) e shaders de compute concorrentes.
  * Calibração de limites térmicos e detecção de instabilidade/throttling.

---

## [v0.2.0] — 2026-11-05

### Adicionado
* **Armazenamento e Histórico Local:**
  * Painel de quebra de volumes e discos montados (`df -kP` / Storage Breakdown).
  * Persistência de histórico de pontuações de benchmarks em JSON local para comparação temporal de evolução do hardware.

---

## [v0.1.0] — 2026-11-05

### Adicionado
* **Núcleo de Diagnóstico e Benchmarking Leve:**
  * Leitura e diagnóstico de saúde de bateria (capacidade atual vs. design, contagem de ciclos e status).
  * Sensores de CPU e RAM em tempo real via comandos de baixo nível do kernel.
  * Motor de benchmark leve implementado em Rust com compilação para biblioteca dinâmica C-ABI (`cdylib`) e integração via `dart:ffi`.
  * Algoritmos de cálculo de pontuação para CPU (single/multi-core), Memória (largura de banda e latência de pointer chasing) e Disco (leitura/escrita sequencial).
  * Renderizador GPU Metal inicial com MSAA e shaders computacionais no macOS.

---

## [v0.0.1] — 2026-11-05

### Adicionado
* **Fundação do Projeto (Fase 0):**
  * Estruturação do projeto Flutter com suporte a macOS, Windows, Linux e Android a partir de uma única base de código.
  * Tema escuro adaptativo desktop vs. touchscreen (`AppTheme`, `AppColors`).
  * Barra de navegação superior (`TopNav`) e navegação inferior móvel (`NavigationBar`).
  * Pipeline básica de integração contínua (CI) no GitHub Actions (`.github/workflows/ci.yml`).
