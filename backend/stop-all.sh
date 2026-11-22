#!/usr/bin/env bash
# =============================================================================
# Stop All Backends (Backend A: 3001, Backend B: 3002)
# =============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Stopping Private Network Backend Services ==="
"$DIR/stop-a.sh"
"$DIR/stop-b.sh"
echo "=== All backend services stopped ==="
