#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE_DIR"

mkdir -p tools/data_raw
mkdir -p assets/db
mkdir -p assets/licenses

echo "Created: $BASE_DIR/tools/data_raw"
echo "Created: $BASE_DIR/assets/db"
echo "Created: $BASE_DIR/assets/licenses"
