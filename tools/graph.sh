#!/usr/bin/env bash
# Code graph: who uses a class or autoload, and what it uses. Usage: tools/graph.sh [Name ...] (see tools/graph.py).
cd "$(dirname "$0")/.." && exec python3 tools/graph.py "$@"
