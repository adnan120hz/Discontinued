#!/bin/bash
# build-ios.sh — WorkSlop AirLift Rust core
#
# Builds the Rust FFI static library for iOS and packages
# AirliftFFI.xcframework. Ported from AirCard-iOS (Mak5er, MIT).
#
# CI runs the equivalent steps inline (device slice only) in
# .github/workflows/main.yml before the Xcode archive. Run this script
# locally any time RustCore/ changes.
set -euo pipefail

export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-17.0}"

# Make ~/.cargo visible to non-login shells (Xcode build phases, CI)
# shellcheck disable=SC1090
source "$HOME/.cargo/env" 2>/dev/null || true

# Remap $HOME so absolute source paths don't appear in the binary's log output
export RUSTFLAGS="${RUSTFLAGS:-} --remap-path-prefix=${HOME}=/build"
export CFLAGS="${CFLAGS:-} -ffile-prefix-map=${HOME}=/build"
export TARGET_CFLAGS="${TARGET_CFLAGS:-} -ffile-prefix-map=${HOME}=/build"

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "==> Installing iOS targets (if needed)"
rustup target add aarch64-apple-ios aarch64-apple-ios-sim 2>/dev/null || true

echo "==> Building Rust static libs (release)"
cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim

echo "==> Repackaging AirliftFFI.xcframework"
rm -rf "$ROOT/AirliftFFI.xcframework"
xcodebuild -create-xcframework \
  -library "$ROOT/target/aarch64-apple-ios/release/libairlift_ffi.a" \
  -headers "$ROOT/include" \
  -library "$ROOT/target/aarch64-apple-ios-sim/release/libairlift_ffi.a" \
  -headers "$ROOT/include" \
  -output "$ROOT/AirliftFFI.xcframework"

echo "==> Done."
