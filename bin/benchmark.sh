#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source bin/toolchain.sh
swift run -c release --sdk "$newton_sdk" NewtonBench
