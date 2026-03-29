# Critical Fix Applied - Channel Cardinality Issue

## Problem Identified
The pipeline was only processing **1 out of 40 shards** instead of all 40 in parallel.

### Root Cause
When passing multiple input channels to a process in Nextflow, the channels are **synchronized** (consumed together). With:
- `beds_with_id`: 40 items
- `cram_ch`, `ref_fasta_ch`, etc.: 1 item each

Nextflow consumed 1 item from each channel and stopped, running MAKE_EXAMPLES only once.

## Solution Applied

### Files Changed
1. **main.nf** - Lines 141-148
2. **modules/make_examples.nf** - Line 4

### Changes Made

#### main.nf (BEFORE)
```groovy
MAKE_EXAMPLES(
    beds_with_id,           // 40 items
    cram_ch,                // 1 item → SYNC PROBLEM
    cram_index_ch,          // 1 item
    ref_fasta_ch,           // 1 item
    ref_fasta_index_ch,     // 1 item
    ref_dict_ch             // 1 item
)
```

#### main.nf (AFTER)
```groovy
// Combine creates Cartesian product: broadcasts single files to all 40 shards
make_examples_input = beds_with_id.combine(cram_ch)
    .combine(cram_index_ch)
    .combine(ref_fasta_ch)
    .combine(ref_fasta_index_ch)
    .combine(ref_dict_ch)

MAKE_EXAMPLES(make_examples_input)
```

#### modules/make_examples.nf (BEFORE)
```groovy
input:
tuple val(shard_id), path(bed)
path cram
path cram_index
path ref_fasta
path ref_fasta_index
path ref_dict
```

#### modules/make_examples.nf (AFTER)
```groovy
input:
tuple val(shard_id), path(bed), path(cram), path(cram_index), path(ref_fasta), path(ref_fasta_index), path(ref_dict)
```

## Expected Behavior After Fix

### MAKE_EXAMPLES Process
- **Executions**: 40 parallel runs (one per shard)
- **Outputs**: 40 tfrecord files
  - `1_of_40.tfrecord.gz`
  - `2_of_40.tfrecord.gz`
  - ...
  - `40_of_40.tfrecord.gz`

### CALL_VARIANTS Process
- **Input**: All 40 tfrecord files (via `.collect()`)
- **params.ini**: Will show `numExampleFiles = 40`
- **Output**: Multiple `call_variants.*.gz` files containing all variants

### POST_PROCESS Process
- **Input**: All call_variants output files
- **Output**: Final VCF with complete variant calls

## Verification Steps

1. **Check MAKE_EXAMPLES executions**:
   ```bash
   # Should see 40 work directories
   ls -ld work/*/*/MAKE_EXAMPLES*
   ```

2. **Check tfrecord count**:
   ```bash
   # Should list 40 files
   find work -name "*.tfrecord.gz" | wc -l
   ```

3. **Check CALL_VARIANTS input**:
   ```bash
   # Find the call_variants work directory
   find work -name ".command.sh" -path "*/CALL_VARIANTS*" -exec grep "numExampleFiles" {} \;
   # Should show: numExampleFiles = 40
   ```

4. **Check params.ini**:
   ```bash
   find work -name "params.ini" -path "*/CALL_VARIANTS*" -exec cat {} \;
   # Should list exampleFile1 through exampleFile40
   ```

## Testing Command

Run a small test with reduced scatter count to verify:

```bash
cd ultima_germline_variant_calling

# Test with 5 shards instead of 40
nextflow run main.nf \
  --cram <your_cram_file> \
  --cram_index <your_cram_index> \
  --scatter_count 5 \
  --output_dir test_results \
  -resume
```

After completion, verify:
```bash
# Should show 5
find work -name "*.tfrecord.gz" -type f | wc -l

# Should show numExampleFiles = 5
find work -name "params.ini" -exec grep "numExampleFiles" {} \;
```

## Lint Status
✅ All files passed `nextflow lint` validation

## Files Modified
- `main.nf` (lines 141-148)
- `modules/make_examples.nf` (line 4)

## No Other Changes Needed
All other modules (scatter_intervals, convert_intervals_to_bed, call_variants, post_process) are correct and unchanged.
