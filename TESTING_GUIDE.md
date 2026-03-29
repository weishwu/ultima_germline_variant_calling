# Testing Guide - Verification of Fix

## Quick Test (Recommended First)

Test with a **small scatter count** to verify the fix works quickly:

```bash
cd ultima_germline_variant_calling

# Test with 5 shards (completes much faster than 40)
nextflow run main.nf \
  --cram <your_cram_file> \
  --cram_index <your_cram_index> \
  --scatter_count 5 \
  --output_dir test_results_5 \
  -resume

# Validate results
./validate_pipeline.sh 5
```

**Expected output from validation script:**
```
✓ PASS: Found 5 MAKE_EXAMPLES work directories
✓ PASS: Found 5 tfrecord files
✓ PASS: params.ini shows numExampleFiles = 5
✓ PASS: params.ini contains 5 exampleFile entries
✓ PASS: Command script shows numExampleFiles = 5
```

## Full Test (Production Run)

Once the quick test passes, run with full scatter count:

```bash
nextflow run main.nf \
  --cram <your_cram_file> \
  --cram_index <your_cram_index> \
  --scatter_count 40 \
  --output_dir results \
  -resume

# Validate
./validate_pipeline.sh 40
```

## Manual Verification Steps

### Step 1: Check MAKE_EXAMPLES Parallel Execution

```bash
# Should show 40 directories (or your scatter_count)
find work -type d -name "*MAKE_EXAMPLES*" | wc -l

# View execution timeline
# All MAKE_EXAMPLES tasks should run in parallel, not sequentially
```

### Step 2: Check tfrecord Files

```bash
# Count tfrecord files
find work -name "*.tfrecord.gz" -not -name "*.gvcf.tfrecord.gz" | wc -l

# List them (should see shard IDs: 1, 2, 3, ..., 40)
find work -name "*.tfrecord.gz" -not -name "*.gvcf.tfrecord.gz" -exec basename {} \; | sort
```

**Expected output:**
```
1_of_40.tfrecord.gz
2_of_40.tfrecord.gz
3_of_40.tfrecord.gz
...
40_of_40.tfrecord.gz
```

### Step 3: Inspect CALL_VARIANTS Input

```bash
# Find the CALL_VARIANTS work directory
CALL_VAR_DIR=$(find work -type d -name "*CALL_VARIANTS*" | head -1)

# View the generated params.ini
cat $CALL_VAR_DIR/params.ini
```

**Expected content (key sections):**
```ini
[general]
...
numExampleFiles = 40

exampleFile1 = 1_of_40.tfrecord.gz
exampleFile2 = 2_of_40.tfrecord.gz
exampleFile3 = 3_of_40.tfrecord.gz
...
exampleFile40 = 40_of_40.tfrecord.gz
```

### Step 4: Check Nextflow Execution Report

```bash
# After pipeline completes, view the execution report
# Look for MAKE_EXAMPLES tasks - should see 40 tasks, not 1

# If you ran with -with-report report.html
open report.html  # or xdg-open on Linux
```

In the report, check:
- **Process MAKE_EXAMPLES**: Should show 40 tasks
- **Process CALL_VARIANTS**: Should show 1 task
- **Process POST_PROCESS**: Should show 1 task

### Step 5: Verify Final Output

```bash
# Check final VCF exists
ls -lh results/final_variants/*.vcf.gz

# Quick stats on the VCF
zcat results/final_variants/*.vcf.gz | grep -v "^#" | wc -l
```

## Common Issues and Solutions

### Issue 1: Still Only 1 MAKE_EXAMPLES Execution

**Diagnosis:**
```bash
find work -type d -name "*MAKE_EXAMPLES*" | wc -l
# Returns: 1 (WRONG)
```

**Solution:**
- Verify you pulled the latest changes
- Check that `main.nf` contains `.combine()` operators
- Ensure `modules/make_examples.nf` has the tuple input format

### Issue 2: params.ini Shows numExampleFiles = 1

**Diagnosis:**
```bash
grep numExampleFiles work/*/CALL_VARIANTS*/params.ini
# Returns: numExampleFiles = 1 (WRONG)
```

**Solution:**
- MAKE_EXAMPLES is still only running once
- Check the .combine() fix is applied correctly
- Use `-resume` to avoid re-running already cached processes

### Issue 3: Different Scatter Count

If you need a different number of shards:

```bash
# For 10 shards
nextflow run main.nf \
  --scatter_count 10 \
  ...

# Validate with matching count
./validate_pipeline.sh 10
```

## Benchmarking

### Expected Timeline (40 shards, WGS)

| Stage | Duration | Parallelization |
|-------|----------|-----------------|
| SCATTER_INTERVALS | 1-2 min | 1x |
| CONVERT_INTERVALS_TO_BED | 1-2 min | 40x parallel |
| MAKE_EXAMPLES | 30-60 min | 40x parallel |
| CALL_VARIANTS | 20-40 min | 1x (GPU) |
| POST_PROCESS | 10-20 min | 1x |
| **Total** | **~60-120 min** | |

### Resource Usage

**MAKE_EXAMPLES (per task):**
- CPU: 1 core
- Memory: ~2 GB
- Disk: Variable (large if saving realigned SAM)

**CALL_VARIANTS:**
- GPU: 1x P100/V100
- CPU: 8+ cores (for decompression)
- Memory: ~16 GB (8 + 1 per thread)

**POST_PROCESS:**
- CPU: 1 core
- Memory: 8 GB

## Success Criteria

The fix is successful if:

✅ MAKE_EXAMPLES runs **scatter_count times in parallel** (not once)
✅ **scatter_count tfrecord files** are generated
✅ CALL_VARIANTS receives **all scatter_count files** (check params.ini)
✅ Final VCF is generated and contains variants
✅ All validation checks pass

## Next Steps After Verification

1. **If test passes**: Run full production pipeline with scatter_count=40
2. **If test fails**: Check the troubleshooting section or report specific errors
3. **Performance tuning**: Adjust scatter_count based on your resources
4. **Integration**: Integrate into your production workflow

## Reporting Issues

If you encounter problems, please provide:

1. Output of `./validate_pipeline.sh <scatter_count>`
2. Contents of params.ini from CALL_VARIANTS work directory
3. Count of MAKE_EXAMPLES executions
4. Any error messages from Nextflow logs

---

**Time estimate to verify fix:**
- Quick test (5 shards): ~10-15 minutes
- Full test (40 shards): ~1-2 hours

Good luck! The fix has been applied and tested with `nextflow lint`.
