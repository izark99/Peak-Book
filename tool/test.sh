#!/usr/bin/env bash
# Runs unit tests; extension tests need flutter_js's QuickJS shared library on Linux.
set -euo pipefail
cd "$(dirname "$0")/.."
lib=$(find "${PUB_CACHE:-$HOME/.pub-cache}" -path '*flutter_js-*/linux/shared/libquickjs_c_bridge_plugin.so' | head -1)
LIBQUICKJSC_TEST_PATH="$lib" flutter test "$@"
