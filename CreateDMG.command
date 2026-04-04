#!/bin/bash
set -uo pipefail

cd "$(dirname "$0")" || exit 1
./scripts/create_dmg.sh

echo ""
echo "Press Enter to close."
read -r _
