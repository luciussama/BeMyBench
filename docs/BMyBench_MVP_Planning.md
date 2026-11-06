# BMyBench — Planejamento do MVP

**Nome:** BMyBench (*Be My Bench*)
**Conceito:** Uma ferramenta moderna de diagnóstico de hardware, cross-platform, com foco em diagnóstico + benchmark + saúde da bateria.
**Plataformas MVP:** macOS, Windows, Linux e Android — 1 codebase, 4 pacotes.

---

## 1. Visão do produto

Não é só listar hardware. É um ciclo:
**Diagnosticar → Medir → (no futuro) Limpar/Atualizar → Medir de novo**

Isso posiciona o BMyBench além das ferramentas de diagnóstico (só leitura) e das suítes de referência (só score).

---

## 2. Resumo dos requisitos levantados

### Requisitos da MVP original
1. Multi-plataforma: macOS, Windows, Linux, Android
2. Layout adaptativo: touchscreen vs. app padrão
3. Testador de bateria (diferencial)
4. Testes de CPU, GPU e Memória (equivalente às suítes de referência, sem usar as marcas)

### Funções futuras propostas
5. Diagnóstico RAM + Disco (single/dual channel, saúde SSD, velocidade)
6. Limpeza de arquivos temporários (por ambiente)
7. Atualizador de pacotes/sistema (`winget upgrade --all`, `apt upgrade`, etc.)
8. Benchmark GPU de estresse térmico (cena 3D repetitiva, monitoramento térmico)

---

## 3. Critério para decidir o que entra no MVP

Cada função foi avaliada por:
- **Valor percebido** — resolve problema real?
- **Esforço** — simples / médio / complexo
- **Risco** — quebra sistema, permissão, loja, segurança?
- **Dependência** — depende de outra função já pronta?
- **Reuso** — reaproveita código da MVP?

> Regra: MVP entra o que é essencial + o que é *quase de graça* por reuso. Arriscado e complexo fica para V1.1+.

---

## 4. Decisão: o que entra no MVP, o que pode ser adiantado e o que fica depois

### 4.1. MVP — Entra

| # | Função | Esforço | Por que entra |
|---|--------|---------|---------------|
| 1 | **System Info** (CPU, GPU, RAM total, disco, OS, tela, rede) | Médio | Coração de qualquer ferramenta de diagnóstico de hardware. Barato com Flutter + canais nativos. |
| 2 | **Sensores básicos** (temperatura CPU/GPU quando disponível, uso CPU/RAM em tempo real, ventilação quando disponível) | Médio | Esperado em app desse tipo. No macOS limitaríamos ao que a Apple permite (via IOKit/sysctl). |
| 3 | **Bateria — Diagnóstico de saúde** (%, ciclos, capacidade design vs. atual, tensão, status, tempo estimado) | Médio | Seu diferencial. Leitura é simples: `ioreg` (macOS), WMI (Windows), `/sys/class/power_supply` (Linux), `BatteryManager` (Android). |
| 4 | **Benchmark CPU — Leve** (single-core + multi-core, contagem de operações, hash/física) | Médio | Score próprio, sem replicar suítes de terceiros. Pode rodar em Rust/isolate para não travar UI. |
| 5 | **Benchmark Memória — Leve** (velocidade GB/s de leitura/escrita, latência básica) | Médio | Reaproveita o teste de CPU. Sem ele, não há comparação com as suítes de referência. |
| 6 | **Benchmark Disco — Leve** (leitura/escrita sequencial em arquivo temporário) | Baixo | Simples e muito útil. Já cobre parte do item 5 futuro. |
| 7 | **GPU Info + Teste FPS simples** (nome, VRAM/unificada, FPS de render off-screen 5-10s) | Baixo/Médio | Nome da GPU é fácil na System Info. FPS simples c/ Metal/Vulkan/OpenGL dá um score sem precisar do teste de estresse térmico completo. |
| 8 | **Detecção Touch** (botões maiores, gestos, layout adaptativo) | Baixo | Flutter já detecta `PointerDeviceKind.touch`. Só aplicar tema/layout condicional. |
| 9 | **Storage Breakdown (somente leitura)** (quanto ocupa app, temp, sistema) | Baixo | Metade do "limpador" sem risco. Mostra espaço, não apaga nada. |

### 4.2. MVP+ — Adiantar porque é simples e de alto valor

Essas foram pensadas para a “segunda leva”, mas são tão simples que valem já no MVP:

| Função | Versão MVP | O que fica para depois |
|--------|------------|------------------------|
| **RAM Single/Dual Channel** | Campo informativo na System Info (Windows/Linux via WMI/SMBIOS, macOS/Android = “Memória unificada/LPDDR — N/A”) | Tela completa de diagnóstico de RAM |
| **Saúde SSD (leitura)** | Nome, tamanho, interface (NVMe/SATA), % usada, temperatura se disponível | SMART completo, TBW, previsão de vida |
| **Escaneador de Temporários** | Lista pastas comuns + tamanho total, sem apagar | Botão “Limpar” com segurança |
| **Verificador de Atualizações** | Lista se há updates (`winget upgrade`, `apt list --upgradable`) sem instalar | Botão único “Atualizar tudo” |

> Motivo: o código para *ler/informar* essas coisas é quase o mesmo do MVP. O risco está em *agir* (apagar, atualizar), e isso fica para a V1.1 com proteções.

### 4.3. V1.1 — Deixar para logo depois do MVP

| Função | Por que não no MVP |
|--------|-------------------|
| **Teste completo de bateria** (descarga real 100%→20%, autonomia real) | Demora horas, precisa de controle de brilho/carga, difícil de validar em todos os sistemas. O diagnóstico de saúde já entrega 80% do valor. |
| **Limpeza com exclusão** | Risco alto: apagar errado quebra app/sistema. Precisa whitelist, confirmação, ponto de restauração (Windows), sudo/admin, e cuidados com Play Store/App Store. |
| **Atualizador 1-clique** (`winget upgrade --all`, `apt upgrade`) | Simples de chamar, complexo de fazer bem: streaming de output, pedir admin, lidar com erro, detectar distro (Debian/RHEL/Arch), aprovação do usuário. |
| **Teste térmico completo** (cena 3D pesada + throttling) | O mais complexo: shader/tessellation em Metal+Vulkan, limite térmico automático, risco de esquentar a GPU. O FPS simples do MVP já valida a pipeline. |

---

## 5. Arquitetura sugerida (preparada para crescer)

```
BMyBench/
├── lib/
│   ├── core/
│   │   ├── theme/               # touch vs desktop
│   │   ├── platform/            # detecção de OS + touch
│   │   └── permissions/         # base para futuro cleaner/updater
│   ├── features/
│   │   ├── system_info/         # MVP
│   │   ├── sensors/             # MVP
│   │   ├── battery/             # MVP (saúde) - teste descarga depois
│   │   ├── benchmark/
│   │   │   ├── cpu/
│   │   │   ├── memory/
│   │   │   ├── disk/            # MVP leve (B4.2: + saúde)
│   │   │   └── gpu/             # MVP leve (B4.3: + FPS simples)
│   │   └── performance/         # V1.1 (stubs vazios agora)
│   │       ├── ram_disk_diagnosis/
│   │       ├── cleaner/
│   │       └── updater/
│   └── platform/                # Method Channels nativos
│       ├── macos/               # Swift + IOKit
│       ├── windows/             # C++/WMI
│       ├── linux/               # /sys, nvme, dmidecode
│       └── android/             # Kotlin + BatteryManager
├── rust/                        # núcleo de benchmark (CPU/Memória)
└── packages/
    ├── macos/  (.dmg assinado + notarizado)
    ├── windows/ (.exe/.msix)
    ├── linux/  (.AppImage/.deb)
    └── android/ (.apk)
```

**Stack:** Flutter (UI) + Rust (benchmark core) + código nativo mínimo por plataforma (sensores/bateria).
**Princípio:** cada feature é uma pasta. Função nova = pasta nova, sem refatorar as antigas.

---

## 6. Roadmap de implementação

### Fase 0 — Fundação (semana 1)
- [ ] Projeto Flutter multi-plataforma
- [ ] Tema + detecção touch/desktop
- [ ] Navegação: Sistema | Sensores | Bateria | Benchmark
- [ ] Builds gerando os 4 pacotes

### Fase 1 — Núcleo de diagnóstico (semana 2)
- [ ] System Info (todas as plataformas)
- [ ] Sensores básicos (tempo real)
- [ ] Bateria — saúde (c. 4.1 §3)
- [ ] Storage breakdown somente leitura

### Fase 2 — Benchmark leve (semana 3)
- [ ] CPU single/multi-core
- [ ] Memória (GB/s + latência)
- [ ] Disco sequencial
- [ ] GPU: nome + FPS simples 10s
- [ ] Tela de resultado com score próprio (ex.: CPU Score, Mem Score)

### Fase 3 — MVP+ (semana 4, se Fase 2 rápida)
- [ ] RAM single/dual (informativo)
- [ ] Saúde SSD leitura básica
- [ ] Escaneador de temporários (somente leitura)
- [ ] Verificador de atualizações (somente listar)

### V1.1 — Performance Aid
- [ ] Diagnóstico completo RAM/Disco (SMART, TBW)
- [ ] Limpeza segura (whitelist + confirmação)
- [ ] Updater 1-clique com admin
- [ ] Teste de estresse térmico de GPU (Metal/Vulkan + proteção térmica)
- [ ] Teste de bateria com descarga real + relatório PDF/HTML

---

## 7. Riscos e limitações mapeadas

| Risco | Impacto | Mitigação |
|-------|---------|-----------|
| **macOS sandbox** (Apple Silicon limita sensores) | Sensores incompletos no Mac | Usar IOKit/sysctl, aceitar limitação, deixar a função degradar graciosamente |
| **Android/Play Store** restritivo p/ “limpeza” | Rejeição na loja | Distribuir via site/APK direto; MVP sem exclusão já resolve |
| **Cleaner apagar errado** | Quebra sistema | MVP só escaneia; V1.1 com whitelist + confirmação + restauração |
| **Updater sem admin** | Falha silenciosa | Permissão elevada com consentimento explícito |
| **GPU esquentar** | Throttling/dano percebido | Limite de tempo, parada automática por temperatura |
| **Scores não comparáveis** entre sistemas | Confusão de usuário | Motor em Rust + metodologia própria documentada, sem nomes de suítes de terceiros |

---

## 8. Critérios de sucesso do MVP

- [ ] Roda nos 4 sistemas a partir de 1 codebase
- [ ] Layout muda automaticamente em touchscreen
- [ ] Mostra System Info + sensores + bateria em < 2s
- [ ] Benchmark CPU/Memória/Disco/GPU executam e retornam score
- [ ] Nenhuma ação destrutiva (nada apaga, nada atualiza sozinho)

---

## 9. Próxima decisão

Posso começar a Fase 0 + Fase 1 agora (esqueleto + System Info/Sensores/Bateria). Ao final da Fase 2, a gente reavalia se adianta a Fase 3 ou se fecha o MVP para testes no seu MacBook antes de gerar os pacotes Windows/Linux/Android.

---

## 10. GPU Window 3D (pós-v2)

- Metal nativo no macOS + Vulkan nos demais OS
- Janela separada flutuante sobre o app, fechável sem fechar o app
- VSync desligado para medir FPS real da GPU
- Combobox Benchmark/Stress alterna o modo de carga na janela
- HUD dentro da janela 3D com 6 campos: GPU Name, %, Clock, V-RAM, Temperature, FPS
- Sem ações destrutivas: MVP continua só lendo/medindo, sem apagar ou atualizar nada

