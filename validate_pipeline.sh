#!/bin/bash
# Pipeline Validation Script
# Run this after pipeline execution to verify all 40 shards were processed

set -e

echo "==================================="
echo "Pipeline Validation Script"
echo "==================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCATTER_COUNT=${1:-40}

echo "Expected scatter count: $SCATTER_COUNT"
echo ""

# Check 1: MAKE_EXAMPLES executions
echo "Check 1: MAKE_EXAMPLES executions"
echo "-----------------------------------"
MAKE_EXAMPLES_COUNT=$(find work -type d -name "*MAKE_EXAMPLES*" 2>/dev/null | wc -l)
if [ "$MAKE_EXAMPLES_COUNT" -eq "$SCATTER_COUNT" ]; then
    echo -e "${GREEN}✓ PASS${NC}: Found $MAKE_EXAMPLES_COUNT MAKE_EXAMPLES work directories"
else
    echo -e "${RED}✗ FAIL${NC}: Expected $SCATTER_COUNT MAKE_EXAMPLES executions, found $MAKE_EXAMPLES_COUNT"
fi
echo ""

# Check 2: tfrecord files
echo "Check 2: tfrecord output files"
echo "-----------------------------------"
TFRECORD_COUNT=$(find work -name "*.tfrecord.gz" -not -name "*.gvcf.tfrecord.gz" 2>/dev/null | wc -l)
if [ "$TFRECORD_COUNT" -eq "$SCATTER_COUNT" ]; then
    echo -e "${GREEN}✓ PASS${NC}: Found $TFRECORD_COUNT tfrecord files"
    # List first few
    echo "Sample files:"
    find work -name "*.tfrecord.gz" -not -name "*.gvcf.tfrecord.gz" 2>/dev/null | head -5 | while read f; do
        echo "  - $(basename $f)"
    done
else
    echo -e "${RED}✗ FAIL${NC}: Expected $SCATTER_COUNT tfrecord files, found $TFRECORD_COUNT"
fi
echo ""

# Check 3: CALL_VARIANTS params.ini
echo "Check 3: CALL_VARIANTS configuration"
echo "-----------------------------------"
PARAMS_INI=$(find work -name "params.ini" -path "*/CALL_VARIANTS*" 2>/dev/null | head -1)
if [ -f "$PARAMS_INI" ]; then
    NUM_EXAMPLES=$(grep "numExampleFiles" "$PARAMS_INI" | awk -F= '{print $2}' | tr -d ' ')
    if [ "$NUM_EXAMPLES" -eq "$SCATTER_COUNT" ]; then
        echo -e "${GREEN}✓ PASS${NC}: params.ini shows numExampleFiles = $NUM_EXAMPLES"
    else
        echo -e "${RED}✗ FAIL${NC}: Expected numExampleFiles = $SCATTER_COUNT, found $NUM_EXAMPLES"
    fi
    
    # Count exampleFile entries
    EXAMPLE_FILE_COUNT=$(grep -c "^exampleFile" "$PARAMS_INI" || true)
    if [ "$EXAMPLE_FILE_COUNT" -eq "$SCATTER_COUNT" ]; then
        echo -e "${GREEN}✓ PASS${NC}: params.ini contains $EXAMPLE_FILE_COUNT exampleFile entries"
    else
        echo -e "${RED}✗ FAIL${NC}: Expected $SCATTER_COUNT exampleFile entries, found $EXAMPLE_FILE_COUNT"
    fi
    
    # Show sample entries
    echo "Sample entries from params.ini:"
    grep "^exampleFile" "$PARAMS_INI" | head -3
    echo "  ..."
    grep "^exampleFile" "$PARAMS_INI" | tail -1
else
    echo -e "${YELLOW}⚠ WARNING${NC}: params.ini not found (CALL_VARIANTS may not have run yet)"
fi
echo ""

# Check 4: CALL_VARIANTS command log
echo "Check 4: CALL_VARIANTS execution log"
echo "-----------------------------------"
CALL_VARIANTS_CMD=$(find work -name ".command.sh" -path "*/CALL_VARIANTS*" 2>/dev/null | head -1)
if [ -f "$CALL_VARIANTS_CMD" ]; then
    NUM_FILES=$(grep "numExampleFiles" "$CALL_VARIANTS_CMD" | awk -F= '{print $2}' | tr -d ' ')
    if [ "$NUM_FILES" -eq "$SCATTER_COUNT" ]; then
        echo -e "${GREEN}✓ PASS${NC}: Command script shows numExampleFiles = $NUM_FILES"
    else
        echo -e "${RED}✗ FAIL${NC}: Expected numExampleFiles = $SCATTER_COUNT, found $NUM_FILES"
    fi
    
    # Count files in for loop
    FILE_LIST_COUNT=$(grep -A1 "for f in" "$CALL_VARIANTS_CMD" | grep "\.tfrecord\.gz" | tr ' ' '\n' | grep -c "\.tfrecord\.gz" || true)
    if [ "$FILE_LIST_COUNT" -eq "$SCATTER_COUNT" ]; then
        echo -e "${GREEN}✓ PASS${NC}: Command script lists $FILE_LIST_COUNT tfrecord files"
    else
        echo -e "${YELLOW}⚠ INFO${NC}: Command script lists $FILE_LIST_COUNT tfrecord files (expected $SCATTER_COUNT)"
    fi
else
    echo -e "${YELLOW}⚠ WARNING${NC}: CALL_VARIANTS .command.sh not found"
fi
echo ""

# Check 5: Final outputs
echo "Check 5: Final outputs"
echo "-----------------------------------"
if [ -d "results/final_variants" ]; then
    VCF_COUNT=$(find results/final_variants -name "*.vcf.gz" 2>/dev/null | wc -l)
    if [ "$VCF_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: Found $VCF_COUNT final VCF file(s)"
        find results/final_variants -name "*.vcf.gz" 2>/dev/null | while read f; do
            echo "  - $(basename $f)"
        done
    else
        echo -e "${YELLOW}⚠ WARNING${NC}: No final VCF files found"
    fi
else
    echo -e "${YELLOW}⚠ WARNING${NC}: results/final_variants directory not found (pipeline may still be running)"
fi
echo ""

# Summary
echo "==================================="
echo "Validation Summary"
echo "==================================="
echo ""
echo "Expected behavior:"
echo "  - $SCATTER_COUNT parallel MAKE_EXAMPLES executions"
echo "  - $SCATTER_COUNT tfrecord files generated"
echo "  - CALL_VARIANTS processes all $SCATTER_COUNT files"
echo "  - Final VCF contains variants from all shards"
echo ""
echo "If all checks passed, the pipeline is working correctly!"
echo ""
