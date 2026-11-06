library system_tweaks_models;

/// Modelos de dados para o módulo de Ajustes do Sistema (System Tweaks).
/// Cobre os três pilares:
/// 1. Atualização de pacotes (winget / apt / dnf / pacman)
/// 2. Varredura por drivers disponíveis
/// 3. Detecção e diagnóstico de hardware com driver ausente ou com problemas

enum PackageUpdateStage {
  idle,
  checking,
  updating,
  completed,
  failed,
  noUpdates,
}

/// Item de pacote disponível para atualização
class PackageInfoItem {
  final String name;
  final String id;
  final String currentVersion;
  final String availableVersion;
  final String source;

  const PackageInfoItem({
    required this.name,
    required this.id,
    required this.currentVersion,
    required this.availableVersion,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'id': id,
        'currentVersion': currentVersion,
        'availableVersion': availableVersion,
        'source': source,
      };

  factory PackageInfoItem.fromJson(Map<String, dynamic> json) => PackageInfoItem(
        name: json['name'] as String? ?? 'Desconhecido',
        id: json['id'] as String? ?? '',
        currentVersion: json['currentVersion'] as String? ?? 'N/D',
        availableVersion: json['availableVersion'] as String? ?? 'N/D',
        source: json['source'] as String? ?? 'Repositório',
      );
}

/// Item de driver disponível para atualização (Windows Update / fwupd / ubuntu-drivers)
class DriverUpdateItem {
  final String deviceName;
  final String currentVersion;
  final String availableVersion;
  final String? releaseDate;
  final String manufacturer;
  final String provider;
  final bool isFirmware;

  const DriverUpdateItem({
    required this.deviceName,
    required this.currentVersion,
    required this.availableVersion,
    this.releaseDate,
    required this.manufacturer,
    required this.provider,
    this.isFirmware = false,
  });

  Map<String, dynamic> toJson() => {
        'deviceName': deviceName,
        'currentVersion': currentVersion,
        'availableVersion': availableVersion,
        'releaseDate': releaseDate,
        'manufacturer': manufacturer,
        'provider': provider,
        'isFirmware': isFirmware,
      };

  factory DriverUpdateItem.fromJson(Map<String, dynamic> json) => DriverUpdateItem(
        deviceName: json['deviceName'] as String? ?? 'Dispositivo Desconhecido',
        currentVersion: json['currentVersion'] as String? ?? 'N/D',
        availableVersion: json['availableVersion'] as String? ?? 'N/D',
        releaseDate: json['releaseDate'] as String?,
        manufacturer: json['manufacturer'] as String? ?? 'Fabricante Desconhecido',
        provider: json['provider'] as String? ?? 'Sistema',
        isFirmware: json['isFirmware'] as bool? ?? false,
      );
}

/// Severidade do problema de hardware
enum HardwareProblemSeverity {
  missingDriver, // Amarelo/Laranja: Sem driver instalado (Código 28 no Windows ou sem driver de kernel no Linux)
  deviceFailed,  // Vermelho: Falha de hardware/driver (Código 10, 43, etc.)
  needsRestart,  // Azul: Requer reinicialização do sistema (Código 14)
  configuration, // Cinza/Laranja: Dispositivo não configurado ou com conflito
}

/// Dispositivo de hardware com driver não localizado ou com falha
class ProblematicHardwareItem {
  final String name;
  final String deviceId;
  final String hardwareClass;
  final int errorCode;
  final String errorTitle;
  final String errorDescription;
  final String suggestedAction;
  final HardwareProblemSeverity severity;

  const ProblematicHardwareItem({
    required this.name,
    required this.deviceId,
    required this.hardwareClass,
    required this.errorCode,
    required this.errorTitle,
    required this.errorDescription,
    required this.suggestedAction,
    required this.severity,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'deviceId': deviceId,
        'hardwareClass': hardwareClass,
        'errorCode': errorCode,
        'errorTitle': errorTitle,
        'errorDescription': errorDescription,
        'suggestedAction': suggestedAction,
        'severity': severity.name,
      };

  /// Converte códigos de erro do Gerenciador de Dispositivos do Windows (Win32_PnPEntity.ConfigManagerErrorCode)
  /// para explicações legíveis e amigáveis para usuários leigos.
  static ProblematicHardwareItem fromWindowsPnp({
    required String name,
    required String deviceId,
    required String hardwareClass,
    required int errorCode,
  }) {
    String title;
    String description;
    String action;
    HardwareProblemSeverity severity;

    switch (errorCode) {
      case 28:
        title = 'Driver Não Instalado (Código 28)';
        description = 'O sistema reconheceu o dispositivo conectado, mas não localizou um driver compatível instalado.';
        action = 'Utilize a busca de drivers ou baixe o driver oficial no site do fabricante do equipamento.';
        severity = HardwareProblemSeverity.missingDriver;
        break;
      case 10:
        title = 'Falha ao Iniciar Dispositivo (Código 10)';
        description = 'O driver foi localizado, mas o dispositivo não pôde ser inicializado devido a incompatibilidade ou firmware desatualizado.';
        action = 'Reinstale o driver mais recente ou atualize o firmware/BIOS da placa-mãe.';
        severity = HardwareProblemSeverity.deviceFailed;
        break;
      case 43:
        title = 'Dispositivo Interrompido por Falha (Código 43)';
        description = 'O Windows interrompeu a operação deste dispositivo porque o hardware reportou um erro interno ou instabilidade.';
        action = 'Desconecte e reconecte o periférico, ou execute uma atualização limpa do driver.';
        severity = HardwareProblemSeverity.deviceFailed;
        break;
      case 14:
        title = 'Reinicialização Necessária (Código 14)';
        description = 'Este dispositivo só funcionará corretamente após a reinicialização do computador.';
        action = 'Reinicie o sistema operacional para concluir a configuração do hardware.';
        severity = HardwareProblemSeverity.needsRestart;
        break;
      case 1:
        title = 'Dispositivo Não Configurado (Código 1)';
        description = 'O hardware ainda não foi configurado pelo sistema operacional.';
        action = 'Clique em verificar drivers para permitir que o sistema atribua a configuração correta.';
        severity = HardwareProblemSeverity.configuration;
        break;
      case 18:
        title = 'Reinstalação Necessária (Código 18)';
        description = 'Os drivers deste dispositivo precisam ser reinstalados.';
        action = 'Reinstale o pacote de suporte de hardware fornecido pelo fabricante.';
        severity = HardwareProblemSeverity.missingDriver;
        break;
      case 31:
        title = 'Dispositivo Não Está Funcionando (Código 31)';
        description = 'O sistema não conseguiu carregar os drivers necessários para este dispositivo.';
        action = 'Atualize o driver do dispositivo através dos repositórios oficiais.';
        severity = HardwareProblemSeverity.deviceFailed;
        break;
      default:
        title = 'Erro de Hardware/Driver (Código $errorCode)';
        description = 'O dispositivo reportou uma condição anormal de operação ao gerenciador de hardware.';
        action = 'Consulte o suporte do fabricante ou verifique atualizações de sistema disponíveis.';
        severity = HardwareProblemSeverity.deviceFailed;
        break;
    }

    return ProblematicHardwareItem(
      name: name.isEmpty ? 'Dispositivo Desconhecido' : name,
      deviceId: deviceId,
      hardwareClass: hardwareClass.isEmpty ? 'Hardware Geral' : hardwareClass,
      errorCode: errorCode,
      errorTitle: title,
      errorDescription: description,
      suggestedAction: action,
      severity: severity,
    );
  }

  /// Converte ocorrência Linux (dispositivo PCI/USB sem driver ativo ou falha em dmesg)
  static ProblematicHardwareItem fromLinux({
    required String name,
    required String deviceId,
    required String hardwareClass,
    required bool hasMissingFirmware,
    String? details,
  }) {
    if (hasMissingFirmware) {
      return ProblematicHardwareItem(
        name: name,
        deviceId: deviceId,
        hardwareClass: hardwareClass,
        errorCode: -1,
        errorTitle: 'Firmware Ausente no Kernel',
        errorDescription: details ?? 'O módulo do kernel solicitou um arquivo de firmware proprietário que não foi encontrado em /lib/firmware.',
        suggestedAction: 'Instale o pacote linux-firmware ou os drivers adicionais recomendados da sua distribuição.',
        severity: HardwareProblemSeverity.missingDriver,
      );
    }

    return ProblematicHardwareItem(
      name: name,
      deviceId: deviceId,
      hardwareClass: hardwareClass,
      errorCode: -2,
      errorTitle: 'Dispositivo Sem Driver de Kernel Ativo',
      errorDescription: 'O hardware foi detectado no barramento do sistema, mas nenhum módulo de kernel está gerenciando o dispositivo.',
      suggestedAction: 'Verifique se há drivers proprietários ou módulos DKMS recomendados na seção de atualização.',
      severity: HardwareProblemSeverity.missingDriver,
    );
  }
}

/// Relatório consolidado do diagnóstico do sistema
class SystemTweaksScanReport {
  final DateTime timestamp;
  final String osName;
  final String packageManagerName;
  final bool isPackageManagerAvailable;
  final List<PackageInfoItem> availablePackages;
  final List<DriverUpdateItem> availableDrivers;
  final List<ProblematicHardwareItem> problematicHardware;
  final int scanDurationMs;

  const SystemTweaksScanReport({
    required this.timestamp,
    required this.osName,
    required this.packageManagerName,
    required this.isPackageManagerAvailable,
    required this.availablePackages,
    required this.availableDrivers,
    required this.problematicHardware,
    required this.scanDurationMs,
  });

  bool get hasIssues => problematicHardware.isNotEmpty;
  bool get hasDriverUpdates => availableDrivers.isNotEmpty;
  bool get hasPackageUpdates => availablePackages.isNotEmpty;
}
