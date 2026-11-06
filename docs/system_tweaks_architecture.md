# Arquitetura e Especificação Técnica: Ajustes do Sistema (BMyBench)

**Status:** Implementado, Validado e Integrado na Release v1.0  
**Branch:** `main` (Merge da `iter/v5`)  
**Escopo:** Três pilares operacionais de manutenção de sistema:
1. Atualização de pacotes do sistema operacional
2. Varredura por atualizações de drivers de hardware
3. Diagnóstico e exibição de dispositivos de hardware com erro ou ausência de driver

---

## 1. Diretriz Mandatória de UX (Regra de Omissão Silenciosa)

- **Sem Disclaimers:** É estritamente proibido exibir avisos ou placeholders educativos como *"Aviso: Android não suporta gerenciador de hardware"*.
- **Omissão Completa:** Se uma plataforma não for compatível com um determinado pilar ou recurso, o botão, card ou seção correspondente **simplesmente não existe** no layout.
- **Detecção de Capacidade (`PlatformDetector.supportsSystemTweaks`):**
  - **Ambientes Desktop (Windows, Linux, macOS):** A aba "Ajustes" é exibida no menu superior. Os botões internos respeitam a disponibilidade de cada ferramenta (ex: se o Homebrew não estiver instalado no Mac, o botão de atualizar pacotes é omitido sem disclaimer).
  - **Ambientes Mobile (Android / iOS / Web):** A aba inteira é omitida da interface silenciosamente.

---

## 2. Pilar 1: Atualização de Pacotes

### 2.1. Windows
- **Comando Primário:** `winget upgrade --all --include-unknown --accept-package-agreements --accept-source-agreements`
- **Verificação de Disponibilidade:**
  ```powershell
  where winget
  ```
- **Listagem Prévia:** `winget upgrade --include-unknown`
- **Execução e Privilégios:** Executado via streaming em modal visual (`PackageUpdaterModal`) com log e barra de progresso.

### 2.2. Linux
- **Detecção de Gerenciador:** Detecção dinâmica entre `apt`, `apt-get`, `dnf`, `pacman` e `zypper`.
- **Listagem Prévia (Sem privilégios de root):**
  - APT: `apt list --upgradable`
- **Execução com Elevação Gráfica (Polkit):**
  - Execução via `pkexec sh -c 'apt update && apt upgrade -y'`, invocando a caixa de diálogo nativa de autenticação gráfica do sistema operacional sem abrir terminais CLI pretos.

### 2.3. macOS
- **Detecção de Gerenciador:** Verificação de `/opt/homebrew/bin/brew` ou `/usr/local/bin/brew`.
- **Listagem Prévia:** `brew outdated --verbose`
- **Execução:** `brew upgrade` via streaming no modal visual.
- **Omissão:** Se o Homebrew não estiver instalado na máquina, a seção de pacotes é omitida silenciosamente.

---

## 3. Pilar 2: Varredura por Atualização de Drivers

### 3.1. Windows
- **Mecanismo Primário (Windows Update Agent COM Object):**
  ```powershell
  $Session = New-Object -ComObject Microsoft.Update.Session
  $Searcher = $Session.CreateUpdateSearcher()
  $Results = $Searcher.Search("IsInstalled=0 and Type='Driver'")
  $Results.Updates | Select-Object Title, Description, DriverModel, DriverManufacturer, DriverVerDate | ConvertTo-Json
  ```
- **Reescaneamento de Barramento:** `pnputil /scan-devices`

### 3.2. Linux
- **Mecanismo Primário: LVFS / `fwupd` (Firmware de Fabricantes):**
  ```bash
  fwupdmgr refresh && fwupdmgr get-updates --json
  ```
- **Mecanismo Secundário: `ubuntu-drivers` (para GPUs e chipsets proprietários):**
  ```bash
  ubuntu-drivers devices
  ```
  O parser extrai o identificador limpo do driver (ex: `nvidia-driver-535`).

### 3.3. macOS
- **Mecanismo Oficial da Apple:** Consulta a atualizações de hardware e firmware via `softwareupdate -l`.

---

## 4. Pilar 3: Hardware com Driver com Problema ou Não Localizado

### 4.1. Windows
- **Consulta WMI / CIM (`Win32_PnPEntity`):**
  Dispositivos PnP com falha ou driver ausente possuem código de erro diferente de 0 (`ConfigManagerErrorCode != 0`):
  ```powershell
  Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | Select-Object Name, DeviceID, PNPClass, ConfigManagerErrorCode | ConvertTo-Json
  ```
- **Mapeamento de Códigos de Erro para Linguagem Leiga:**
  - **Código 28 (`CM_PROB_FAILED_INSTALL`):** "Driver Não Instalado (Código 28)" — Alerta laranja com orientação de busca.
  - **Código 10 (`CM_PROB_FAILED_START`):** "Falha ao Iniciar Dispositivo (Código 10)" — Alerta vermelho.
  - **Código 43 (`CM_PROB_FAILED_POST_START`):** "Dispositivo Interrompido por Falha (Código 43)".
  - **Código 14 (`CM_PROB_NEED_RESTART`):** "Reinicialização Necessária (Código 14)".
  - **Código 1 (`CM_PROB_NOT_CONFIGURED`):** "Dispositivo Não Configurado (Código 1)".

### 4.2. Linux
- **Detecção de Dispositivos PCI sem Driver:**
  - Varredura de `lspci -nnk`: dispositivos sem a diretiva `Kernel driver in use:` são catalogados como hardware sem driver ativo.
- **Detecção de Erros de Firmware no Kernel:**
  - Varredura em `dmesg -l err,warn` para capturar falhas como `firmware: failed to load` ou `Direct firmware load failed`.

### 4.3. macOS
- **Diagnóstico Nativo:** Validação de integridade dos barramentos (Thunderbolt, USB4, GPU, Neural Engine, Wi-Fi, Áudio) via kernel Darwin.

---

## 5. Estrutura de Arquivos Implementada

```
lib/features/system_tweaks/
├── system_tweaks_models.dart      # Modelos: PackageInfoItem, DriverUpdateItem, ProblematicHardwareItem, SystemTweaksScanReport
├── system_tweaks_service.dart     # Coletor e orquestrador multi-plataforma (Windows, Linux e macOS)
├── system_tweaks_screen.dart      # Tela visual da aba Ajustes com os 3 pilares estruturados
└── widgets/
    └── package_updater_modal.dart # Modal interativo com progresso, log estilizado e sem terminais
```
