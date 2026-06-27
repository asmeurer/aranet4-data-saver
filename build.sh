#!/usr/bin/env bash
# Build Aranet4Logger.app.
#
# Unsets conda/pixi compiler environment variables (LD, CC, AR, NM, LDFLAGS, ...) which
# otherwise hijack Xcode's linker with a cross-compiler `ld` that rejects -Xlinker.
set -euo pipefail
cd "$(dirname "$0")"

# Regenerate the Xcode project from project.yml if xcodegen is available.
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate
fi

env -u LD -u CC -u CXX -u AR -u NM -u LDFLAGS -u LDFLAGS_LD -u CFLAGS -u CPPFLAGS \
    xcodebuild -project Aranet4Logger.xcodeproj \
    -scheme Aranet4Logger \
    -configuration Debug \
    -derivedDataPath build \
    "$@" \
    build

echo
echo "Built: $(pwd)/build/Build/Products/Debug/Aranet4Logger.app"
