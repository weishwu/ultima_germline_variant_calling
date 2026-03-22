#!/bin/bash
#
# Test script to isolate ug_postproc segmentation fault
#
# This script progressively adds flags to ug_postproc to identify
# which specific option combination triggers the segmentation fault.
#
# Usage:
#   ./test_ug_postproc.sh <work_directory>
#
# Where work_directory is the Nextflow work directory containing:
#   - call_variants.*.gz files
#   - Reference fasta
#   - dbSNP VCF
#   - filters.txt (if using)

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <work_directory>" >&2
    echo "" >&2
    echo "Example:" >&2
    echo "  $0 /path/to/work/3e/da394642d333a6210ad13641a765fe" >&2
    exit 1
fi

WORK_DIR="$1"

if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Directory not found: $WORK_DIR" >&2
    exit 1
fi

cd "$WORK_DIR"

# Find required files
CALLED_VARIANTS=$(ls call_variants.*.gz 2>/dev/null | head -n1)
REF_FASTA=$(ls *.fasta 2>/dev/null | head -n1)
DBSNP=$(ls *dbsnp*.vcf 2>/dev/null | head -n1)
FILTERS=$(ls filters.txt 2>/dev/null | head -n1)

if [ -z "$CALLED_VARIANTS" ]; then
    echo "ERROR: No call_variants.*.gz file found" >&2
    exit 1
fi

if [ -z "$REF_FASTA" ]; then
    echo "ERROR: No reference fasta found" >&2
    exit 1
fi

echo "===== ug_postproc Segfault Diagnostic Test ====="
echo ""
echo "Test environment:"
echo "  Work directory: $WORK_DIR"
echo "  Input variants: $CALLED_VARIANTS"
echo "  Reference: $REF_FASTA"
echo "  dbSNP: ${DBSNP:-NOT FOUND}"
echo "  Filters: ${FILTERS:-NOT FOUND}"
echo ""

# Test 1: Minimal command
echo "TEST 1: Minimal command (no annotation, no filtering)"
echo "------------------------------------------------------"
if ug_postproc \
    --infile "$CALLED_VARIANTS" \
    --ref "$REF_FASTA" \
    --outfile test1_minimal.vcf.gz \
    --flow_order TGCA 2>&1 | tee test1.log; then
    echo "✅ TEST 1 PASSED: Minimal command works"
    rm -f test1_minimal.vcf.gz test1_minimal.vcf.gz.gzi
else
    echo "❌ TEST 1 FAILED: Even minimal command fails (exit code: $?)"
    echo "This suggests a fundamental issue with ug_postproc or input files"
    exit 1
fi
echo ""

# Test 2: Add strand bias
echo "TEST 2: Add strand bias consideration"
echo "------------------------------------------------------"
if ug_postproc \
    --infile "$CALLED_VARIANTS" \
    --ref "$REF_FASTA" \
    --outfile test2_strand.vcf.gz \
    --flow_order TGCA \
    --consider_strand_bias 2>&1 | tee test2.log; then
    echo "✅ TEST 2 PASSED: Strand bias flag works"
    rm -f test2_strand.vcf.gz test2_strand.vcf.gz.gzi
else
    echo "❌ TEST 2 FAILED: --consider_strand_bias triggers failure (exit code: $?)"
    exit 1
fi
echo ""

# Test 3: Add quality filter
echo "TEST 3: Add quality filter"
echo "------------------------------------------------------"
if ug_postproc \
    --infile "$CALLED_VARIANTS" \
    --ref "$REF_FASTA" \
    --outfile test3_qual.vcf.gz \
    --flow_order TGCA \
    --consider_strand_bias \
    --qual_filter 1 2>&1 | tee test3.log; then
    echo "✅ TEST 3 PASSED: Quality filter works"
    rm -f test3_qual.vcf.gz test3_qual.vcf.gz.gzi
else
    echo "❌ TEST 3 FAILED: --qual_filter triggers failure (exit code: $?)"
    exit 1
fi
echo ""

# Test 4: Add custom filters (if available)
if [ -n "$FILTERS" ]; then
    echo "TEST 4: Add custom filters from file"
    echo "------------------------------------------------------"
    if ug_postproc \
        --infile "$CALLED_VARIANTS" \
        --ref "$REF_FASTA" \
        --outfile test4_filters.vcf.gz \
        --flow_order TGCA \
        --consider_strand_bias \
        --qual_filter 1 \
        --filter \
        --filters_file "$FILTERS" 2>&1 | tee test4.log; then
        echo "✅ TEST 4 PASSED: Custom filters work"
        rm -f test4_filters.vcf.gz test4_filters.vcf.gz.gzi
    else
        echo "❌ TEST 4 FAILED: Custom filters trigger failure (exit code: $?)"
        exit 1
    fi
    echo ""
else
    echo "TEST 4: SKIPPED (no filters.txt file)"
    echo ""
fi

# Test 5: Enable annotation WITHOUT dbSNP
echo "TEST 5: Enable annotation flag (without dbSNP)"
echo "------------------------------------------------------"
FILTERS_FLAG=""
if [ -n "$FILTERS" ]; then
    FILTERS_FLAG="--filter --filters_file $FILTERS"
fi

if ug_postproc \
    --infile "$CALLED_VARIANTS" \
    --ref "$REF_FASTA" \
    --outfile test5_annotate.vcf.gz \
    --flow_order TGCA \
    --consider_strand_bias \
    --qual_filter 1 \
    $FILTERS_FLAG \
    --annotate 2>&1 | tee test5.log; then
    echo "✅ TEST 5 PASSED: --annotate flag works without dbSNP"
    rm -f test5_annotate.vcf.gz test5_annotate.vcf.gz.gzi
else
    echo "❌ TEST 5 FAILED: --annotate triggers failure even without dbSNP (exit code: $?)"
    echo "This suggests annotation itself is broken, not just dbSNP"
    exit 1
fi
echo ""

# Test 6: Add dbSNP annotation (THE CRITICAL TEST)
if [ -n "$DBSNP" ]; then
    echo "TEST 6: Add dbSNP annotation (CRITICAL TEST)"
    echo "------------------------------------------------------"
    echo "⚠️  This is the test most likely to fail with segmentation fault"
    echo ""
    
    if timeout 120 ug_postproc \
        --infile "$CALLED_VARIANTS" \
        --ref "$REF_FASTA" \
        --outfile test6_dbsnp.vcf.gz \
        --flow_order TGCA \
        --consider_strand_bias \
        --qual_filter 1 \
        $FILTERS_FLAG \
        --annotate \
        --dbsnp "$DBSNP" 2>&1 | tee test6.log; then
        echo "✅ TEST 6 PASSED: dbSNP annotation works! (Unexpected success)"
        echo "   The segfault may be intermittent or environment-specific"
        rm -f test6_dbsnp.vcf.gz test6_dbsnp.vcf.gz.gzi
    else
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 139 ]; then
            echo "❌ TEST 6 FAILED: Segmentation fault (exit 139) - CONFIRMED"
            echo ""
            echo "DIAGNOSIS: The issue is specifically with dbSNP annotation"
        elif [ $EXIT_CODE -eq 124 ]; then
            echo "❌ TEST 6 FAILED: Timeout after 120 seconds"
            echo ""
            echo "DIAGNOSIS: Process hangs with dbSNP annotation"
        else
            echo "❌ TEST 6 FAILED: Exit code $EXIT_CODE"
        fi
        
        # Check if core dump was created
        if [ -f core ]; then
            echo ""
            echo "Core dump generated: core"
            echo "To analyze: gdb \$(which ug_postproc) core"
        fi
        
        exit 1
    fi
else
    echo "TEST 6: SKIPPED (no dbSNP file found)"
fi

echo ""
echo "===== ALL TESTS PASSED ====="
echo ""
echo "Summary:"
echo "  ✅ Basic ug_postproc functionality works"
echo "  ✅ Strand bias consideration works"
echo "  ✅ Quality filtering works"
if [ -n "$FILTERS" ]; then
    echo "  ✅ Custom filters work"
fi
echo "  ✅ Annotation flag works"
if [ -n "$DBSNP" ]; then
    echo "  ✅ dbSNP annotation works (no segfault detected)"
    echo ""
    echo "⚠️  Note: If you experienced a segfault previously, it may be:"
    echo "     - Intermittent"
    echo "     - Related to specific data characteristics"
    echo "     - Memory/environment dependent"
fi

# Cleanup
rm -f test*.log

echo ""
echo "Test complete. Check test*.log files for detailed output."
