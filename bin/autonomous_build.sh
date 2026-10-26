#!/bin/bash
# Legacy filename retained for compatibility. No scheduler or provider invocation.
set -euo pipefail
cd "$(dirname "$0")/.."
echo "Newton test helper — unattended AI execution is disabled."
./test.sh
