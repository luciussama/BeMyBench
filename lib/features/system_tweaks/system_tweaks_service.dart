import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'system_tweaks_models.dart';

/// Serviço responsável pelos 3 pilares de Ajustes do Sistema:
/// 1. Atualização de pacotes (winget / apt / dnf / pacman)
/// 2. Varredura por drivers disponíveis (Windows Update / fwupd / ubuntu-drivers)
/// 3. Detecção e diagnóstico de hardware com driver ausente ou com problemas
class SystemTweaksService {
  final bool isWindows;
  final bool isLinux;

  SystemTweaksService({
    bool? isWindows,
    bool? isLinux,
  })  : isWindows = isWindows ?? Platform.isWindows,
        isLinux = isLinux ?? Platform.isLinux;

  bool get isSupported => isWindows || isLinux;

  String get detectedOsName {
    if (isWindows) return 'Windows';
    if (isLinux) return 'Linux';
    return Platform.operatingSystem;
  }

  // ===========================================================================
  // 1. PILAR 1: ATUALIZAÇÃO DE PACOTES
  // ===========================================================================

  /// Detecta qual gerenciador de pacotes está disponível no sistema.
  Future<String> detectPackageManager() async {
    if (isWindows) {
      try {
        final res = await Process.run('where', ['winget']);
        if (res.exitCode == 0) return 'winget (Windows Package Manager)';
      } catch (_) {}
      return 'Nenhum (winget não localizado)';
    }

    if (isLinux) {
      for (final pm in ['apt', 'apt-get', 'dnf', 'pacman', 'zypper']) {
        try {
          final res = await Process.run('which', [pm]);
          if (res.exitCode == 0) return pm;
        } catch (_) {}
      }
      return 'Nenhum gerenciador suportado localizado';
    }

    return 'Não suportado nesta plataforma';
  }

  /// Verifica se há pacotes disponíveis para atualização sem instalar.
  Future<List<PackageInfoItem>> checkPackageUpdates() async {
    if (!isSupported) return const [];

    if (isWindows) {
      return _checkWingetUpdates();
    }

    if (isLinux) {
      return _checkLinuxPackageUpdates();
    }

    return const [];
  }

  Future<List<PackageInfoItem>> _checkWingetUpdates() async {
    try {
      final res = await Process.run(
        'winget',
        ['upgrade', '--include-unknown'],
        runInShell: true,
      ).timeout(const Duration(seconds: 40));

      if (res.exitCode == 0 || res.exitCode == 1) {
        return parseWingetOutput(res.stdout.toString());
      }
    } catch (e) {
      debugPrint('Erro ao checar winget: $e');
    }
    return const [];
  }

  /// Parser público para winget upgrade, facilitando testes unitários isolados.
  static List<PackageInfoItem> parseWingetOutput(String stdout) {
    final items = <PackageInfoItem>[];
    final lines = stdout.split(RegExp(r'\r?\n'));
    bool tableStarted = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('---') || trimmed.contains('-------')) {
        tableStarted = true;
        continue;
      }

      if (!tableStarted) continue;

      // As linhas são formatadas em colunas: Nome, Id, Versão, Disponível, Origem
      final parts = trimmed.split(RegExp(r'\s{2,}'));
      if (parts.length >= 4) {
        items.add(PackageInfoItem(
          name: parts[0],
          id: parts.length > 4 ? parts[1] : parts[0],
          currentVersion: parts[parts.length - 3],
          availableVersion: parts[parts.length - 2],
          source: parts.last,
        ));
      }
    }
    return items;
  }

  Future<List<PackageInfoItem>> _checkLinuxPackageUpdates() async {
    final pm = await detectPackageManager();
    if (pm.contains('apt')) {
      try {
        final res = await Process.run('apt', ['list', '--upgradable'])
            .timeout(const Duration(seconds: 25));
        if (res.exitCode == 0) {
          return parseAptListOutput(res.stdout.toString());
        }
      } catch (_) {}
    }
    return const [];
  }

  /// Parser público de `apt list --upgradable` para testes
  static List<PackageInfoItem> parseAptListOutput(String stdout) {
    final items = <PackageInfoItem>[];
    final lines = stdout.split(RegExp(r'\r?\n'));

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('Listing...')) continue;

      // Exemplo: libssl3/jammy-updates 3.0.2-0ubuntu1.18 amd64 [upgradable from: 3.0.2-0ubuntu1.17]
      final match = RegExp(r'^([^/]+)/[^\s]+\s+([^\s]+)\s+[^\s]+\s+\[upgradable from:\s+([^\]]+)\]')
          .firstMatch(trimmed);
      if (match != null) {
        items.add(PackageInfoItem(
          name: match.group(1)!,
          id: match.group(1)!,
          availableVersion: match.group(2)!,
          currentVersion: match.group(3)!,
          source: 'APT Repository',
        ));
      }
    }
    return items;
  }

  /// Executa o processo de atualização de pacotes com feedback visual linha a linha.
  Future<bool> runPackageUpgrade({
    required void Function(String line) onProgress,
  }) async {
    if (!isSupported) {
      onProgress('Operação não suportada nesta plataforma.');
      return false;
    }

    if (isWindows) {
      onProgress('Iniciando Windows Package Manager (winget)...\n');
      try {
        final process = await Process.start(
          'winget',
          [
            'upgrade',
            '--all',
            '--include-unknown',
            '--accept-package-agreements',
            '--accept-source-agreements',
          ],
          runInShell: true,
        );

        process.stdout.transform(utf8.decoder).listen((data) {
          for (final line in data.split(RegExp(r'\r?\n'))) {
            if (line.isNotEmpty) onProgress(line);
          }
        });

        process.stderr.transform(utf8.decoder).listen((data) {
          for (final line in data.split(RegExp(r'\r?\n'))) {
            if (line.isNotEmpty) onProgress('[ERRO] $line');
          }
        });

        final exitCode = await process.exitCode;
        if (exitCode == 0) {
          onProgress('\n✓ Todos os pacotes disponíveis foram atualizados com sucesso!');
          return true;
        } else {
          onProgress('\nProcesso finalizado com código: $exitCode');
          return exitCode == 0;
        }
      } catch (e) {
        onProgress('\nFalha ao executar winget: $e');
        return false;
      }
    }

    if (isLinux) {
      final pm = await detectPackageManager();
      onProgress('Gerenciador de pacotes detectado: $pm');
      onProgress('Solicitando elevação de privilégios via interface gráfica do sistema (Polkit)...\n');

      try {
        // Usa pkexec para solicitar senha em janela gráfica nativa do sistema operacional
        // sem abrir janela de terminal preto/CLI.
        final command = pm.contains('apt')
            ? 'apt update && apt upgrade -y'
            : pm.contains('dnf')
                ? 'dnf upgrade -y'
                : 'pacman -Syu --noconfirm';

        final process = await Process.start(
          'pkexec',
          ['sh', '-c', command],
          runInShell: false,
        );

        process.stdout.transform(utf8.decoder).listen((data) {
          for (final line in data.split(RegExp(r'\r?\n'))) {
            if (line.isNotEmpty) onProgress(line);
          }
        });

        process.stderr.transform(utf8.decoder).listen((data) {
          for (final line in data.split(RegExp(r'\r?\n'))) {
            if (line.isNotEmpty) onProgress('[AVISO] $line');
          }
        });

        final exitCode = await process.exitCode;
        if (exitCode == 0) {
          onProgress('\n✓ Atualização concluída com sucesso!');
          return true;
        } else {
          onProgress('\nProcesso finalizado (código: $exitCode). Autenticação cancelada ou erro.');
          return false;
        }
      } catch (e) {
        onProgress('\nFalha ao iniciar processo de atualização: $e');
        return false;
      }
    }

    return false;
  }

  // ===========================================================================
  // 2. PILAR 2: VASCULHAR POR ATUALIZAÇÃO DE DRIVER
  // ===========================================================================

  /// Varredura por drivers atualizados para os dispositivos do sistema.
  Future<List<DriverUpdateItem>> scanDriverUpdates() async {
    if (!isSupported) return const [];

    if (isWindows) {
      return _scanWindowsDriverUpdates();
    }

    if (isLinux) {
      return _scanLinuxDriverUpdates();
    }

    return const [];
  }

  Future<List<DriverUpdateItem>> _scanWindowsDriverUpdates() async {
    const psScript = r'''
try {
    $Session = New-Object -ComObject Microsoft.Update.Session
    $Searcher = $Session.CreateUpdateSearcher()
    $Results = $Searcher.Search("IsInstalled=0 and Type='Driver'")
    $Drivers = @()
    foreach ($Update in $Results.Updates) {
        $Drivers += [PSCustomObject]@{
            deviceName = $Update.Title
            currentVersion = "Instalado"
            availableVersion = if ($Update.DriverVerDate) { $Update.DriverVerDate.ToString("yyyy-MM-dd") } else { "Disponível no Windows Update" }
            releaseDate = if ($Update.DriverVerDate) { $Update.DriverVerDate.ToString("yyyy-MM-dd") } else { $null }
            manufacturer = if ($Update.DriverManufacturer) { $Update.DriverManufacturer } else { "Microsoft Update" }
            provider = if ($Update.DriverProviderName) { $Update.DriverProviderName } else { "Windows Update" }
            isFirmware = ($Update.Title -match "Firmware|BIOS|System")
        }
    }
    $Drivers | ConvertTo-Json -Compress
} catch {
    Write-Output "[]"
}
''';

    try {
      final res = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', psScript],
      ).timeout(const Duration(seconds: 35));

      if (res.exitCode == 0) {
        return parseWindowsDriversJson(res.stdout.toString().trim());
      }
    } catch (e) {
      debugPrint('Erro ao buscar drivers no Windows: $e');
    }
    return const [];
  }

  /// Parser público do JSON de drivers do Windows Update
  static List<DriverUpdateItem> parseWindowsDriversJson(String jsonStr) {
    if (jsonStr.isEmpty || jsonStr == '[]') return const [];
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        return decoded
            .map((item) => DriverUpdateItem.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      } else if (decoded is Map) {
        return [DriverUpdateItem.fromJson(Map<String, dynamic>.from(decoded))];
      }
    } catch (_) {}
    return const [];
  }

  Future<List<DriverUpdateItem>> _scanLinuxDriverUpdates() async {
    final list = <DriverUpdateItem>[];

    // 1. fwupdmgr (Linux Vendor Firmware Service)
    try {
      final res = await Process.run(
        'fwupdmgr',
        ['get-updates', '--json'],
      ).timeout(const Duration(seconds: 20));

      if (res.exitCode == 0) {
        list.addAll(parseFwupdJson(res.stdout.toString()));
      }
    } catch (_) {}

    // 2. ubuntu-drivers
    try {
      final res = await Process.run(
        'ubuntu-drivers',
        ['devices'],
      ).timeout(const Duration(seconds: 15));

      if (res.exitCode == 0) {
        list.addAll(parseUbuntuDriversOutput(res.stdout.toString()));
      }
    } catch (_) {}

    return list;
  }

  /// Parser público para `fwupdmgr get-updates --json`
  static List<DriverUpdateItem> parseFwupdJson(String jsonStr) {
    final items = <DriverUpdateItem>[];
    try {
      final decoded = jsonDecode(jsonStr);
      final devices = decoded['Devices'] as List? ?? [];
      for (final dev in devices) {
        final name = dev['Name'] as String? ?? 'Dispositivo de Hardware';
        final vendor = dev['Vendor'] as String? ?? 'Fabricante';
        final releases = dev['Releases'] as List? ?? [];
        if (releases.isNotEmpty) {
          final latest = releases.first as Map;
          items.add(DriverUpdateItem(
            deviceName: name,
            currentVersion: dev['Version'] as String? ?? 'N/D',
            availableVersion: latest['Version'] as String? ?? 'Nova versão',
            releaseDate: latest['Created'] != null ? '${latest['Created']}' : null,
            manufacturer: vendor,
            provider: 'Linux Vendor Firmware Service (LVFS)',
            isFirmware: true,
          ));
        }
      }
    } catch (_) {}
    return items;
  }

  /// Parser público para `ubuntu-drivers devices`
  static List<DriverUpdateItem> parseUbuntuDriversOutput(String stdout) {
    final items = <DriverUpdateItem>[];
    final lines = stdout.split(RegExp(r'\r?\n'));
    String currentModel = '';
    String vendor = 'Hardware Vendor';

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('model')) {
        final parts = trimmed.split(':');
        if (parts.length > 1) currentModel = parts[1].trim();
      } else if (trimmed.startsWith('vendor')) {
        final parts = trimmed.split(':');
        if (parts.length > 1) vendor = parts[1].trim();
      } else if (trimmed.startsWith('driver') && trimmed.contains('recommended')) {
        final driverName = trimmed.split(':').last.replaceAll('- recommended', '').trim();
        items.add(DriverUpdateItem(
          deviceName: currentModel.isNotEmpty ? currentModel : 'Controlador Gráfico/Rede',
          currentVersion: 'Genérico/Open-source',
          availableVersion: driverName,
          manufacturer: vendor,
          provider: 'Repositório de Drivers da Distribuição',
          isFirmware: false,
        ));
      }
    }
    return items;
  }

  // ===========================================================================
  // 3. PILAR 3: HARDWARE COM DRIVER NÃO LOCALIZADO OU COM PROBLEMAS
  // ===========================================================================

  /// Varredura e listagem de dispositivos com driver ausente (ex: código 28)
  /// ou problemas operacionais reportados pelo sistema.
  Future<List<ProblematicHardwareItem>> scanProblematicHardware() async {
    if (!isSupported) return const [];

    if (isWindows) {
      return _scanWindowsProblematicHardware();
    }

    if (isLinux) {
      return _scanLinuxProblematicHardware();
    }

    return const [];
  }

  Future<List<ProblematicHardwareItem>> _scanWindowsProblematicHardware() async {
    const psScript = r'''
try {
    $Problems = Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 }
    $List = @()
    foreach ($Dev in $Problems) {
        $List += [PSCustomObject]@{
            name = if ($Dev.Name) { $Dev.Name } else { "Dispositivo Desconhecido" }
            deviceId = if ($Dev.DeviceID) { $Dev.DeviceID } else { "" }
            hardwareClass = if ($Dev.PNPClass) { $Dev.PNPClass } else { "Hardware" }
            errorCode = [int]$Dev.ConfigManagerErrorCode
        }
    }
    $List | ConvertTo-Json -Compress
} catch {
    Write-Output "[]"
}
''';

    try {
      final res = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', psScript],
      ).timeout(const Duration(seconds: 30));

      if (res.exitCode == 0) {
        return parseWindowsProblemsJson(res.stdout.toString().trim());
      }
    } catch (e) {
      debugPrint('Erro ao consultar Win32_PnPEntity: $e');
    }
    return const [];
  }

  /// Parser público do JSON de dispositivos problemáticos do Windows
  static List<ProblematicHardwareItem> parseWindowsProblemsJson(String jsonStr) {
    if (jsonStr.isEmpty || jsonStr == '[]') return const [];
    try {
      final decoded = jsonDecode(jsonStr);
      final rawList = decoded is List ? decoded : [decoded];
      return rawList.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return ProblematicHardwareItem.fromWindowsPnp(
          name: map['name'] as String? ?? 'Dispositivo Desconhecido',
          deviceId: map['deviceId'] as String? ?? '',
          hardwareClass: map['hardwareClass'] as String? ?? 'Hardware',
          errorCode: map['errorCode'] as int? ?? 1,
        );
      }).toList();
    } catch (_) {}
    return const [];
  }

  Future<List<ProblematicHardwareItem>> _scanLinuxProblematicHardware() async {
    final list = <ProblematicHardwareItem>[];

    // 1. Inspeciona lspci -nnk procurando dispositivos PCI sem driver ativo
    try {
      final res = await Process.run('lspci', ['-nnk']).timeout(const Duration(seconds: 15));
      if (res.exitCode == 0) {
        list.addAll(parseLspciOutput(res.stdout.toString()));
      }
    } catch (_) {}

    // 2. Inspeciona dmesg para falhas de firmware
    try {
      final res = await Process.run('dmesg', ['-l', 'err,warn'])
          .timeout(const Duration(seconds: 10));
      if (res.exitCode == 0) {
        list.addAll(parseDmesgOutput(res.stdout.toString()));
      }
    } catch (_) {}

    return list;
  }

  /// Parser público de `lspci -nnk` para dispositivos sem driver de kernel ativo
  static List<ProblematicHardwareItem> parseLspciOutput(String stdout) {
    final items = <ProblematicHardwareItem>[];
    final blocks = stdout.split(RegExp(r'\n(?=[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.)'));

    for (final block in blocks) {
      final trimmed = block.trim();
      if (trimmed.isEmpty) continue;

      final lines = trimmed.split('\n');
      final firstLine = lines.first.trim();

      // Dispositivos que não necessitam de driver (ex: pontes PCI host bridge, ISA bridge) são filtrados
      final isBridge = firstLine.toLowerCase().contains('host bridge') ||
          firstLine.toLowerCase().contains('isa bridge') ||
          firstLine.toLowerCase().contains('pci bridge');

      final hasDriverInUse = lines.any((l) => l.trim().startsWith('Kernel driver in use:'));

      if (!hasDriverInUse && !isBridge) {
        // Encontrou hardware sem driver de kernel gerenciando
        final deviceIdMatch = RegExp(r'^([0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F])\s+(.*)$')
            .firstMatch(firstLine);

        final deviceId = deviceIdMatch?.group(1) ?? 'PCI Device';
        final fullName = deviceIdMatch?.group(2) ?? firstLine;

        items.add(ProblematicHardwareItem.fromLinux(
          name: fullName,
          deviceId: deviceId,
          hardwareClass: 'Controlador PCI',
          hasMissingFirmware: false,
        ));
      }
    }
    return items;
  }

  /// Parser público de `dmesg` para identificar falhas de carregamento de firmware
  static List<ProblematicHardwareItem> parseDmesgOutput(String stdout) {
    final items = <ProblematicHardwareItem>[];
    final lines = stdout.split(RegExp(r'\r?\n'));

    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.contains('failed to load') && lower.contains('firmware')) {
        items.add(ProblematicHardwareItem.fromLinux(
          name: 'Módulo de Hardware com Firmware Ausente',
          deviceId: 'Kernel Subsystem',
          hardwareClass: 'Firmware',
          hasMissingFirmware: true,
          details: line.trim(),
        ));
      }
    }
    return items;
  }

  // ===========================================================================
  // RELATÓRIO COMPLETO CONSOLIDADO
  // ===========================================================================

  Future<SystemTweaksScanReport> fullDiagnosticsScan() async {
    final stopwatch = Stopwatch()..start();

    final pmName = await detectPackageManager();
    final packages = await checkPackageUpdates();
    final drivers = await scanDriverUpdates();
    final problems = await scanProblematicHardware();

    stopwatch.stop();

    return SystemTweaksScanReport(
      timestamp: DateTime.now(),
      osName: detectedOsName,
      packageManagerName: pmName,
      isPackageManagerAvailable: !pmName.startsWith('Nenhum') && !pmName.startsWith('Não suportado'),
      availablePackages: packages,
      availableDrivers: drivers,
      problematicHardware: problems,
      scanDurationMs: stopwatch.elapsedMilliseconds,
    );
  }
}
