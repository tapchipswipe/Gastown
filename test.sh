#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source bin/toolchain.sh
newton_testing_plugin="$(xcrun --find swiftc)"
newton_testing_plugin="$(dirname "$newton_testing_plugin")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
newton_test_flags=()
# Some preview CLTs ship Testing but omit its macro from swiftbuild discovery.
if [[ -f "$newton_testing_plugin" ]]; then
    newton_test_flags=(-Xswiftc -load-plugin-library -Xswiftc "$newton_testing_plugin")
fi
# Tests never read provider sessions, user Git configuration or a persistent HOME.
newton_test_home="$(mktemp -d "${TMPDIR:-/tmp}/newton-test-home.XXXXXX")"
trap 'rm -rf "$newton_test_home"' EXIT
export HOME="$newton_test_home"
export CODEX_HOME="$newton_test_home/.codex"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
swift test --sdk "$newton_sdk" --disable-xctest "${newton_test_flags[@]}"
python3 -B -m unittest discover -s Tests/ToolingTests -v
