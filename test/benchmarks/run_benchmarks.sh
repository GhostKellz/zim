#!/usr/bin/env bash

# ZIM Benchmark Runner
# Runs performance benchmarks for critical operations

set -e

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}⚡ ZIM Benchmark Suite${NC}"
echo "================================"
echo ""

# Change to project root
cd "$(dirname "$0")/../.."

# Build and run each benchmark
for bench_file in test/benchmarks/bench_*.zig; do
    if [ -f "$bench_file" ]; then
        bench_name=$(basename "$bench_file" .zig)

        echo -e "${YELLOW}Building: ${bench_name}${NC}"

        # Compile with optimizations
        zig build-exe "$bench_file" \
            --main-mod-path . \
            -O ReleaseFast \
            --name "$bench_name" \
            -femit-bin="./zig-out/bench/$bench_name"

        echo -e "${GREEN}Running: ${bench_name}${NC}"
        "./zig-out/bench/$bench_name"
        echo ""
    fi
done

echo -e "${GREEN}✅ All benchmarks complete${NC}"
echo ""
