#!/bin/bash

# Flow Test Runner Script
# Runs each test file individually to avoid contract persistence issues

echo "Running Flow tests individually..."
echo "================================"

# Track overall test status
ALL_PASSED=true

# Run each test file
for test in cadence/tests/*.cdc; do
    if [[ -f "$test" ]]; then
        echo -e "\n📝 Running: $test"
        
        # Clear Flow cache before each test
        rm -rf ~/.flow 2>/dev/null
        
        if flow test "$test"; then
            echo "✅ PASSED: $test"
        else
            echo "❌ FAILED: $test"
            ALL_PASSED=false
        fi
    fi
done

echo -e "\n================================"
if $ALL_PASSED; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed!"
    exit 1
fi 