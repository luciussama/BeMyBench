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

    if (Platform.isMacOS) {
      // caminho absoluto do projeto (apenas conveniência de dev)
      list.add('$HOME/repos/BeMyBench/rust/target/release/$name');
    }
    return list;
  }

  static String _resolvePath() {
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

  String get version {
    final ptr = _version();
    try {
      return ptr.toDartString();
    } finally {
      _free(ptr);
    }
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
