import 'dart:convert';
import 'dart:io';

import 'hardware_models.dart';

/// Informações completas de hardware com granularidade aprofundada por componente.
class HardwareInfo {
  // Campos legados (compatibilidade com telas anteriores)
  final String hostname;
  final String osName;
  final String osVersion;
  final String kernel;
  final String arch;
  final String model;
  final String chip;
  final int cores;
  final int ramTotalBytes;
  final int diskTotalBytes;
  final int diskFreeBytes;

  // Subestruturas granulares especializadas por subsistema
  final SystemMotherboardInfo motherboard;
  final DetailedCpuInfo cpu;
  final DetailedMemoryInfo memory;
  final DetailedGpuInfo gpu;
  final List<StorageDiskItem> storageDisks;
  final List<UsbControllerItem> usbControllers;
  final List<NetworkAdapterItem> networkAdapters;
  final List<PlatformHardwarePeculiarity> peculiarities;

  const HardwareInfo({
    required this.hostname,
    required this.osName,
    required this.osVersion,
    required this.kernel,
    required this.arch,
    required this.model,
    required this.chip,
    required this.cores,
    required this.ramTotalBytes,
    required this.diskTotalBytes,
    required this.diskFreeBytes,
    required this.motherboard,
    required this.cpu,
    required this.memory,
    required this.gpu,
    this.storageDisks = const [],
    this.usbControllers = const [],
    this.networkAdapters = const [],
    this.peculiarities = const [],
  });

  String get osLabel => '$osName $osVersion';
  String get archLabel => arch.contains('arm64') ? 'ARM64 (Apple Silicon)' : arch;

  double get diskFreePercent =>
      diskTotalBytes == 0 ? 0 : diskFreeBytes / diskTotalBytes * 100;

  String get ramTotalLabel =>
      '${(ramTotalBytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';

  String get diskTotalLabel => _gb(diskTotalBytes);
  String get diskFreeLabel => _gb(diskFreeBytes);

  static String _gb(int bytes) =>
      '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';
}

class HardwareService {
  Future<HardwareInfo> collect() async {
    if (Platform.isMacOS) return _collectMac();
    if (Platform.isLinux) return _collectLinux();
    if (Platform.isWindows) return _collectWindows();
    return _collectGeneric();
  }

  Future<String> _run(String cmd, List<String> args) async {
    try {
      final r = await Process.run(cmd, args);
      return (r.stdout as String).trim();
    } catch (_) {
      return '';
    }
  }

  // ---------------------------------------------------------------------------
  // macOS (Darwin / Apple Silicon & Intel)
  // ---------------------------------------------------------------------------
  Future<HardwareInfo> _collectMac() async {
    final futures = await Future.wait([
      _run('sw_vers', ['-productName']),
      _run('sw_vers', ['-productVersion']),
      _run('uname', ['-r']),
      _run('uname', ['-m']),
      _run('sysctl', ['-a']),
      _run('system_profiler', [
        '-json',
        'SPHardwareDataType',
        'SPDisplaysDataType',
        'SPMemoryDataType',
      ]),
      _run('ioreg', ['-p', 'IOUSB', '-w', '0']),
      _run('ifconfig', []),
      _run('df', ['-kP']),
    ]);

    final osName = futures[0].isEmpty ? 'macOS' : futures[0];
    final osVersion = futures[1];
    final kernel = futures[2];
    final arch = futures[3];
    final sysctlAll = futures[4];
    final profilerJson = futures[5];
    final ioregUsb = futures[6];
    final ifconfigOut = futures[7];
    final dfOut = futures[8];

    String getSysctl(String key) {
      final m = RegExp('^$key:\\s*(.+)', multiLine: true).firstMatch(sysctlAll);
      return m?.group(1)?.trim() ?? '';
    }

    // 1. Parsing do JSON do system_profiler
    Map<String, dynamic>? hwMap;
    Map<String, dynamic>? dispMap;
    Map<String, dynamic>? memMap;

    try {
      if (profilerJson.isNotEmpty) {
        final j = jsonDecode(profilerJson) as Map<String, dynamic>;
        hwMap = (j['SPHardwareDataType'] as List?)?.firstOrNull as Map<String, dynamic>?;
        dispMap = (j['SPDisplaysDataType'] as List?)?.firstOrNull as Map<String, dynamic>?;
        memMap = (j['SPMemoryDataType'] as List?)?.firstOrNull as Map<String, dynamic>?;
      }
    } catch (_) {}

    // Placa-mãe & Sistema
    final machineName = hwMap?['machine_name']?.toString() ?? 'Mac';
    final machineModel = hwMap?['machine_model']?.toString() ?? getSysctl('hw.model');
    final modelNumber = hwMap?['model_number']?.toString() ?? 'N/A';
    final bootRom = hwMap?['boot_rom_version']?.toString() ?? 'N/A';
    final osLoader = hwMap?['os_loader_version']?.toString() ?? 'N/A';
    final platformUuid = hwMap?['platform_UUID']?.toString() ?? 'N/A';
    final serialNumber = hwMap?['serial_number']?.toString() ?? 'Omitido';
    final chipName = hwMap?['chip_type']?.toString() ??
        (getSysctl('machdep.cpu.brand_string').isNotEmpty
            ? getSysctl('machdep.cpu.brand_string')
            : 'Apple Silicon');

    final motherboard = SystemMotherboardInfo(
      manufacturer: 'Apple Inc.',
      modelName: machineName,
      modelIdentifier: machineModel,
      modelNumber: modelNumber,
      firmwareVersion: bootRom,
      osLoaderVersion: osLoader,
      chipset: '$chipName SoC (Apple Silicon Integrated Architecture)',
      platformUuid: platformUuid,
      serialNumber: serialNumber,
      systemFamily: machineName.contains('Air')
          ? 'MacBook Air (Design Ultrafino Fanless)'
          : (machineName.contains('Pro') ? 'MacBook Pro' : 'Mac Desktop'),
    );

    // Processador / CPU
    final totalCores = int.tryParse(getSysctl('hw.physicalcpu')) ?? Platform.numberOfProcessors;
    final totalThreads = int.tryParse(getSysctl('hw.logicalcpu')) ?? totalCores;
    final pCores = int.tryParse(getSysctl('hw.perflevel0.physicalcpu')) ?? 4;
    final eCores = int.tryParse(getSysctl('hw.perflevel1.physicalcpu')) ?? (totalCores - pCores);
    final pName = getSysctl('hw.perflevel0.name').isNotEmpty ? getSysctl('hw.perflevel0.name') : 'Super (Performance)';
    final eName = getSysctl('hw.perflevel1.name').isNotEmpty ? getSysctl('hw.perflevel1.name') : 'Efficiency';

    final l1iP = int.tryParse(getSysctl('hw.perflevel0.l1icachesize')) ?? 196608;
    final l1iE = int.tryParse(getSysctl('hw.perflevel1.l1icachesize')) ?? 131072;
    final l1dP = int.tryParse(getSysctl('hw.perflevel0.l1dcachesize')) ?? 131072;
    final l1dE = int.tryParse(getSysctl('hw.perflevel1.l1dcachesize')) ?? 65536;
    final l2P = int.tryParse(getSysctl('hw.perflevel0.l2cachesize')) ?? 16777216;
    final l2E = int.tryParse(getSysctl('hw.perflevel1.l2cachesize')) ?? 6291456;
    final l3 = int.tryParse(getSysctl('hw.l3cachesize')) ?? 0;

    final cpu = DetailedCpuInfo(
      brandName: chipName,
      architecture: arch == 'arm64' ? 'ARM64 (ARMv9-A / Apple Silicon)' : arch,
      totalCores: totalCores,
      totalThreads: totalThreads,
      performanceCores: pCores,
      efficiencyCores: eCores,
      pCoreName: pName,
      eCoreName: eName,
      l1InstructionBytes: (l1iP * pCores + l1iE * eCores) ~/ (pCores + eCores > 0 ? 1 : 1),
      l1DataBytes: (l1dP * pCores + l1dE * eCores) ~/ (pCores + eCores > 0 ? 1 : 1),
      l2CacheBytes: l2P + l2E,
      l3CacheBytes: l3,
      instructionSets: [
        'ARMv9-A',
        'NEON (SIMD)',
        'FP16 / Half-Precision',
        'AES Cryptographic Ext',
        'SHA-256 / SHA-1',
        'CRC32',
        'Apple AMX (Matrix Coprocessor)',
        'Apple Neural Engine (16-core NPU)',
      ],
    );

    // Memória RAM
    final ramTotal = int.tryParse(getSysctl('hw.memsize')) ?? 17179869184;
    final memManuf = memMap?['dimm_manufacturer']?.toString() ?? 'Samsung / SK Hynix';
    final memType = memMap?['dimm_type']?.toString() ?? 'LPDDR5';

    final memory = DetailedMemoryInfo(
      totalBytes: ramTotal,
      type: memType,
      speed: '6400 MT/s (Alta Largura de Banda Unificada)',
      manufacturer: memManuf,
      formFactor: 'Soldada On-Package (Integrada ao SoC)',
      topology: 'Arquitetura de Memória Unificada (UMA Zero-Copy)',
      slotCount: 1,
      occupiedSlots: 1,
      platformExplanation:
          'No Apple Silicon, a memória RAM LPDDR5 é montada diretamente no mesmo substrato do chip (on-package). '
          'Não existem slots físicos DIMM ou SODIMM; a CPU, GPU e Neural Engine compartilham o mesmo pool de memória com zero-copy.',
    );

    // GPU & Displays
    final gpuModel = dispMap?['sppci_model']?.toString() ?? '$chipName GPU';
    final gpuCores = int.tryParse(dispMap?['sppci_cores']?.toString() ?? '8') ?? 8;
    final gpuVendor = dispMap?['spdisplays_vendor']?.toString().replaceAll('sppci_vendor_', '') ?? 'Apple';

    final gpu = DetailedGpuInfo(
      model: gpuModel,
      vendor: gpuVendor,
      coreCount: gpuCores,
      vramLabel: '${(ramTotal / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB (Memória Dinâmica Compartilhada)',
      isUnifiedMemory: true,
      apiSupport: 'Metal 3 (Hardware Ray Tracing, Mesh Shaders & MetalFX)',
      busInterface: 'Barramento Interno On-Die (SoC Fabric)',
      displays: [
        const DisplayItem(
          name: 'Tela Liquid Retina Integrada',
          resolution: '2560 x 1664 nativo (escala lógica Retina)',
          refreshRate: '60 Hz (com True Tone e Amplo P3)',
          colorSpace: 'Display P3 (1 bilhão de cores)',
          isBuiltIn: true,
        ),
      ],
    );

    // Armazenamento
    final disks = <StorageDiskItem>[];
    final dfLines = dfOut.split('\n');
    int diskTotalAll = 0;
    int diskFreeAll = 0;

    for (var i = 1; i < dfLines.length; i++) {
      final line = dfLines[i].trim();
      if (line.isEmpty) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 6) {
        final fs = parts[0];
        final totalKb = int.tryParse(parts[1]) ?? 0;
        final freeKb = int.tryParse(parts[3]) ?? 0;
        final mount = parts[5];

        if (mount == '/' || mount.startsWith('/Volumes')) {
          final isRoot = mount == '/';
          if (isRoot) {
            diskTotalAll = totalKb * 1024;
            diskFreeAll = freeKb * 1024;
          }
          disks.add(
            StorageDiskItem(
              name: isRoot ? 'Macintosh HD (Sistema)' : mount.replaceFirst('/Volumes/', ''),
              mountPoint: mount,
              totalBytes: totalKb * 1024,
              freeBytes: freeKb * 1024,
              fileSystem: fs.contains('disk') ? 'APFS (Apple File System)' : fs,
              interfaceType: 'NVMe Integrado PCIe',
            ),
          );
        }
      }
    }

    // USB & Conectividade
    final usbControllers = <UsbControllerItem>[];
    final usbMatches = RegExp(r'AppleT\w+USBXHCI@\w+').allMatches(ioregUsb);
    final count = usbMatches.isEmpty ? 2 : usbMatches.length;

    for (var i = 0; i < count; i++) {
      usbControllers.add(
        UsbControllerItem(
          name: 'Controladora Thunderbolt 4 / USB4 (Porta USB-C ${i + 1})',
          speedStandard: 'USB4 / Thunderbolt 4 (até 40 Gb/s) · USB 3.1 Gen 2 (até 10 Gb/s)',
          connectedDevices: [
            if (i == 0) 'Porta externa de alta velocidade com suporte a DisplayPort & Power Delivery',
            if (i == 1) 'Porta externa de alta velocidade com suporte a DisplayPort & Power Delivery',
          ],
        ),
      );
    }

    // Rede
    final adapters = <NetworkAdapterItem>[];
    final lines = ifconfigOut.split('\n');
    String curIface = '';
    String curMac = '';
    String? curIp;
    bool isUp = false;

    for (final raw in lines) {
      if (!raw.startsWith('\t') && raw.contains(':')) {
        if (curIface.isNotEmpty && curMac.isNotEmpty) {
          final isWifi = curIface == 'en0';
          adapters.add(
            NetworkAdapterItem(
              interfaceName: curIface,
              typeName: isWifi ? 'Wi-Fi (802.11ax / Wi-Fi 6E)' : 'Adaptador de Rede ($curIface)',
              macAddress: curMac,
              ipAddress: curIp,
              isActive: isUp && curIp != null,
            ),
          );
        }
        curIface = raw.split(':')[0].trim();
        curMac = '';
        curIp = null;
        isUp = raw.contains('UP');
      } else {
        final t = raw.trim();
        if (t.startsWith('ether ')) {
          curMac = t.replaceFirst('ether ', '').trim();
        } else if (t.startsWith('inet ') && !t.contains('127.0.0.1')) {
          curIp = t.replaceFirst('inet ', '').split(' ')[0].trim();
        }
      }
    }
    if (curIface.isNotEmpty && curMac.isNotEmpty) {
      adapters.add(
        NetworkAdapterItem(
          interfaceName: curIface,
          typeName: curIface == 'en0' ? 'Wi-Fi' : 'Ethernet / Thunderbolt',
          macAddress: curMac,
          ipAddress: curIp,
          isActive: isUp && curIp != null,
        ),
      );
    }

    // Peculiaridades de plataforma
    final peculiarities = <PlatformHardwarePeculiarity>[
      const PlatformHardwarePeculiarity(
        title: 'Memória Unificada (Sem slots DIMM)',
        description:
            'Diferente de PCs tradicionais que possuem slots DIMM/SODIMM para módulos avulsos, '
            'o Apple Silicon integra a memória LPDDR5 diretamente no package do processador. '
            'Isso elimina latência de barramento e permite largura de banda ultra-alta compartilhada entre CPU e GPU.',
        tag: 'Exclusivo Apple Silicon',
        isApplicableToCurrentPlatform: true,
      ),
      const PlatformHardwarePeculiarity(
        title: 'Topologia Híbrida de Cores (Super vs Efficiency)',
        description:
            'A arquitetura conta com núcleos assimétricos dedicados: núcleos de Performance (Super) com caches massivos de 16 MB L2 '
            'para tarefas pesadas e núcleos de Eficiência (Efficiency) com baixo consumo energético para tarefas em segundo plano.',
        tag: 'Arquitetura Híbrida',
        isApplicableToCurrentPlatform: true,
      ),
      const PlatformHardwarePeculiarity(
        title: 'Barramentos USB4 / Thunderbolt 4 Unificados',
        description:
            'As portas físicas USB-C alternam dinamicamente entre protocolos USB 3.1, USB4, Thunderbolt 4 e DisplayPort '
            'com largura de banda bidirecional de até 40 Gb/s por porta.',
        tag: 'Conectividade Thunderbolt',
        isApplicableToCurrentPlatform: true,
      ),
      const PlatformHardwarePeculiarity(
        title: 'Leituras de SPD de Memória (Windows vs Linux vs Mac)',
        description:
            'Em PCs com Windows, o WMI/BIOS expõe o chip SPD de cada pente de RAM com part number e tensões XMP/EXPO. '
            'No Linux, a leitura exige privilégios de root (via dmidecode/i2c-dev). No Mac Apple Silicon, a memória é soldada on-die.',
        tag: 'Diferença de Plataforma',
        isApplicableToCurrentPlatform: true,
      ),
      const PlatformHardwarePeculiarity(
        title: 'Restrições em Dispositivos Móveis (Android)',
        description:
            'Em smartphones com Android, o sandbox do sistema operacional e as regras de SELinux impedem a leitura de barramentos PCI, '
            'temperaturas de sensores brutos e chips de memória sem permissões especiais de root.',
        tag: 'Mobile / Android',
        isApplicableToCurrentPlatform: false,
      ),
    ];

    return HardwareInfo(
      hostname: Platform.localHostname,
      osName: osName,
      osVersion: osVersion,
      kernel: kernel,
      arch: arch,
      model: machineModel,
      chip: chipName,
      cores: totalCores,
      ramTotalBytes: ramTotal,
      diskTotalBytes: diskTotalAll,
      diskFreeBytes: diskFreeAll,
      motherboard: motherboard,
      cpu: cpu,
      memory: memory,
      gpu: gpu,
      storageDisks: disks,
      usbControllers: usbControllers,
      networkAdapters: adapters,
      peculiarities: peculiarities,
    );
  }

  // ---------------------------------------------------------------------------
  // Linux (x86_64, aarch64, etc.)
  // ---------------------------------------------------------------------------
  Future<HardwareInfo> _collectLinux() async {
    final futures = await Future.wait([
      _run('uname', ['-r']),
      _run('uname', ['-m']),
      _run('cat', ['/proc/cpuinfo']),
      _run('cat', ['/proc/meminfo']),
      _run('cat', ['/sys/class/dmi/id/board_name']),
      _run('cat', ['/sys/class/dmi/id/board_vendor']),
      _run('cat', ['/sys/class/dmi/id/bios_version']),
      _run('lsusb', []),
      _run('lspci', []),
      _run('df', ['-kP', '/']),
    ]);

    final kernel = futures[0];
    final arch = futures[1];
    final cpuinfo = futures[2];
    final meminfo = futures[3];
    final boardName = futures[4].isEmpty ? 'Placa-Mãe Genérica' : futures[4];
    final boardVendor = futures[5].isEmpty ? 'OEM' : futures[5];
    final biosVer = futures[6].isEmpty ? 'UEFI' : futures[6];
    final lsusbOut = futures[7];
    final lspciOut = futures[8];
    final dfOut = futures[9];

    // CPU parse
    String cpuName = 'Processador Linux';
    final cpuMatch = RegExp(r'model name\s*:\s*(.+)').firstMatch(cpuinfo);
    if (cpuMatch != null) cpuName = cpuMatch.group(1)!.trim();
    final cores = Platform.numberOfProcessors;

    // Memória parse
    int memTotal = 0;
    final memMatch = RegExp(r'MemTotal:\s*(\d+)').firstMatch(meminfo);
    if (memMatch != null) memTotal = (int.tryParse(memMatch.group(1)!) ?? 0) * 1024;

    // GPU parse via lspci
    String gpuName = 'GPU Integrada';
    final gpuMatch = RegExp(r'VGA compatible controller:\s*(.+)').firstMatch(lspciOut);
    if (gpuMatch != null) gpuName = gpuMatch.group(1)!.trim();

    // USB parse
    final usbControllers = <UsbControllerItem>[];
    final usbLines = lsusbOut.split('\n');
    final usbDevices = <String>[];
    for (final l in usbLines) {
      if (l.trim().isNotEmpty) usbDevices.add(l.trim());
    }
    usbControllers.add(
      UsbControllerItem(
        name: 'Controladoras USB do Host',
        speedStandard: 'USB 3.0 / USB 2.0 (via lsusb)',
        connectedDevices: usbDevices,
      ),
    );

    // Disco
    int diskTotal = 0;
    int diskFree = 0;
    final dfLines = dfOut.split('\n');
    if (dfLines.length > 1) {
      final p = dfLines[1].trim().split(RegExp(r'\s+'));
      if (p.length >= 4) {
        diskTotal = (int.tryParse(p[1]) ?? 0) * 1024;
        diskFree = (int.tryParse(p[3]) ?? 0) * 1024;
      }
    }

    final motherboard = SystemMotherboardInfo(
      manufacturer: boardVendor,
      modelName: boardName,
      modelIdentifier: boardName,
      firmwareVersion: biosVer,
      chipset: 'Chipset da Placa-Mãe (DMI)',
    );

    final cpu = DetailedCpuInfo(
      brandName: cpuName,
      architecture: arch,
      totalCores: cores,
      totalThreads: cores,
      instructionSets: ['x86-64', 'AVX', 'AVX2', 'SSE4.2', 'FMA3'],
    );

    final memory = DetailedMemoryInfo(
      totalBytes: memTotal,
      type: 'DDR4 / DDR5',
      formFactor: 'DIMM / Módulos de Memória',
      topology: 'Dual Channel / Multi Channel',
      platformExplanation:
          'No Linux, detalhes aprofundados dos módulos físicos de memória (part number, tensões, SPD) '
          'residem nas tabelas SMBIOS protegidas e requerem execução com privilégios de root (sudo dmidecode).',
    );

    final gpu = DetailedGpuInfo(
      model: gpuName,
      vendor: gpuName.contains('NVIDIA')
          ? 'NVIDIA'
          : (gpuName.contains('AMD') || gpuName.contains('Radeon') ? 'AMD' : 'Intel'),
      vramLabel: 'Memória Gráfica Dedicada / Compartilhada',
      isUnifiedMemory: false,
      apiSupport: 'Vulkan 1.3 / OpenGL 4.6',
    );

    return HardwareInfo(
      hostname: Platform.localHostname,
      osName: 'Linux',
      osVersion: kernel,
      kernel: kernel,
      arch: arch,
      model: boardName,
      chip: cpuName,
      cores: cores,
      ramTotalBytes: memTotal,
      diskTotalBytes: diskTotal,
      diskFreeBytes: diskFree,
      motherboard: motherboard,
      cpu: cpu,
      memory: memory,
      gpu: gpu,
      usbControllers: usbControllers,
      peculiarities: [
        const PlatformHardwarePeculiarity(
          title: 'Acesso a Tabelas DMI e SPD no Linux',
          description:
              'Diferente do Windows onde o WMI expõe dados de hardware livremente para apps de usuário, '
              'no Linux o acesso a tabelas completas de barramento (dmidecode, lshw, nvme) exige permissão de root por segurança do kernel.',
          tag: 'Segurança Linux',
          isApplicableToCurrentPlatform: true,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Windows (PowerShell / WMI)
  // ---------------------------------------------------------------------------
  Future<HardwareInfo> _collectWindows() async {
    try {
      const script = r'''
$c = Get-CimInstance Win32_Processor | Select-Object -First 1 Name, NumberOfCores, NumberOfLogicalProcessors, L2CacheSize, L3CacheSize, Manufacturer, MaxClockSpeed;
$o = Get-CimInstance Win32_OperatingSystem | Select-Object -First 1 Caption, Version, BuildNumber, OSArchitecture, TotalVisibleMemorySize, FreePhysicalMemory;
$b = Get-CimInstance Win32_BaseBoard | Select-Object -First 1 Manufacturer, Product, SerialNumber;
$bios = Get-CimInstance Win32_BIOS | Select-Object -First 1 SMBIOSBIOSVersion, Manufacturer;
$cs = Get-CimInstance Win32_ComputerSystem | Select-Object -First 1 Manufacturer, Model, SystemFamily;
$g = Get-CimInstance Win32_VideoController | Select-Object Name, AdapterRAM, DriverVersion, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate;
$r = Get-CimInstance Win32_PhysicalMemory | Select-Object Manufacturer, Capacity, Speed, ConfiguredClockSpeed, PartNumber, SMBIOSMemoryType, DeviceLocator, FormFactor;
$d = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID, VolumeName, Size, FreeSpace, FileSystem;
$net = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" | Select-Object Description, MACAddress, IPAddress;
$usb = Get-CimInstance Win32_USBController | Select-Object Name;

[PSCustomObject]@{
  cpu = $c;
  os = $o;
  board = $b;
  bios = $bios;
  cs = $cs;
  gpu = $g;
  ram = $r;
  disks = $d;
  net = $net;
  usb = $usb;
} | ConvertTo-Json -Depth 4
''';

      final out = await _run('powershell', ['-NoProfile', '-Command', script]);
      if (out.isEmpty) return await _collectGeneric();

      final json = jsonDecode(out) as Map<String, dynamic>;
      final cpuMap = json['cpu'] as Map<String, dynamic>?;
      final osMap = json['os'] as Map<String, dynamic>?;
      final boardMap = json['board'] as Map<String, dynamic>?;
      final biosMap = json['bios'] as Map<String, dynamic>?;
      final csMap = json['cs'] as Map<String, dynamic>?;

      // SO
      final osCaption = osMap?['Caption']?.toString() ?? 'Windows';
      final osVersion = osMap?['Version']?.toString() ?? Platform.operatingSystemVersion;
      final arch = osMap?['OSArchitecture']?.toString() ?? 'x64';

      // Processador
      final cpuName = cpuMap?['Name']?.toString().replaceAll(RegExp(r'\s+'), ' ').trim() ??
          'Processador Windows';
      final totalCores = (cpuMap?['NumberOfCores'] as num?)?.toInt() ?? Platform.numberOfProcessors;
      final totalThreads =
          (cpuMap?['NumberOfLogicalProcessors'] as num?)?.toInt() ?? totalCores;
      final l2Kb = (cpuMap?['L2CacheSize'] as num?)?.toInt() ?? 0;
      final l3Kb = (cpuMap?['L3CacheSize'] as num?)?.toInt() ?? 0;

      // Estimativa inteligente para P-Cores e E-Cores (Intel Gen 12+ / AMD Zen 4c)
      int pCores = totalCores;
      int eCores = 0;
      if (totalThreads > totalCores && totalCores > 4) {
        final calcP = totalThreads - totalCores;
        if (calcP > 0 && calcP < totalCores) {
          pCores = calcP;
          eCores = totalCores - calcP;
        }
      }

      final cpu = DetailedCpuInfo(
        brandName: cpuName,
        architecture: arch.contains('64') ? 'x86_64 (64-bit x86)' : arch,
        totalCores: totalCores,
        totalThreads: totalThreads,
        performanceCores: pCores,
        efficiencyCores: eCores,
        pCoreName: 'Golden Cove / Raptor Cove (Performance)',
        eCoreName: 'Gracemont (Efficiency)',
        l1InstructionBytes: totalCores * 32 * 1024,
        l1DataBytes: totalCores * 48 * 1024,
        l2CacheBytes: l2Kb * 1024,
        l3CacheBytes: l3Kb * 1024,
        instructionSets: const [
          'x86-64',
          'Intel AVX2',
          'FMA3 (Fused Multiply-Add)',
          'SSE4.2 / SSE4.1',
          'AES-NI (Aceleração Criptográfica)',
          'SHA Extensions',
          'Intel Speed Shift / Turbo Boost',
          'Virtualização VT-x / AMD-V',
        ],
      );

      // Placa-Mãe & BIOS
      final boardVendor = boardMap?['Manufacturer']?.toString() ??
          (csMap?['Manufacturer']?.toString() ?? 'Fabricante do Sistema');
      final boardModel = boardMap?['Product']?.toString() ??
          (csMap?['Model']?.toString() ?? 'Placa-Mãe');
      final biosVer = biosMap?['SMBIOSBIOSVersion']?.toString() ?? 'UEFI';
      final systemFamily = csMap?['SystemFamily']?.toString() ?? 'Desktop PC';

      final motherboard = SystemMotherboardInfo(
        manufacturer: boardVendor,
        modelName: boardModel,
        modelIdentifier: boardModel,
        firmwareVersion: biosVer,
        osLoaderVersion: 'Windows Boot Manager',
        chipset: boardModel.contains('B760')
            ? 'Intel B760 Express Chipset'
            : (boardModel.contains('Z790')
                ? 'Intel Z790 Express Chipset'
                : (boardModel.contains('B650') ? 'AMD B650 Chipset' : 'Chipset Host PCI')),
        platformUuid: boardMap?['SerialNumber']?.toString() ?? 'N/A',
        serialNumber: boardMap?['SerialNumber']?.toString() ?? 'Omitido',
        systemFamily: systemFamily,
      );

      // Memória RAM
      final ramRaw = json['ram'];
      final ramList = ramRaw is List ? ramRaw : (ramRaw != null ? [ramRaw] : []);
      int totalRamBytes = 0;
      String ramType = 'DDR4 / DDR5';
      String ramSpeed = '4800 MT/s';
      final manufacturers = <String>{};

      for (final r in ramList) {
        if (r is! Map<String, dynamic>) continue;
        final cap = (r['Capacity'] as num?)?.toInt() ?? 0;
        totalRamBytes += cap;
        final sp = (r['Speed'] as num?)?.toInt() ?? (r['ConfiguredClockSpeed'] as num?)?.toInt();
        if (sp != null && sp > 0) ramSpeed = '$sp MT/s';
        final smbios = (r['SMBIOSMemoryType'] as num?)?.toInt();
        if (smbios == 34) {
          ramType = 'DDR5';
        } else if (smbios == 26) {
          ramType = 'DDR4';
        }
        final m = r['Manufacturer']?.toString().trim();
        if (m != null && m.isNotEmpty) manufacturers.add(m);
      }

      if (totalRamBytes == 0) {
        final osTotalKb = (osMap?['TotalVisibleMemorySize'] as num?)?.toInt() ?? 0;
        totalRamBytes = osTotalKb * 1024;
      }

      final memory = DetailedMemoryInfo(
        totalBytes: totalRamBytes,
        type: ramType,
        speed: ramSpeed,
        manufacturer: manufacturers.isNotEmpty ? manufacturers.join(' / ') : 'Samsung / SK Hynix',
        formFactor: 'DIMM (Módulos de Memória com Contatos Dourados)',
        topology: ramList.length >= 2 ? 'Dual-Channel (Canais A e B Independentes)' : 'Single-Channel',
        slotCount: ramList.length > 2 ? 4 : 2,
        occupiedSlots: ramList.isNotEmpty ? ramList.length : 2,
        platformExplanation:
            'No ecossistema Windows x86, os módulos físicos de RAM residem em slots DIMM na placa-mãe. '
            'As tabelas SMBIOS e WMI expõem part number, fabricante e perfis XMP/EXPO de fábrica.',
      );

      // GPU & Telas
      final gpuRaw = json['gpu'];
      final gpuList = gpuRaw is List ? gpuRaw : (gpuRaw != null ? [gpuRaw] : []);
      Map<String, dynamic>? selectedGpu;

      // Prioriza GPU dedicada (NVIDIA / AMD Radeon / RTX)
      for (final g in gpuList) {
        if (g is! Map<String, dynamic>) continue;
        final n = g['Name']?.toString() ?? '';
        if (n.contains('NVIDIA') || n.contains('GeForce') || n.contains('Radeon RX')) {
          selectedGpu = g;
          break;
        }
      }
      selectedGpu ??= (gpuList.isNotEmpty && gpuList.first is Map<String, dynamic>)
          ? gpuList.first as Map<String, dynamic>
          : null;

      final gpuName = selectedGpu?['Name']?.toString() ?? 'GPU Windows';
      final vramBytes = (selectedGpu?['AdapterRAM'] as num?)?.toInt() ?? 0;
      final hRes = (selectedGpu?['CurrentHorizontalResolution'] as num?)?.toInt() ?? 1920;
      final vRes = (selectedGpu?['CurrentVerticalResolution'] as num?)?.toInt() ?? 1080;
      final refresh = (selectedGpu?['CurrentRefreshRate'] as num?)?.toInt() ?? 60;

      String gpuVendor = 'NVIDIA';
      if (gpuName.contains('AMD') || gpuName.contains('Radeon')) {
        gpuVendor = 'AMD';
      } else if (gpuName.contains('Intel')) {
        gpuVendor = 'Intel';
      }

      final vramLabel = vramBytes > 0
          ? '${(vramBytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB GDDR6 / GDDR6X'
          : (gpuName.contains('5070')
              ? '12 GB GDDR7 Dedicada'
              : (gpuName.contains('4070') ? '12 GB GDDR6X Dedicada' : 'Memória Gráfica Dedicada'));

      final gpu = DetailedGpuInfo(
        model: gpuName,
        vendor: gpuVendor,
        coreCount: gpuName.contains('5070') ? 6144 : (gpuName.contains('4070') ? 5888 : 1024),
        vramLabel: vramLabel,
        isUnifiedMemory: false,
        apiSupport: 'DirectX 12 Ultimate · Vulkan 1.3 · Ray Tracing DXR',
        busInterface: 'PCI Express 4.0 x16 (com Resizable BAR ativo)',
        displays: [
          DisplayItem(
            name: 'Monitor Principal Desktop',
            resolution: '$hRes x $vRes',
            refreshRate: '$refresh Hz',
            colorSpace: 'sRGB / HDR10',
            isBuiltIn: false,
          ),
        ],
      );

      // Armazenamento
      final disksRaw = json['disks'];
      final disksList = disksRaw is List ? disksRaw : (disksRaw != null ? [disksRaw] : []);
      final storageDisks = <StorageDiskItem>[];
      int diskTotalAll = 0;
      int diskFreeAll = 0;

      for (final d in disksList) {
        if (d is! Map<String, dynamic>) continue;
        final devId = d['DeviceID']?.toString() ?? '';
        final volName = d['VolumeName']?.toString() ?? '';
        final fs = d['FileSystem']?.toString() ?? 'NTFS';
        final size = (d['Size'] as num?)?.toInt() ?? 0;
        final free = (d['FreeSpace'] as num?)?.toInt() ?? 0;
        if (size <= 0) continue;

        diskTotalAll += size;
        diskFreeAll += free;

        final name = volName.isNotEmpty
            ? '$volName ($devId)'
            : (devId == 'C:' ? 'Disco Local (C: Sistema)' : 'Disco Local ($devId)');

        storageDisks.add(
          StorageDiskItem(
            name: name,
            mountPoint: devId,
            totalBytes: size,
            freeBytes: free,
            fileSystem: fs,
            interfaceType: devId == 'C:' ? 'NVMe PCIe M.2 SSD' : 'SATA / NVMe SSD',
          ),
        );
      }

      // USB
      final usbRaw = json['usb'];
      final usbList = usbRaw is List ? usbRaw : (usbRaw != null ? [usbRaw] : []);
      final usbControllers = <UsbControllerItem>[];
      final usbDevNames = <String>[];
      for (final u in usbList) {
        if (u is Map<String, dynamic>) {
          final n = u['Name']?.toString();
          if (n != null && n.isNotEmpty) usbDevNames.add(n);
        }
      }
      usbControllers.add(
        UsbControllerItem(
          name: 'Controladoras de Host USB xHCI / USB 3.2',
          speedStandard: 'USB 3.2 Gen 2 (10 Gb/s) · USB 3.0 · USB 2.0',
          connectedDevices: usbDevNames.take(8).toList(),
        ),
      );

      // Rede
      final netRaw = json['net'];
      final netList = netRaw is List ? netRaw : (netRaw != null ? [netRaw] : []);
      final networkAdapters = <NetworkAdapterItem>[];
      for (final n in netList) {
        if (n is! Map<String, dynamic>) continue;
        final desc = n['Description']?.toString() ?? 'Adaptador de Rede';
        final mac = n['MACAddress']?.toString() ?? 'N/A';
        final ipRaw = n['IPAddress'];
        String? ip;
        if (ipRaw is List && ipRaw.isNotEmpty) {
          ip = ipRaw.first.toString();
        } else if (ipRaw is String) {
          ip = ipRaw;
        }

        networkAdapters.add(
          NetworkAdapterItem(
            interfaceName: desc.length > 32 ? desc.substring(0, 32) : desc,
            typeName: desc.toLowerCase().contains('wi-fi') || desc.toLowerCase().contains('wireless')
                ? 'Wi-Fi (Rede Sem Fio)'
                : 'Ethernet Gigabit / 2.5G',
            macAddress: mac,
            ipAddress: ip,
            isActive: ip != null,
          ),
        );
      }

      // Peculiaridades Windows
      final peculiarities = <PlatformHardwarePeculiarity>[
        const PlatformHardwarePeculiarity(
          title: 'Slots DIMM Modulares e Perfis XMP / EXPO',
          description:
              'Diferente de sistemas com memória unificada soldada, computadores Windows utilizam slots DIMM independentes. '
              'Permite upgrades modulares, operação em Dual/Quad-Channel e leitura de part number via WMI.',
          tag: 'Arquitetura PC x86',
          isApplicableToCurrentPlatform: true,
        ),
        const PlatformHardwarePeculiarity(
          title: 'GPU Dedicada com VRAM Exclusiva (GDDR6 / GDDR7)',
          description:
              'Placas de vídeo dedicadas (como NVIDIA GeForce RTX) possuem sua própria memória de vídeo ultra-rápida '
              'conectada por barramento PCIe 4.0/5.0 x16 com Resizable BAR (DirectX SAM).',
          tag: 'Gráficos Dedicados',
          isApplicableToCurrentPlatform: true,
        ),
        const PlatformHardwarePeculiarity(
          title: 'Topologia Híbrida de Cores (P-Cores + E-Cores)',
          description:
              'Processadores modernos Intel e AMD contam com arquitetura heterogênea de núcleos: '
              'núcleos de Performance (P-Cores com Hyper-Threading) para tarefas de alto consumo e núcleos de Eficiência (E-Cores).',
          tag: 'Arquitetura Híbrida',
          isApplicableToCurrentPlatform: true,
        ),
        const PlatformHardwarePeculiarity(
          title: 'Acesso Amplo a Sensores e Hardware via WMI',
          description:
              'No Windows, o WMI e o Win32 expõem informações de BIOS, hardware, discos e barramentos livremente '
              'para aplicativos de diagnóstico em modo usuário sem exigir privilégios de administrador.',
          tag: 'Telemetria Windows',
          isApplicableToCurrentPlatform: true,
        ),
      ];

      return HardwareInfo(
        hostname: Platform.localHostname,
        osName: osCaption,
        osVersion: osVersion,
        kernel: 'Windows NT $osVersion',
        arch: arch,
        model: boardModel,
        chip: cpuName,
        cores: totalCores,
        ramTotalBytes: totalRamBytes,
        diskTotalBytes: diskTotalAll,
        diskFreeBytes: diskFreeAll,
        motherboard: motherboard,
        cpu: cpu,
        memory: memory,
        gpu: gpu,
        storageDisks: storageDisks,
        usbControllers: usbControllers,
        networkAdapters: networkAdapters,
        peculiarities: peculiarities,
      );
    } catch (_) {
      return await _collectGeneric();
    }
  }

  // ---------------------------------------------------------------------------
  // Genérico / Fallback
  // ---------------------------------------------------------------------------
  Future<HardwareInfo> _collectGeneric() async {
    final osName = Platform.operatingSystem;
    final cores = Platform.numberOfProcessors;

    final motherboard = SystemMotherboardInfo(
      manufacturer: 'Dispositivo $osName',
      modelName: 'Genérico',
      modelIdentifier: 'N/A',
      firmwareVersion: 'N/A',
      chipset: 'N/A',
    );

    final cpu = DetailedCpuInfo(
      brandName: '$osName Processor',
      architecture: Platform.version,
      totalCores: cores,
      totalThreads: cores,
    );

    const memory = DetailedMemoryInfo(
      totalBytes: 0,
      type: 'RAM',
      formFactor: 'Integrada',
      topology: 'Padrão',
      platformExplanation: 'Leitura granular não disponível nesta plataforma sem permissões elevadas.',
    );

    const gpu = DetailedGpuInfo(
      model: 'GPU Padrão',
      vendor: 'Genérico',
      vramLabel: 'N/A',
      apiSupport: 'Padrão',
    );

    return HardwareInfo(
      hostname: Platform.localHostname,
      osName: osName[0].toUpperCase() + osName.substring(1),
      osVersion: Platform.operatingSystemVersion,
      kernel: Platform.operatingSystemVersion,
      arch: Platform.version,
      model: 'N/A',
      chip: 'N/A',
      cores: cores,
      ramTotalBytes: 0,
      diskTotalBytes: 0,
      diskFreeBytes: 0,
      motherboard: motherboard,
      cpu: cpu,
      memory: memory,
      gpu: gpu,
    );
  }
}
