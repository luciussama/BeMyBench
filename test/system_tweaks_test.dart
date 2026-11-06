import 'package:bemybench/features/system_tweaks/system_tweaks_models.dart';
import 'package:bemybench/features/system_tweaks/system_tweaks_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SystemTweaksModels - Diagnóstico e Mapeamento de Erros', () {
    test('Mapeia Código 28 (Driver não instalado) corretamente', () {
      final item = ProblematicHardwareItem.fromWindowsPnp(
        name: 'Controlador de Comunicação PCI Simples',
        deviceId: r'PCI\VEN_8086&DEV_A13A',
        hardwareClass: 'Outros Dispositivos',
        errorCode: 28,
      );

      expect(item.errorCode, 28);
      expect(item.errorTitle, contains('Código 28'));
      expect(item.severity, HardwareProblemSeverity.missingDriver);
      expect(item.suggestedAction, contains('fabricante'));
    });

    test('Mapeia Código 10 (Falha ao iniciar) corretamente', () {
      final item = ProblematicHardwareItem.fromWindowsPnp(
        name: 'Dispositivo de Áudio de Alta Definição',
        deviceId: r'HDAUDIO\FUNC_01',
        hardwareClass: 'Controladores de som',
        errorCode: 10,
      );

      expect(item.errorCode, 10);
      expect(item.severity, HardwareProblemSeverity.deviceFailed);
      expect(item.errorDescription, contains('não pôde ser inicializado'));
    });

    test('Mapeia Código 43 (Dispositivo com falha interna) corretamente', () {
      final item = ProblematicHardwareItem.fromWindowsPnp(
        name: 'NVIDIA GeForce RTX 3080',
        deviceId: r'PCI\VEN_10DE&DEV_2206',
        hardwareClass: 'Adaptadores de vídeo',
        errorCode: 43,
      );

      expect(item.errorCode, 43);
      expect(item.severity, HardwareProblemSeverity.deviceFailed);
      expect(item.errorTitle, contains('Código 43'));
    });

    test('Mapeia Ocorrências Linux com Firmware Ausente e Sem Driver', () {
      final firmwareItem = ProblematicHardwareItem.fromLinux(
        name: 'Placa Wi-Fi Intel AX200',
        deviceId: '0000:03:00.0',
        hardwareClass: 'Rede',
        hasMissingFirmware: true,
      );
      expect(firmwareItem.errorTitle, contains('Firmware Ausente'));
      expect(firmwareItem.severity, HardwareProblemSeverity.missingDriver);

      final noDriverItem = ProblematicHardwareItem.fromLinux(
        name: 'Broadcom BCM4360',
        deviceId: '02:00.0',
        hardwareClass: 'Controlador PCI',
        hasMissingFirmware: false,
      );
      expect(noDriverItem.errorTitle, contains('Sem Driver de Kernel Ativo'));
      expect(noDriverItem.severity, HardwareProblemSeverity.missingDriver);
    });
  });

  group('SystemTweaksService - Parsers de Pacotes (Pilar 1)', () {
    test('parseWingetOutput processa tabela padrão do winget', () {
      const sampleWinget = '''
Nome                   Id                         Versão          Disponível     Origem
---------------------------------------------------------------------------------------
Google Chrome          Google.Chrome              120.0.6099.130  121.0.6167.86  winget
Git                    Git.Git                    2.43.0          2.44.0         winget
Microsoft Visual C++   Microsoft.VCRedist.2015+   14.38.33130.0   14.38.33135.0  winget
''';

      final items = SystemTweaksService.parseWingetOutput(sampleWinget);
      expect(items.length, 3);
      expect(items[0].name, 'Google Chrome');
      expect(items[0].id, 'Google.Chrome');
      expect(items[0].currentVersion, '120.0.6099.130');
      expect(items[0].availableVersion, '121.0.6167.86');
      expect(items[0].source, 'winget');

      expect(items[1].name, 'Git');
      expect(items[1].availableVersion, '2.44.0');
    });

    test('parseAptListOutput processa formato apt list --upgradable', () {
      const sampleApt = '''
Listing... Done
libssl3/jammy-updates 3.0.2-0ubuntu1.18 amd64 [upgradable from: 3.0.2-0ubuntu1.17]
curl/jammy-updates,jammy-security 7.81.0-1ubuntu1.16 amd64 [upgradable from: 7.81.0-1ubuntu1.15]
''';

      final items = SystemTweaksService.parseAptListOutput(sampleApt);
      expect(items.length, 2);
      expect(items[0].name, 'libssl3');
      expect(items[0].currentVersion, '3.0.2-0ubuntu1.17');
      expect(items[0].availableVersion, '3.0.2-0ubuntu1.18');

      expect(items[1].name, 'curl');
      expect(items[1].availableVersion, '7.81.0-1ubuntu1.16');
    });
  });

  group('SystemTweaksService - Parsers de Drivers (Pilar 2)', () {
    test('parseWindowsDriversJson converte saída da API COM do Windows Update', () {
      const sampleJson = '''
[
  {
    "deviceName": "Intel - System - 10.1.18243.8188",
    "availableVersion": "2023-08-15",
    "releaseDate": "2023-08-15",
    "manufacturer": "Intel Corporation",
    "provider": "Windows Update",
    "isFirmware": false
  },
  {
    "deviceName": "Dell System Firmware 1.15.0",
    "availableVersion": "2024-01-10",
    "releaseDate": "2024-01-10",
    "manufacturer": "Dell Inc.",
    "provider": "Windows Update",
    "isFirmware": true
  }
]
''';

      final items = SystemTweaksService.parseWindowsDriversJson(sampleJson);
      expect(items.length, 2);
      expect(items[0].deviceName, contains('Intel'));
      expect(items[0].isFirmware, isFalse);

      expect(items[1].deviceName, contains('Firmware'));
      expect(items[1].isFirmware, isTrue);
    });

    test('parseFwupdJson converte formato JSON do fwupdmgr', () {
      const sampleFwupd = '''
{
  "Devices": [
    {
      "Name": "System Firmware",
      "Vendor": "Lenovo",
      "Version": "1.34",
      "Releases": [
        {
          "Version": "1.35",
          "Created": 1704067200
        }
      ]
    }
  ]
}
''';

      final items = SystemTweaksService.parseFwupdJson(sampleFwupd);
      expect(items.length, 1);
      expect(items[0].deviceName, 'System Firmware');
      expect(items[0].currentVersion, '1.34');
      expect(items[0].availableVersion, '1.35');
      expect(items[0].manufacturer, 'Lenovo');
      expect(items[0].isFirmware, isTrue);
    });

    test('parseUbuntuDriversOutput extrai driver proprietário recomendado', () {
      const sampleUbuntuDrivers = '''
== /sys/devices/pci0000:00/0000:00:01.0/0000:01:00.0 ==
modalias : pci:v000010DEd00001C03sv00001043sd000085ABbc03sc00i00
model    : GP106 [GeForce GTX 1060 6GB]
vendor   : NVIDIA Corporation
driver   : nvidia-driver-535 - distro non-free recommended
driver   : nvidia-driver-470 - distro non-free
''';

      final items = SystemTweaksService.parseUbuntuDriversOutput(sampleUbuntuDrivers);
      expect(items.length, 1);
      expect(items[0].deviceName, 'GP106 [GeForce GTX 1060 6GB]');
      expect(items[0].availableVersion, 'nvidia-driver-535');
      expect(items[0].manufacturer, 'NVIDIA Corporation');
    });
  });

  group('SystemTweaksService - Parsers de Hardware Problemático (Pilar 3)', () {
    test('parseWindowsProblemsJson converte entidades WMI com erro', () {
      const sampleJson = '''
[
  {
    "name": "Dispositivo Desconhecido",
    "deviceId": "ACPI\\\\VEN_INT&DEV_3400",
    "hardwareClass": "System",
    "errorCode": 28
  },
  {
    "name": "Intel Wi-Fi 6 AX201",
    "deviceId": "PCI\\\\VEN_8086&DEV_A0F0",
    "hardwareClass": "Net",
    "errorCode": 10
  }
]
''';

      final problems = SystemTweaksService.parseWindowsProblemsJson(sampleJson);
      expect(problems.length, 2);
      expect(problems[0].errorCode, 28);
      expect(problems[0].severity, HardwareProblemSeverity.missingDriver);
      expect(problems[1].errorCode, 10);
      expect(problems[1].severity, HardwareProblemSeverity.deviceFailed);
    });

    test('parseLspciOutput identifica dispositivos PCI sem driver de kernel gerenciando', () {
      const sampleLspci = '''
00:00.0 Host bridge [0600]: Intel Corporation 8th Gen Core Processor Host Bridge/DRAM Registers [8086:3ec2] (rev 07)
	Subsystem: Dell Device [1028:085b]

00:02.0 VGA compatible controller [0300]: Intel Corporation UHD Graphics 630 [8086:3e92]
	Subsystem: Dell Device [1028:085b]
	Kernel driver in use: i915
	Kernel modules: i915

02:00.0 Network controller [0280]: Broadcom Inc. and subsidiaries BCM4360 [14e4:43a0] (rev 03)
	Subsystem: Apple Inc. AirPort Extreme [106b:0117]
	Kernel modules: bcma, wl
''';

      final problems = SystemTweaksService.parseLspciOutput(sampleLspci);
      // Host bridge deve ser ignorado.
      // Intel UHD Graphics possui "Kernel driver in use: i915" -> OK.
      // Broadcom BCM4360 NÃO possui "Kernel driver in use" -> Falta driver!
      expect(problems.length, 1);
      expect(problems[0].deviceId, '02:00.0');
      expect(problems[0].name, contains('Broadcom Inc.'));
      expect(problems[0].errorTitle, contains('Sem Driver de Kernel Ativo'));
    });

    test('parseDmesgOutput identifica logs de falha no carregamento de firmware', () {
      const sampleDmesg = '''
[    2.341200] iwlwifi 0000:03:00.0: firmware: failed to load iwlwifi-QuZ-a0-hr-b0-77.ucode (-2)
[    2.341250] iwlwifi 0000:03:00.0: Direct firmware load for iwlwifi-QuZ-a0-hr-b0-77.ucode failed with error -2
''';

      final problems = SystemTweaksService.parseDmesgOutput(sampleDmesg);
      expect(problems.length, 2);
      expect(problems[0].errorTitle, contains('Firmware Ausente'));
      expect(problems[0].severity, HardwareProblemSeverity.missingDriver);
    });
  });
}
