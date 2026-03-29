# Pipeline Flow Diagram

## Data Flow Overview

```
INPUT FILES
├── CRAM file (1x)
├── CRAM index (1x)
├── Reference FASTA (1x)
├── Reference FASTA index (1x)
├── Reference dict (1x)
├── Intervals list (1x)
└── Model ONNX (1x)

↓

SCATTER_INTERVALS
├── Input: intervals.interval_list (1x)
├── Process: Split into scatter_count parts
└── Output: 40 interval_list files
    ├── scattered_1.interval_list
    ├── scattered_2.interval_list
    ├── ...
    └── scattered_40.interval_list

↓

CONVERT_INTERVALS_TO_BED (40 parallel)
├── Input: Each interval_list file
├── Process: Convert to BED format
└── Output: 40 BED files
    ├── scattered_1.bed
    ├── scattered_2.bed
    ├── ...
    └── scattered_40.bed

↓

MAKE_EXAMPLES (40 parallel) ✅ FIXED
├── Input (per instance):
│   ├── [shard_id, BED file]  → unique per shard
│   ├── CRAM file             → broadcast via .combine()
│   ├── CRAM index            → broadcast via .combine()
│   ├── Reference FASTA       → broadcast via .combine()
│   ├── Reference FASTA index → broadcast via .combine()
│   └── Reference dict        → broadcast via .combine()
├── Process: Generate variant examples for each genomic region
└── Output (per instance):
    ├── {shard_id}.tfrecord.gz (40 total)
    └── {shard_id}.gvcf.tfrecord.gz (40 total, if --make_gvcf)

↓

CALL_VARIANTS (1x, collects all 40)
├── Input:
│   ├── All 40 tfrecord files (.collect())
│   └── Model ONNX (1x)
├── Process: Deep learning inference on all examples
└── Output: call_variants.*.gz files (variable number)

↓

POST_PROCESS (1x)
├── Input:
│   ├── All call_variants.*.gz files (.collect())
│   ├── All gvcf tfrecords (40, if --make_gvcf)
│   ├── Reference FASTA
│   ├── Reference FASTA index
│   ├── Reference dict
│   ├── Annotation BED files (optional)
│   ├── dbSNP VCF (optional)
│   └── Filters file (optional)
├── Process: 
│   ├── Resolve multi-allelic variants
│   ├── Annotate variants
│   ├── Filter variants
│   └── Generate final VCF
└── Output:
    ├── {sample_name}.vcf.gz
    └── {sample_name}.g.vcf.gz (if --make_gvcf)
```

## Channel Operations Explained

### Critical Fix: .combine() Operator

**Problem**: Multiple input channels with different cardinalities
- beds_with_id: 40 tuples
- cram_ch: 1 file
- ref_fasta_ch: 1 file

**Without .combine()**: Nextflow synchronizes channels
- Takes 1 item from beds_with_id
- Takes 1 item from cram_ch
- Stops (no more items in cram_ch)
- Result: Only 1 MAKE_EXAMPLES execution

**With .combine()**: Creates Cartesian product
- beds_with_id.combine(cram_ch) → 40 tuples with cram added to each
- .combine(cram_index_ch) → 40 tuples with cram_index added
- Result: 40 MAKE_EXAMPLES executions (parallel)

### Channel Cardinality at Each Stage

| Stage | Input Cardinality | Output Cardinality |
|-------|-------------------|-------------------|
| SCATTER_INTERVALS | 1 | 40 |
| CONVERT_INTERVALS_TO_BED | 40 | 40 |
| MAKE_EXAMPLES | 40 | 40 (tfrecord) + 40 (gvcf) |
| CALL_VARIANTS | 40 → 1 (.collect()) | 1 (multiple files) |
| POST_PROCESS | 1 | 1 |

## Parameter Flow

### Scatter Count (params.scatter_count = 40)
Controls parallelization level:
- SCATTER_INTERVALS: Splits into 40 parts
- MAKE_EXAMPLES: Runs 40 times in parallel
- CALL_VARIANTS: Processes 40 tfrecord files

### GVCF Generation (params.make_gvcf)
- `false` (default): Only VCF output
- `true`: Also generates gVCF
  - MAKE_EXAMPLES: Outputs gvcf.tfrecord.gz files
  - POST_PROCESS: Uses gvcf tfrecords to generate g.vcf.gz

### Annotation (params.annotation_beds, params.dbsnp)
- If provided: POST_PROCESS annotates variants
- If null/NO_FILE: Skips annotation

## Process Resource Requirements

### MAKE_EXAMPLES (40 parallel)
- CPU: Multi-core (1 thread per instance)
- Memory: ~2 GB per thread
- Storage: Large (optional realigned SAM files)

### CALL_VARIANTS (1x GPU)
- GPU: 1x (P100 or V100)
- CPU: Multi-core for decompression
- Memory: 8 GB + 1 GB per decompression thread

### POST_PROCESS (1x CPU)
- CPU: Single thread
- Memory: 8 GB
- Storage: Moderate

## publishDir Targets

| Process | Output Directory | Pattern |
|---------|-----------------|---------|
| CALL_VARIANTS | results/raw_variants | call_variants.*.gz |
| POST_PROCESS | results/final_variants | *.vcf.gz, *.g.vcf.gz |
