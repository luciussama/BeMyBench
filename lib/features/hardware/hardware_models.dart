/// Modelos de dados granulares de hardware por componente e subsistema
/// com suporte a adaptação dinâmica entre macOS, Windows, Linux e Android.
library hardware_models;

class SystemMotherboardInfo {
  final String manufacturer;
  final String modelName;
  final String modelIdentifier;
  final String modelNumber;
  final String firmwareVersion; // BIOS / Boot ROM / EFI
  final String osLoaderVersion;
  final String chipset;
  final String platformUuid;
  final String serialNumber;
  final String systemFamily;

  const SystemMotherboardInfo({
    required this.manufacturer,
    required this.modelName,
    required this.modelIdentifier,
    this.modelNumber = 'N/A',
    required this.firmwareVersion,
    this.osLoaderVersion = 'N/A',
    required this.chipset,
    this.platformUuid = 'N/A',
    this.serialNumber = 'N/A',
    this.systemFamily = 'Desktop / Laptop',
  });
}

class DetailedCpuInfo {
  final String brandName;
  final String architecture;
  final int totalCores;
  final int totalThreads;
  final int performanceCores;
  final int efficiencyCores;
  final String pCoreName;
  final String eCoreName;
  final int l1InstructionBytes;
  final int l1DataBytes;
  final int l2CacheBytes;
  final int l3CacheBytes;
  final double? baseClockGhz;
  final double? maxClockGhz;
  final List<String> instructionSets;

  const DetailedCpuInfo({
    required this.brandName,
    required this.architecture,
    required this.totalCores,
    required this.totalThreads,
    this.performanceCores = 0,
    this.efficiencyCores = 0,
    this.pCoreName = 'Performance',
    this.eCoreName = 'Efficiency',
    this.l1InstructionBytes = 0,
    this.l1DataBytes = 0,
    this.l2CacheBytes = 0,
    this.l3CacheBytes = 0,
    this.baseClockGhz,
    this.maxClockGhz,
    this.instructionSets = const [],
  });

  String get l1Label {
    final total = l1InstructionBytes + l1DataBytes;
    if (total == 0) return 'N/A';
    return '${(total / 1024).round()} KB (I: ${(l1InstructionBytes / 1024).round()} KB, D: ${(l1DataBytes / 1024).round()} KB)';
  }

  String get l2Label {
    if (l2CacheBytes == 0) return 'N/A';
    return '${(l2CacheBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get l3Label {
    if (l3CacheBytes == 0) return 'Nenhum (L2 compartilhado de alta largura de banda)';
    return '${(l3CacheBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class DetailedMemoryInfo {
  final int totalBytes;
  final String type; // LPDDR5, DDR5, DDR4, etc.
  final String speed; // ex: 6400 MT/s
  final String manufacturer; // ex: Samsung, Micron, SK Hynix
  final String formFactor; // On-Die Unificada, DIMM, SODIMM
  final String topology; // Unificada (UMA), Dual Channel, Single Channel
  final int slotCount;
  final int occupiedSlots;
  final String platformExplanation;

  const DetailedMemoryInfo({
    required this.totalBytes,
    required this.type,
    this.speed = 'N/A',
    this.manufacturer = 'Apple / OEM',
    required this.formFactor,
    required this.topology,
    this.slotCount = 1,
    this.occupiedSlots = 1,
    required this.platformExplanation,
  });

  String get totalGbLabel =>
      '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';
}

class DetailedGpuInfo {
  final String model;
  final String vendor;
  final int coreCount;
  final String vramLabel;
  final bool isUnifiedMemory;
  final String apiSupport;
  final String busInterface;
  final List<DisplayItem> displays;

  const DetailedGpuInfo({
    required this.model,
    required this.vendor,
    this.coreCount = 0,
    required this.vramLabel,
    this.isUnifiedMemory = true,
    required this.apiSupport,
    this.busInterface = 'Integrado / On-Die',
    this.displays = const [],
  });
}

class DisplayItem {
  final String name;
  final String resolution;
  final String refreshRate;
  final String colorSpace;
  final bool isBuiltIn;

  const DisplayItem({
    required this.name,
    required this.resolution,
    this.refreshRate = '60 Hz',
    this.colorSpace = 'sRGB / P3',
    this.isBuiltIn = true,
  });
}

class StorageDiskItem {
  final String name;
  final String mountPoint;
  final int totalBytes;
  final int freeBytes;
  final String fileSystem; // APFS, ext4, NTFS
  final String interfaceType; // NVMe PCIe, SATA

  const StorageDiskItem({
    required this.name,
    required this.mountPoint,
    required this.totalBytes,
    required this.freeBytes,
    required this.fileSystem,
    this.interfaceType = 'NVMe / Integrado',
  });

  String get totalGbLabel => _gb(totalBytes);
  String get freeGbLabel => _gb(freeBytes);
  double get usedPercent =>
      totalBytes == 0 ? 0 : (totalBytes - freeBytes) / totalBytes * 100;

  static String _gb(int b) =>
      '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class UsbControllerItem {
  final String name;
  final String speedStandard; // USB 3.1, USB4, Thunderbolt 4, USB 2.0
  final List<String> connectedDevices;

  const UsbControllerItem({
    required this.name,
    required this.speedStandard,
    this.connectedDevices = const [],
  });
}

class NetworkAdapterItem {
  final String interfaceName;
  final String typeName; // Wi-Fi, Ethernet, Loopback
  final String macAddress;
  final String? ipAddress;
  final bool isActive;

  const NetworkAdapterItem({
    required this.interfaceName,
    required this.typeName,
    required this.macAddress,
    this.ipAddress,
    this.isActive = true,
  });
}

class PlatformHardwarePeculiarity {
  final String title;
  final String description;
  final String tag;
  final bool isApplicableToCurrentPlatform;

  const PlatformHardwarePeculiarity({
    required this.title,
    required this.description,
    required this.tag,
    required this.isApplicableToCurrentPlatform,
  });
}
