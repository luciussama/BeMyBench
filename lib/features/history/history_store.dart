import 'dart:convert';
import 'dart:io';

import 'bench_record.dart';

/// Persistência local do histórico de benchmarks.
///
/// Tudo fica em um arquivo JSON no diretório de dados do app:
/// - macOS:   ~/Library/Application Support/BeMyBench/history.json
/// - Linux:   ~/.local/share/bemybench/history.json (ou XDG_DATA_HOME)
/// - Windows: %APPDATA%\BeMyBench\history.json
///
/// Nada é enviado para fora da máquina. O diretório pode ser injetado
/// para testes.
class BenchHistoryStore {
  BenchHistoryStore({this.directory});

  final Directory? directory;

  static const _fileName = 'history.json';
  static const _tmpSuffix = '.tmp';

  Future<Directory> _dir() async {
    final injected = directory;
    if (injected != null) {
      await injected.create(recursive: true);
      return injected;
    }

    final env = Platform.environment;
    String base;
    if (Platform.isMacOS) {
      final home = env['HOME'] ?? '/tmp';
      base = '$home/Library/Application Support/BeMyBench';
    } else if (Platform.isWindows) {
      final appData = env['APPDATA'] ?? env['USERPROFILE'] ?? env['HOMEPATH'] ?? 'C:\\';
      base = '$appData\\BeMyBench';
    } else {
      final home = env['HOME'] ?? '/tmp';
      final xdg = env['XDG_DATA_HOME'];
      base = xdg != null && xdg.isNotEmpty
          ? '$xdg/bemybench'
          : '$home/.local/share/bemybench';
    }

    final dir = Directory(base);
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file() async {
    final dir = await _dir();
    final sep = Platform.isWindows ? '\\' : '/';
    return File('${dir.path}$sep$_fileName');
  }

  /// Carrega o histórico (ordenado do mais antigo para o mais novo).
  /// Arquivo corrompido/ausente resulta em lista vazia — nunca lança.
  Future<List<BenchRecord>> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return <BenchRecord>[];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return <BenchRecord>[];

      final decoded = jsonDecode(content);
      return BenchRecord.fromJsonList(decoded);
    } catch (_) {
      // Arquivo corrompido ou formato inesperado: começa do zero
      // (o arquivo continua no disco; nunca o sobrescrevemos aqui sem escrever)
      return <BenchRecord>[];
    }
  }

  /// Adiciona um registro e salva (substituição atômica via arquivo temporário).
  Future<void> append(BenchRecord record) async {
    final records = List<BenchRecord>.from(await load());
    records.add(record);
    records.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    await _write(records);
  }

  /// Remove todo o histórico.
  Future<void> clear() async {
    final file = await _file();
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<void> _write(List<BenchRecord> records) async {
    final file = await _file();
    final tmp = File('${file.path}$_tmpSuffix');
    await tmp.writeAsString(encodeHistory(records));
    await tmp.rename(file.path);
  }
}
