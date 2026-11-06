import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Detecta OS + tipo de input (touch vs mouse/teclado).
///
/// No Flutter, `HardwareKeyboard` / gesture recognizers não expõem touch
/// direto de forma simples; a heurística aqui combina:
/// - Platform (macOS/Windows/Linux/Android/iOS)
/// - `SystemChannels` via `ServicesBinding` não tem API pública de touchscreen,
///   então fallback: doravante tentará ler via MethodChannel nativo (`bemybench/platform`)
///   quando implementado. Por enquanto retorna `true` para Android/iOS e um cache
///   heurístico para desktop (aguarda implementação nativa).
class PlatformDetector {
  static String get os {
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'unknown';
  }

  /// Cache para leitura síncrona no build (tema). O valor async real vem de
  /// [_isTouchscreenAsync] e alimenta este campo na inicialização.
  static bool? _cachedTouch;

  static bool get isTouchscreenKnown => _cachedTouch ?? false;

  /// Chamado no startup (main) para popular o cache antes do primeiro build.
  static Future<void> init() async {
    _cachedTouch = await _isTouchscreenAsync();
  }

  static Future<bool> _isTouchscreenAsync() async {
    // Android/iOS são sempre touch-capable.
    if (Platform.isAndroid || Platform.isIOS) return true;

    // Desktop: tenta MethodChannel nativo (a ser implementado).
    // Se falhar, assume false (app padrão, não touch).
    try {
      const channel = MethodChannel('bemybench/platform');
      final result = await channel.invokeMethod<bool>('hasTouchscreen');
      if (result != null) return result;
    } catch (_) {
      // channel não implementado ainda — segue para heurística
    }

    // Heurística conservadora desktop: false.
    return false;
  }

  /// Versão síncrona para tema: usa cache (se null, assuming false).
  static bool isTouchscreen() => _cachedTouch ?? false;

  /// Indica se a plataforma atual suporta processos de ajustes do sistema
  /// (Atualização de pacotes, varredura de drivers e diagnóstico de hardware).
  /// Disponível estritamente para Windows e Linux. Em outras plataformas (macOS, Android, etc.)
  /// o recurso é completamente omitido sem disclaimers.
  ///
  /// Para testes visuais da tela em desenvolvimento no macOS:
  /// `--dart-define=ENABLE_SYSTEM_TWEAKS_PREVIEW=true`
  static bool get supportsSystemTweaks =>
      Platform.isWindows ||
      Platform.isLinux ||
      const bool.fromEnvironment('ENABLE_SYSTEM_TWEAKS_PREVIEW', defaultValue: false);

  /// Verifica se houve um pointer de tipo touch na sessão atual de gestos.
  /// (Uso futuro: alternar tema em runtime se usuário tocar com dedo em laptop touch.)
  static bool isTouchPointer(PointerDownEvent event) {
    return event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.stylus;
  }
}
