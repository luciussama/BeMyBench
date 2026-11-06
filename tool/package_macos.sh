#!/usr/bin/env bash
# Compila o core Rust, builda o app macOS e embute a dylib no bundle.
#
#   ./tool/package_macos.sh [--release]
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"
export PUB_CACHE="${PUB_CACHE:-$PROJECT_ROOT/../.pub-cache}"
FLUTTER_BIN="${FLUTTER_BIN:-$PROJECT_ROOT/../flutter/bin/flutter}"
CARGO_BIN="${CARGO_BIN:-$HOME/.cargo/bin/cargo}"
MODE="${1:-debug}"
DYLIB="rust/target/release/libbemybench_core.dylib"

if command -v "$CARGO_BIN" >/dev/null 2>&1 || [[ -x "$CARGO_BIN" ]]; then
  echo "==> [1/4] Rust (release)"
  cd rust
  "$CARGO_BIN" build --release
  cd "$PROJECT_ROOT"
elif [[ -f "$DYLIB" ]]; then
  echo "==> [1/4] Usando dylib Rust já compilada: $DYLIB"
else
  echo "Erro: cargo não encontrado e dylib ausente: $DYLIB"; exit 1;
fi

[[ -f "$DYLIB" ]] || { echo "dylib não encontrada: $DYLIB"; exit 1; }

echo "==> [2/4] Flutter build macOS ($MODE)"
"$FLUTTER_BIN" build macos "--$MODE" --no-pub

APP="build/macos/Build/Products/$( [[ "$MODE" == "release" ]] && echo Release || echo Debug )/bemybench.app"
[[ -d "$APP" ]] || { echo "app não encontrado: $APP"; exit 1; }

echo "==> [3/4] Embutindo dylib em Contents/Frameworks"
mkdir -p "$APP/Contents/Frameworks"
cp "$DYLIB" "$APP/Contents/Frameworks/libbemybench_core.dylib"
codesign --force --sign - "$APP/Contents/Frameworks/libbemybench_core.dylib"

echo "==> [4/4] Assinando app e abrindo"
# Sem --deep: reassinar frameworks internos do Flutter quebra o bundle (tela preta).
codesign --force --sign - "$APP"
open "$APP"
echo "OK: $APP"
