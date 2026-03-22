#!/bin/bash
#
# Post-hoc dbSNP Annotation Script
# 
# This script adds dbSNP rsIDs to a VCF file that was processed
# without annotation due to ug_postproc segmentation fault issues.
#
# Usage:
#   ./annotate_with_dbsnp.sh input.vcf.gz dbsnp.vcf.gz output.vcf.gz
#
# Requirements:
#   - bcftools (tested with v1.19)
#   - Input VCF must be bgzipped and tabix-indexed
#   - dbSNP VCF must be bgzipped and tabix-indexed

set -euo pipefail

# Check arguments
if [ $# -ne 3 ]; then
    echo "Usage: $0 <input.vcf.gz> <dbsnp.vcf.gz> <output.vcf.gz>" >&2
    echo "" >&2
    echo "Example:" >&2
    echo "  $0 sample.vcf.gz Homo_sapiens_assembly38.dbsnp138.vcf.gz sample_annotated.vcf.gz" >&2
    exit 1
fi

INPUT_VCF="$1"
DBSNP_VCF="$2"
OUTPUT_VCF="$3"

# Check if bcftools is available
if ! command -v bcftools &> /dev/null; then
    echo "ERROR: bcftools not found. Please install bcftools." >&2
    exit 1
fi

# Check if input files exist
if [ ! -f "$INPUT_VCF" ]; then
    echo "ERROR: Input VCF not found: $INPUT_VCF" >&2
    exit 1
fi

if [ ! -f "$DBSNP_VCF" ]; then
    echo "ERROR: dbSNP VCF not found: $DBSNP_VCF" >&2
    exit 1
fi

# Check if input is indexed
if [ ! -f "${INPUT_VCF}.tbi" ]; then
    echo "WARNING: Input VCF not indexed. Creating index..." >&2
    tabix -p vcf "$INPUT_VCF"
fi

# Check if dbSNP is indexed
if [ ! -f "${DBSNP_VCF}.tbi" ]; then
    echo "WARNING: dbSNP VCF not indexed. Creating index..." >&2
    tabix -p vcf "$DBSNP_VCF"
fi

# Get version info
BCFTOOLS_VERSION=$(bcftools --version | head -n1)
echo "Using $BCFTOOLS_VERSION"

# Count variants before annotation
VARIANTS_BEFORE=$(bcftools view -H "$INPUT_VCF" | wc -l)
echo "Input VCF contains $VARIANTS_BEFORE variants"

# Perform annotation
echo "Annotating with dbSNP rsIDs..."
bcftools annotate \
    -a "$DBSNP_VCF" \
    -c ID \
    -o "$OUTPUT_VCF" \
    -O z \
    "$INPUT_VCF"

# Index output
echo "Indexing output VCF..."
tabix -p vcf "$OUTPUT_VCF"

# Count variants after annotation
VARIANTS_AFTER=$(bcftools view -H "$OUTPUT_VCF" | wc -l)
echo "Output VCF contains $VARIANTS_AFTER variants"

# Count how many got rsIDs
ANNOTATED=$(bcftools view -H "$OUTPUT_VCF" | awk '$3 ~ /^rs/' | wc -l)
PERCENT=$(awk "BEGIN {printf \"%.1f\", ($ANNOTATED/$VARIANTS_AFTER)*100}")

echo ""
echo "Annotation complete!"
echo "  Total variants: $VARIANTS_AFTER"
echo "  Annotated with rsIDs: $ANNOTATED ($PERCENT%)"
echo "  Output: $OUTPUT_VCF"
echo "  Index: ${OUTPUT_VCF}.tbi"
