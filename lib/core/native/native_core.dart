import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Carrega a biblioteca nativa do benchmark (Rust) e expõe as funções C ABI.
///
/// Ordem de busca:
/// 1. `--dart-define=BMB_CORE_LIB=/caminho/lib.dylib`
/// 2. variável de ambiente `BMB_CORE_LIB`
/// 3. dentro do bundle do app (Contents/Frameworks no macOS)
/// 4. fallback de desenvolvimento: `rust/target/release/...`
class NativeCore {
  NativeCore._(this._lib) {
    _version = _lib.lookupFunction<_StrFnC, _StrFnDart>('bmb_version');
    _cpu = _lib.lookupFunction<_CpuFnC, _CpuFnDart>('bmb_cpu_benchmark');
    _mem = _lib.lookupFunction<_MemFnC, _MemFnDart>('bmb_memory_benchmark');
    _free = _lib.lookupFunction<_FreeFnC, _FreeFnDart>('bmb_free_string');

    // Telemetria rápida do sistema (quando disponível)
    try {
      _sysCpu = _lib.lookupFunction<Double Function(), double Function()>('bmb_sys_cpu_usage');
    } catch (_) {
      _sysCpu = null;
    }

    try {
      _sysMem = _lib.lookupFunction<_StrFnC, _StrFnDart>('bmb_sys_memory_info');
    } catch (_) {
      _sysMem = null;
    }

    // Telemetria granular (núcleos individuais e temperatura da zona ACPI)
    try {
      _sysCpuPerCore =
          _lib.lookupFunction<_StrFnC, _StrFnDart>('bmb_sys_cpu_per_core');
    } catch (_) {
      _sysCpuPerCore = null;
    }

    try {
      _sysCpuTemp =
          _lib.lookupFunction<Double Function(), double Function()>(
        'bmb_sys_cpu_temp_c',
      );
    } catch (_) {
      _sysCpuTemp = null;
    }
  }

  static NativeCore? _instance;

  static NativeCore get instance {
    final existing = _instance;
    if (existing != null) return existing;
    final created = NativeCore._(DynamicLibrary.open(_resolvePath()));
    _instance = created;
    return created;
  }

  static bool get isAvailable {
    try {
      instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _libFileName() {
    if (Platform.isMacOS) return 'libbemybench_core.dylib';
    if (Platform.isWindows) return 'bemybench_core.dll';
    return 'libbemybench_core.so';
  }

  static List<String> _candidates() {
    final name = _libFileName();
    final list = <String>[];

    const defined = String.fromEnvironment('BMB_CORE_LIB');
    if (defined.isNotEmpty) list.add(defined);

    final env = Platform.environment['BMB_CORE_LIB'];
    if (env != null && env.isNotEmpty) list.add(env);

    final exe = File(Platform.resolvedExecutable);
    final exeDir = exe.parent;

    if (Platform.isMacOS) {
      // bemybench.app/Contents/MacOS/bemybench -> ../Frameworks/
      list.add('${exeDir.parent.path}/Frameworks/$name');
    }
    if (Platform.isLinux) {
      list.add('${exeDir.path}/lib/$name');
    }
    list.add('${exeDir.path}/$name');

    // fallback de desenvolvimento (rodando via `dart run` ou app fora do bundle)
    list.add('rust/target/release/$name');
    list.add('rust/target/debug/$name');

    return list;
  }

  static String _resolvePath() {
    final name = _libFileName();

    // No Android, o dynamic linker carrega a biblioteca nativa diretamente
    // do pacote jniLibs embutido no APK pelo nome simples.
    if (Platform.isAndroid) {
      try {
        DynamicLibrary.open(name);
        return name;
      } catch (_) {
        // Segue para os caminhos convencionais caso esteja em testes ou fora do bundle
      }
    }

    final tried = <String>[];
    for (final path in _candidates()) {
      tried.add(path);
      if (File(path).existsSync()) return path;
    }
    throw StateError(
      'Biblioteca nativa não encontrada. Tentativas:\n${tried.join('\n')}\n'
      'Compile com: cd rust && cargo build --release',
    );
  }

  final DynamicLibrary _lib;
  late final _StrFnDart _version;
  late final _CpuFnDart _cpu;
  late final _MemFnDart _mem;
  late final _FreeFnDart _free;
  late final double Function()? _sysCpu;
  late final _StrFnDart? _sysMem;
  late final _StrFnDart? _sysCpuPerCore;
  late final double Function()? _sysCpuTemp;

  String get version {
    final ptr = _version();
    try {
      return ptr.toDartString();
    } finally {
      _free(ptr);
    }
  }

  /// Uso instantâneo de CPU medido diretamente pelo kernel (0.0 a 100.0).
  double get sysCpuUsage => _sysCpu?.call() ?? 0.0;

  /// Retorna JSON de memória instantânea: `total_bytes`, `available_bytes`, `used_bytes`, `load_percent`.
  String? get sysMemoryInfo {
    final fn = _sysMem;
    if (fn == null) return null;
    final ptr = fn();
    try {
      return ptr.toDartString();
    } finally {
      _free(ptr);
    }
  }

  /// Carga instantânea por núcleo lógico (0.0 a 100.0).
  ///
  /// Vazio quando a plataforma não expõe a leitura nativa ou na primeira
  /// amostra (a taxa só existe após duas leituras).
  List<double> get sysCpuPerCore {
    final fn = _sysCpuPerCore;
    if (fn == null) return const [];
    final ptr = fn();
    try {
      final json = ptr.toDartString();
      final start = json.indexOf('[');
      final end = json.lastIndexOf(']');
      if (start < 0 || end <= start) return const [];
      final body = json.substring(start + 1, end).trim();
      if (body.isEmpty) return const [];
      return body
          .split(',')
          .map((part) => double.tryParse(part.trim()) ?? 0)
          .toList(growable: false);
    } catch (_) {
      return const [];
    } finally {
      _free(ptr);
    }
  }

  /// Temperatura da zona térmica ACPI da CPU em °C, ou `null` quando ausente.
  double? get sysCpuTempC {
    final fn = _sysCpuTemp;
    if (fn == null) return null;
    final value = fn();
    if (value.isNaN || value <= 0) return null;
    return value;
  }

  String runCpu({required int durationMs, required int threads}) {
    final ptr = _cpu(durationMs, threads);
    try {
      return ptr.toDartString();
    } finally {
      _free(ptr);
    }
  }

  String runMemory({required int sizeMb, required int chaseEntries}) {
    final ptr = _mem(sizeMb, chaseEntries);
    try {
      return ptr.toDartString();
    } finally {
      _free(ptr);
    }
  }
}

typedef _StrFnC = Pointer<Utf8> Function();
typedef _StrFnDart = Pointer<Utf8> Function();

typedef _CpuFnC = Pointer<Utf8> Function(Uint64, Uint32);
typedef _CpuFnDart = Pointer<Utf8> Function(int, int);

typedef _MemFnC = Pointer<Utf8> Function(Uint64, Uint64);
typedef _MemFnDart = Pointer<Utf8> Function(int, int);

typedef _FreeFnC = Void Function(Pointer<Utf8>);
typedef _FreeFnDart = void Function(Pointer<Utf8>);
