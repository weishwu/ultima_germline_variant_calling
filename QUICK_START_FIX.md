# Quick Start: Fix Segmentation Fault

## Problem
Your pipeline crashes with:
```
Segmentation fault (core dumped)
Exit code: 139
```

## One-Line Fix

Add `--skip_dbsnp_annotation true` to your nextflow command.

## Example: Before (Failing)

```bash
nextflow run efficient_dv_germline.nf \
  --cram /path/to/sample.cram \
  --cram_index /path/to/sample.cram.crai \
  --ref_fasta /path/to/Homo_sapiens_assembly38.fasta \
  --ref_fasta_index /path/to/Homo_sapiens_assembly38.fasta.fai \
  --ref_dict /path/to/Homo_sapiens_assembly38.dict \
  --model_checkpoint /path/to/ultima_model \
  --output_dir results \
  --sample_name SAMPLE123
```

**Result**: ❌ Segmentation fault in POST_PROCESS step

## Example: After (Working)

```bash
nextflow run efficient_dv_germline.nf \
  --cram /path/to/sample.cram \
  --cram_index /path/to/sample.cram.crai \
  --ref_fasta /path/to/Homo_sapiens_assembly38.fasta \
  --ref_fasta_index /path/to/Homo_sapiens_assembly38.fasta.fai \
  --ref_dict /path/to/Homo_sapiens_assembly38.dict \
  --model_checkpoint /path/to/ultima_model \
  --output_dir results \
  --sample_name SAMPLE123 \
  --skip_dbsnp_annotation true    # ← ADD THIS LINE
```

**Result**: ✅ Pipeline completes successfully

## Full Working Example (Your Setup)

Based on your work directory, here's a complete command:

```bash
nextflow run efficient_dv_germline.nf \
  --cram /nfs/mm-isilon/bioinfcore/ActiveProjects/BFXcore_projects/ultima/test_run/sample.cram \
  --cram_index /nfs/mm-isilon/bioinfcore/ActiveProjects/BFXcore_projects/ultima/test_run/sample.cram.crai \
  --ref_fasta /nfs/mm-isilon/bioinfcore/ActiveProjects/BFXcore_projects/ultima/references/Homo_sapiens_assembly38.fasta \
  --ref_fasta_index /nfs/mm-isilon/bioinfcore/ActiveProjects/BFXcore_projects/ultima/references/Homo_sapiens_assembly38.fasta.fai \
  --ref_dict /nfs/mm-isilon/bioinfcore/ActiveProjects/BFXcore_projects/ultima/references/Homo_sapiens_assembly38.dict \
  --dbsnp /nfs/mm-isilon/bioinfcore/ActiveProjects/BFXcore_projects/ultima/references/Homo_sapiens_assembly38.dbsnp138.vcf \
  --model_checkpoint /nfs/mm-isilon/bioinfcore/ActiveProjects/BFXcore_projects/ultima/models/ultima_trained_model \
  --output_dir /nfs/mm-isilon/bioinfcore/ActiveProjects/BFXcore_projects/ultima/test_run/results \
  --sample_name TEST_SAMPLE \
  --skip_dbsnp_annotation true \
  -resume
```

## Optional: Add dbSNP After Pipeline Completes

If you need dbSNP rsIDs in your final VCF:

```bash
# After pipeline finishes successfully
bash scripts/annotate_with_dbsnp.sh \
  results/TEST_SAMPLE.vcf.gz \
  /path/to/Homo_sapiens_assembly38.dbsnp138.vcf.gz \
  results/TEST_SAMPLE.annotated.vcf.gz
```

This adds rsIDs without risking the segmentation fault.

## What This Fix Does

✅ **Keeps**:
- All variant calling functionality
- Quality filtering (`--qual_filter 1`)
- Strand bias consideration (`--consider_strand_bias`)
- Custom filters (`--filters_file`)
- GVCF generation (if enabled)

❌ **Skips**:
- dbSNP annotation during ug_postproc (the buggy step)

💡 **Optional add-back**:
- dbSNP rsIDs can be added later with bcftools (see above)

## Expected Output

With the fix, your pipeline will produce:

```
results/
├── TEST_SAMPLE.vcf.gz          # Main variant calls (without rsIDs)
├── TEST_SAMPLE.vcf.gz.tbi      # Index file
└── TEST_SAMPLE.g.vcf.gz        # gVCF (if --make_gvcf true)
```

After optional annotation:
```
results/
├── TEST_SAMPLE.annotated.vcf.gz     # With dbSNP rsIDs
└── TEST_SAMPLE.annotated.vcf.gz.tbi # Index
```

## Resume from Failed Run

If your pipeline already failed partway through:

```bash
# Same command as before, but add -resume
nextflow run efficient_dv_germline.nf \
  --skip_dbsnp_annotation true \
  ... [other params] \
  -resume   # ← This reuses completed work
```

Nextflow will skip successfully completed steps and only re-run from POST_PROCESS.

## Troubleshooting

### Still getting segfault?

Run the diagnostic:
```bash
bash scripts/test_ug_postproc.sh /path/to/failed/work/directory
```

### Need more details?

See comprehensive guide:
```bash
cat TROUBLESHOOTING_SEGFAULT.md
```

### Want to try a newer container?

Edit `efficient_dv_germline.nf` line 249:
```groovy
container 'docker://ultimagenomics/make_examples:latest'
```

## Summary

| Step | Command | Time |
|------|---------|------|
| 1. Run pipeline | Add `--skip_dbsnp_annotation true` | ~2-6 hours |
| 2. Add rsIDs (optional) | `bash scripts/annotate_with_dbsnp.sh ...` | ~5-10 min |

That's it! Your pipeline will now work. 🎉

For questions or issues, check `TROUBLESHOOTING_SEGFAULT.md`.
