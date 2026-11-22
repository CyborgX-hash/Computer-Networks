#!/usr/bin/env bash
# =============================================================================
# Start All Backends (Backend A: 3001, Backend B: 3002)
# =============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Starting Private Network Backend Services ==="
"$DIR/start-a.sh"
"$DIR/start-b.sh"
echo "=== All backend services successfully initiated ==="
"$DIR/health-check.sh"
