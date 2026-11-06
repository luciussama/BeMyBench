# Arquitetura e Especificação Técnica: Ajustes do Sistema (BMyBench)

**Status:** Especificado e Documentado  
**Branch:** `iter/v5`  
**Escopo:** Três pilares operacionais de manutenção de sistema:
1. Atualização de pacotes do sistema operacional
2. Varredura por atualizações de drivers de hardware
3. Diagnóstico e exibição de dispositivos de hardware com erro ou ausência de driver

---

## 1. Diretriz Mandatória de UX (Regra de Omissão Silenciosa)

- **Sem Disclaimers:** É estritamente proibido exibir avisos ou placeholders educativos como *"Aviso: Android/macOS não suporta gerenciador de hardware"*.
- **Omissão Completa:** Se uma plataforma não for compatível com um determinado pilar, o botão, card ou seção correspondente **simplesmente não existe** no layout.
- **Detecção de Capacidade (`PlatformCapabilities`):**
  - Windows: Suporta Pilar 1 (se `winget` estiver instalado), Pilar 2 (Windows Update/PnP) e Pilar 3 (WMI/PnP).
  - Linux: Suporta Pilar 1 (se gerenciador compatível for detectado), Pilar 2 (se `fwupd` ou `ubuntu-drivers` estiverem presentes) e Pilar 3 (`lspci`/`dmesg`).
  - macOS / Android / Web / iOS: Omitidos silenciosamente nos três pilares.

---

## 2. Pilar 1: Atualização de Pacotes

### 2.1. Windows
- **Comando Primário:** `winget upgrade --all --include-unknown --accept-package-agreements --accept-source-agreements`
- **Verificação de Disponibilidade:**
  ```powershell
  Get-Command winget -ErrorAction SilentlyContinue
  ```
- **Listagem de Atualizações Disponíveis (Check/Dry-Run):**
  ```cmd
  winget upgrade
  ```
  Retorna tabela com Nome, Id, Versão Atual, Versão Disponível e Origem.
- **Execução e Privilégios:**
  - `winget` pode necessitar de privilégios elevados (UAC) para certos instaladores `.exe`/`.msi`.
  - Estratégia de execução: Executar via `Process.start` transmitindo stream de saída (stdout/stderr) para feedback visual em modal com barra de rolagem e botão de fechar ao concluir.

### 2.2. Linux
- **Detecção de Gerenciador:**
  - Debian/Ubuntu: `which apt` / `which apt-get`
  - Fedora/RHEL: `which dnf`
  - Arch Linux: `which pacman`
  - openSUSE: `which zypper`
- **Listagem Prévia (Sem privilégios de root):**
  - APT: `apt list --upgradable`
  - DNF: `dnf check-update` (código de saída 100 indica updates pendentes)
  - Pacman: `checkupdates` ou `pacman -Qu`
- **Execução com Elevação de Privilégios:**
  - No Linux, `apt upgrade` exige root.
  - Estratégia de elevação:
    1. Se ambiente gráfico com Polkit disponível: `pkexec apt update && pkexec apt upgrade -y` (exibe prompt nativo do sistema para senha).
    2. Fallback de terminal interativo: Abrir em emulador de terminal gráfico do usuário (`x-terminal-emulator`, `gnome-terminal`, `konsole`, `xterm`) executando o comando de atualização.

---

## 3. Pilar 2: Varredura por Atualização de Drivers

### 3.1. Windows
- **Mecanismo Primário (Windows Update API - COM Object):**
  O Windows não possui um comando CLI no Device Manager para checar driver sem abrir o assistente GUI, porém a API nativa do Windows Update Agent (`Microsoft.Update.Session`) permite varredura assíncrona filtrando por drivers:
  ```powershell
  $Session = New-Object -ComObject Microsoft.Update.Session
  $Searcher = $Session.CreateUpdateSearcher()
  $Results = $Searcher.Search("IsInstalled=0 and Type='Driver'")
  $Results.Updates | Select-Object Title, Description, DriverModel, DriverManufacturer, DriverVerDate | ConvertTo-Json
  ```
- **Mecanismo PnP (Varredura de barramento):**
  - `pnputil /scan-devices`: Força o Windows a reescanear todo o barramento PnP em busca de novos dispositivos ou alterações de hardware.

### 3.2. Linux
- **Mecanismo Primário: LVFS / `fwupd` (Firmware de Fabricantes):**
  - Utilitário universal para atualização de firmware de hardware (UEFI, NVMe, controladoras, docks, GPUs):
    ```bash
    fwupdmgr refresh && fwupdmgr get-updates --json
    ```
    Retorna dispositivos com firmware novo disponível no Linux Vendor Firmware Service.
- **Mecanismo Secundário: `ubuntu-drivers` (para GPUs e chipsets proprietários):**
  - `ubuntu-drivers devices` ou `ubuntu-drivers list`:
    Identifica se placas de vídeo (ex: NVIDIA) ou interfaces de rede têm drivers proprietários recomendados mais recentes nos repositórios APT.

---

## 4. Pilar 3: Hardware com Driver com Problema ou Não Localizado

### 4.1. Windows
- **Consulta WMI / CIM (`Win32_PnPEntity`):**
  Dispositivos PnP com falha ou driver ausente possuem código de erro diferente de 0 (`ConfigManagerErrorCode != 0`):
  ```powershell
  Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | Select-Object Name, DeviceID, Manufacturer, ConfigManagerErrorCode, Status | ConvertTo-Json
  ```
- **Tabela de Códigos de Erro Relevantes do Windows Device Manager:**
  - **Código 28 (`CM_PROB_FAILED_INSTALL`):** "Os drivers para este dispositivo não estão instalados" (Ponto de exclamação amarelo / driver ausente).
  - **Código 10 (`CM_PROB_FAILED_START`):** "O dispositivo não pode ser iniciado" (Falha no driver ou incompatibilidade).
  - **Código 43 (`CM_PROB_FAILED_POST_START`):** "O Windows interrompeu este dispositivo porque encontrou problemas".
  - **Código 1 (`CM_PROB_NOT_CONFIGURED`):** Dispositivo não configurado.
  - **Código 14 (`CM_PROB_NEED_RESTART`):** O dispositivo requer reinicialização para funcionar.
  - **Código 22 (`CM_PROB_DISABLED`):** Dispositivo desativado pelo usuário/sistema.
- **Mecanismo PnP Alternativo:**
  - `pnputil /enum-devices /problem /deviceids`

### 4.2. Linux
- **Detecção de Dispositivos PCI sem Driver:**
  - Comando: `lspci -nnk`
  - Parser: Cada dispositivo PCI possui seu identificador e classe. Se o bloco do dispositivo não contiver a linha `Kernel driver in use:`, significa que o kernel reconhece o hardware mas **nenhum driver/módulo está ativo para ele**:
    ```
    02:00.0 Network controller [0280]: Broadcom Inc. and subsidiaries BCM4360 [14e4:43a0] (rev 03)
        Subsystem: Apple Inc. AirPort Extreme [106b:0117]
        Kernel modules: bcma, wl
        # Note: falta "Kernel driver in use:" -> driver ausente!
    ```
- **Detecção de Erros de Firmware no Kernel:**
  - Comando: `dmesg -l err,warn --time-format iso | grep -iE "firmware.*failed|failed to load|missing firmware"`
  - Captura mensagens de periféricos que tentaram inicializar mas falharam por falta de blob de firmware em `/lib/firmware`.

---

## 5. Estrutura de Código Proposta no Flutter

```
lib/features/system_tweaks/
├── system_tweaks_models.dart      # Modelos: PackageUpdateItem, DriverUpdateItem, ProblematicDeviceItem
├── system_tweaks_service.dart     # Coletor e orquestrador multi-plataforma (Windows e Linux)
├── widgets/
│   ├── package_updater_modal.dart # Diálogo com log e progresso de atualização
│   ├── driver_updates_panel.dart  # Lista de drivers disponíveis para atualização
│   └── problematic_devices_card.dart # Card com badges vermelhas/amarelas para hardware com falha
```
