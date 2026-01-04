#!/bin/bash
# MixOS-GO Automatic Testing Script
# Monitors build completion and runs tests automatically

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="$PROJECT_DIR/artifacts"
TESTS_DIR="$PROJECT_DIR/tests"
LOG_FILE="$PROJECT_DIR/auto-test.log"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║      MixOS-GO Automatic Test Monitor                       ║"
echo "╚════════════════════════════════════════════════════════════╝" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Check if build is running
if ! pgrep -f "make all" > /dev/null; then
    echo "⚠️  Build is not running!" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Start build with: make all" | tee -a "$LOG_FILE"
    exit 1
fi

echo "✓ Build detected (monitoring...)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Function to check if build is complete
is_build_complete() {
    if ! pgrep -f "make all" > /dev/null; then
        return 0
    fi
    return 1
}

# Monitor build
while ! is_build_complete; do
    # Show progress every 30 seconds
    sleep 30
    
    if [ -d "$ARTIFACTS" ]; then
        FILE_COUNT=$(ls -1 "$ARTIFACTS" 2>/dev/null | wc -l)
        echo "[$(date '+%H:%M:%S')] Build ongoing... ($FILE_COUNT artifacts)" | tee -a "$LOG_FILE"
    fi
done

echo "" | tee -a "$LOG_FILE"
echo "🏁 Build completed!" | tee -a "$LOG_FILE"
sleep 2

# Check build status
if [ ! -d "$ARTIFACTS" ]; then
    echo "❌ No artifacts found - build may have failed" | tee -a "$LOG_FILE"
    exit 1
fi

echo "" | tee -a "$LOG_FILE"
echo "📊 Build Artifacts:" | tee -a "$LOG_FILE"
cd "$ARTIFACTS"
ls -lh | tail -n +2 | awk '{print "   " $5 "\t" $9}' | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"
echo "════════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Determine what to test
TEST_TARGET=""

if [ -f "$ARTIFACTS/mixos.iso" ]; then
    echo "ISO image detected - testing ISO boot" | tee -a "$LOG_FILE"
    TEST_TARGET="iso"
elif [ -f "$ARTIFACTS/mixos-go-v1.0.0.viso" ]; then
    echo "VISO image detected - testing VISO boot" | tee -a "$LOG_FILE"
    TEST_TARGET="viso"
else
    echo "⚠️  No bootable images found" | tee -a "$LOG_FILE"
    echo "Available images:" | tee -a "$LOG_FILE"
    ls "$ARTIFACTS" 2>/dev/null | grep -E '\.(iso|viso|qcow2)$' | sed 's/^/   /' | tee -a "$LOG_FILE"
    exit 0
fi

echo "" | tee -a "$LOG_FILE"
echo "🧪 Running tests..." | tee -a "$LOG_FILE"
echo "════════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Run tests
if [ -f "$TESTS_DIR/run-tests.sh" ]; then
    bash "$TESTS_DIR/run-tests.sh" "$TEST_TARGET" 2>&1 | tee -a "$LOG_FILE"
    TEST_RESULT=$?
else
    echo "❌ Test runner not found: $TESTS_DIR/run-tests.sh" | tee -a "$LOG_FILE"
    exit 1
fi

echo "" | tee -a "$LOG_FILE"
echo "════════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"

if [ $TEST_RESULT -eq 0 ]; then
    echo "✅ ALL TESTS PASSED" | tee -a "$LOG_FILE"
else
    echo "❌ TESTS FAILED (code: $TEST_RESULT)" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "Log saved to: $LOG_FILE" | tee -a "$LOG_FILE"
echo "════════════════════════════════════════════════════════════" | tee -a "$LOG_FILE"

exit $TEST_RESULT
