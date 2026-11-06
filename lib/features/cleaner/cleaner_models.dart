library cleaner_models;

import 'package:flutter/material.dart';

/// Categorias de arquivos para limpeza segura de disco/SSD.
enum CleanCategoryType {
  userCache,
  developerCache,
  systemTemp,
  crashLogs,
  userTrash,
}

extension CleanCategoryTypeExt on CleanCategoryType {
  String get title {
    switch (this) {
      case CleanCategoryType.userCache:
        return 'Caches de Aplicativos';
      case CleanCategoryType.developerCache:
        return 'Caches de Desenvolvimento';
      case CleanCategoryType.systemTemp:
        return 'Arquivos Temporários do Sistema';
      case CleanCategoryType.crashLogs:
        return 'Logs e Relatórios de Falha';
      case CleanCategoryType.userTrash:
        return 'Lixeira do Sistema';
    }
  }

  String get description {
    switch (this) {
      case CleanCategoryType.userCache:
        return 'Arquivos de cache temporário criados por apps navegadores e utilitários que podem ser recriados automaticamente.';
      case CleanCategoryType.developerCache:
        return 'Artefatos de compilação intermediários (Xcode DerivedData, Gradle, CocoaPods, etc.).';
      case CleanCategoryType.systemTemp:
        return 'Arquivos de trabalho temporários órfãos deixados por processos encerrados da sessão.';
      case CleanCategoryType.crashLogs:
        return 'Relatórios de erro, dumps de falha e logs antigos de diagnóstico.';
      case CleanCategoryType.userTrash:
        return 'Arquivos descartados pelo usuário aguardando esvaziamento permanente.';
    }
  }

  IconData get icon {
    switch (this) {
      case CleanCategoryType.userCache:
        return Icons.cached;
      case CleanCategoryType.developerCache:
        return Icons.code;
      case CleanCategoryType.systemTemp:
        return Icons.folder_delete_outlined;
      case CleanCategoryType.crashLogs:
        return Icons.bug_report_outlined;
      case CleanCategoryType.userTrash:
        return Icons.delete_outline;
    }
  }

  bool get isRecommendedDefault {
    switch (this) {
      case CleanCategoryType.userCache:
      case CleanCategoryType.developerCache:
      case CleanCategoryType.systemTemp:
      case CleanCategoryType.crashLogs:
        return true;
      case CleanCategoryType.userTrash:
        return false; // Lixeira exige seleção manual consciente do usuário
    }
  }
}

/// Representa um arquivo individual identificado na varredura.
class CleanItem {
  final String path;
  final int sizeBytes;
  final CleanCategoryType categoryType;
  final DateTime lastModified;

  const CleanItem({
    required this.path,
    required this.sizeBytes,
    required this.categoryType,
    required this.lastModified,
  });
}

/// Resultado da varredura agrupado por categoria.
class CategoryScanResult {
  final CleanCategoryType categoryType;
  final List<String> pathsScanned;
  final int fileCount;
  final int totalSizeBytes;
  final List<CleanItem> items;

  const CategoryScanResult({
    required this.categoryType,
    required this.pathsScanned,
    required this.fileCount,
    required this.totalSizeBytes,
    required this.items,
  });

  String get title => categoryType.title;
  String get description => categoryType.description;
  IconData get icon => categoryType.icon;
  bool get isRecommended => categoryType.isRecommendedDefault;

  String get sizeLabel => formatBytes(totalSizeBytes);

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Relatório consolidado da varredura de disco.
class CleanScanReport {
  final List<CategoryScanResult> categories;
  final int totalBytes;
  final int totalFiles;
  final int durationMs;

  const CleanScanReport({
    required this.categories,
    required this.totalBytes,
    required this.totalFiles,
    required this.durationMs,
  });

  String get totalSizeLabel => CategoryScanResult.formatBytes(totalBytes);
  bool get isEmpty => totalBytes == 0 || totalFiles == 0;
}

/// Relatório da execução da limpeza de disco.
class CleanExecutionReport {
  final int bytesFreed;
  final int filesDeleted;
  final int errorsCount;
  final int durationMs;
  final List<CleanCategoryType> categoriesCleaned;

  const CleanExecutionReport({
    required this.bytesFreed,
    required this.filesDeleted,
    required this.errorsCount,
    required this.durationMs,
    required this.categoriesCleaned,
  });

  String get bytesFreedLabel => CategoryScanResult.formatBytes(bytesFreed);
  bool get isSuccess => filesDeleted > 0 || errorsCount == 0;
}

/// Relatório de otimização de memória RAM (Boost).
class RamBoostReport {
  final int ramUsedBeforeBytes;
  final int ramUsedAfterBytes;
  final int ramTotalBytes;
  final int bytesFreed;
  final int durationMs;
  final String methodUsed;
  final bool isSuccess;

  const RamBoostReport({
    required this.ramUsedBeforeBytes,
    required this.ramUsedAfterBytes,
    required this.ramTotalBytes,
    required this.bytesFreed,
    required this.durationMs,
    required this.methodUsed,
    required this.isSuccess,
  });

  String get bytesFreedLabel => CategoryScanResult.formatBytes(bytesFreed.abs());
  String get usedBeforeLabel => CategoryScanResult.formatBytes(ramUsedBeforeBytes);
  String get usedAfterLabel => CategoryScanResult.formatBytes(ramUsedAfterBytes);

  double get percentBefore => ramTotalBytes == 0 ? 0 : (ramUsedBeforeBytes / ramTotalBytes) * 100;
  double get percentAfter => ramTotalBytes == 0 ? 0 : (ramUsedAfterBytes / ramTotalBytes) * 100;
}
