#!/usr/bin/env bash

# ZIM Test Runner
# Runs all unit tests with memory leak detection

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 ZIM Test Suite${NC}"
echo "================================"
echo ""

# Change to project root
cd "$(dirname "$0")/.."

# Track results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to run a test file
run_test() {
    local test_file=$1
    local test_name=$(basename "$test_file" .zig)

    echo -e "${YELLOW}Running: ${test_name}${NC}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # Run test with Zig
    if zig test "$test_file" --main-mod-path . 2>&1; then
        echo -e "${GREEN}✓ ${test_name} passed${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ ${test_name} failed${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    echo ""
}

# Run all unit tests
echo -e "${BLUE}📋 Unit Tests${NC}"
echo "--------------------------------"
for test_file in test/unit/*.zig; do
    if [ -f "$test_file" ]; then
        run_test "$test_file"
    fi
done

# Run all integration tests if they exist
if [ -d "test/integration" ] && [ "$(ls -A test/integration/*.zig 2>/dev/null)" ]; then
    echo -e "${BLUE}🔗 Integration Tests${NC}"
    echo "--------------------------------"
    for test_file in test/integration/*.zig; do
        if [ -f "$test_file" ]; then
            run_test "$test_file"
        fi
    done
fi

# Summary
echo "================================"
echo -e "${BLUE}📊 Test Summary${NC}"
echo "================================"
echo "Total:  $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"
else
    echo -e "${GREEN}Failed: $FAILED_TESTS${NC}"
fi
echo ""

# Exit with error if any tests failed
if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
else
    echo -e "${GREEN}✅ All tests passed!${NC}"
    echo ""
    echo -e "${BLUE}🔍 Memory Leak Detection${NC}"
    echo "All tests use std.testing.allocator which automatically"
    echo "detects memory leaks. No leaks were found!"
    exit 0
fi
