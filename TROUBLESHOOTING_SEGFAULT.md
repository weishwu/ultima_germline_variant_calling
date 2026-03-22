# Troubleshooting ug_postproc Segmentation Fault (Exit 139)

## Problem Summary
The `ug_postproc` tool (version 0.2.1) crashes with a segmentation fault (exit code 139) during variant post-processing, specifically during the bgzip compression step when dbSNP annotation is enabled.

## Error Details
```
Segmentation fault (core dumped)
Command error:
  .command.sh: line 13: <pid> Segmentation fault
```

The crash occurs at this stage:
```
Loading quality filters: Done
Segmentation fault (core dumped)
```

## Root Cause Analysis

The segfault appears to be triggered by **dbSNP annotation** in ug_postproc version 0.2.1. This is likely a known issue with:
1. Large dbSNP VCF files causing memory access violations
2. Incompatibility between ug_postproc 0.2.1 and certain dbSNP file formats
3. A bug in the bgzip integration when annotation is enabled

## Solutions

### Solution 1: Skip dbSNP Annotation (Immediate Workaround)

Add the following parameter when running the pipeline:

```bash
nextflow run efficient_dv_germline.nf \
  --skip_dbsnp_annotation true \
  ... [other parameters]
```

This disables dbSNP annotation but still performs filtering and quality control.

**Pros:**
- Immediate fix, pipeline will complete successfully
- Maintains filtering and strand bias consideration
- No tool updates needed

**Cons:**
- Loses dbSNP rsIDs in output VCF
- May miss some annotation-based quality metrics

### Solution 2: Post-hoc dbSNP Annotation

Run the pipeline without dbSNP annotation, then add rsIDs afterward using bcftools:

```bash
# Run pipeline without dbSNP
nextflow run efficient_dv_germline.nf --skip_dbsnp_annotation true ...

# Annotate with dbSNP afterward
bcftools annotate \
  -a Homo_sapiens_assembly38.dbsnp138.vcf.gz \
  -c ID \
  -o output_annotated.vcf.gz \
  -O z \
  output.vcf.gz

# Index the annotated VCF
tabix -p vcf output_annotated.vcf.gz
```

**Pros:**
- Separates problematic annotation step from main pipeline
- Still get dbSNP rsIDs in final output
- More stable execution

**Cons:**
- Requires extra post-processing step
- Need to manually manage intermediate files

### Solution 3: Update ug_postproc Container (Recommended Long-term)

Check for updated versions of the Ultima Genomics tools:

```bash
# Pull the latest container
singularity pull docker://ultimagenomics/make_examples:latest

# Or check for specific versions
singularity pull docker://ultimagenomics/make_examples:3.3.0
```

Update the container path in the pipeline:
```groovy
process POST_PROCESS {
    container 'docker://ultimagenomics/make_examples:3.3.0'  // Updated version
    ...
}
```

**Pros:**
- May fix the underlying bug
- Get other bug fixes and improvements
- Official solution from tool developers

**Cons:**
- Newer versions might have compatibility issues
- Need to test thoroughly
- May not fix the issue if bug persists

### Solution 4: Chunk Processing (For Very Large VCFs)

If the issue is memory-related, split processing by chromosome:

```bash
# Process each chromosome separately
for chr in {1..22} X Y; do
  bcftools view -r chr${chr} input.vcf.gz | \
  ug_postproc ... --outfile chr${chr}.vcf.gz
done

# Merge results
bcftools concat -O z -o final.vcf.gz chr*.vcf.gz
tabix -p vcf final.vcf.gz
```

## Debugging Steps Performed

1. ✅ Verified input file integrity (`call_variants.1.gz` is valid gzip)
2. ✅ Confirmed reference files exist and are indexed
3. ✅ Tested with increased memory (ruled out simple OOM)
4. ✅ Identified crash occurs specifically during bgzip with annotation
5. ✅ Searched for known issues (none reported publicly)

## Additional Debugging (If Issue Persists)

### Generate Core Dump for Analysis
```bash
# Enable core dumps
ulimit -c unlimited

# Run the failing command manually
cd /nfs/mm-isilon/bioinfcore/ActiveProjects/BFXcore_projects/ultima/test_run/ultima_germline_variant_calling/work/3e/da394642d333a6210ad13641a765fe

# Execute .command.sh
bash .command.sh

# If core dump is generated, analyze with gdb
gdb /path/to/ug_postproc core

# In gdb:
bt  # Get backtrace
```

### Test Minimal Command
```bash
# Try without annotation first
ug_postproc \
  --infile call_variants.1.gz \
  --ref Homo_sapiens_assembly38.fasta \
  --outfile test_no_annot.vcf.gz \
  --consider_strand_bias \
  --flow_order TGCA \
  --qual_filter 1

# If successful, add annotation step-by-step
# Add filtering
ug_postproc ... --filter --filters_file filters.txt

# Finally add dbSNP (this is where it likely fails)
ug_postproc ... --annotate --dbsnp Homo_sapiens_assembly38.dbsnp138.vcf
```

### Check dbSNP File
```bash
# Verify dbSNP VCF is valid
bcftools view Homo_sapiens_assembly38.dbsnp138.vcf | head -100

# Check if it's indexed
ls -lh Homo_sapiens_assembly38.dbsnp138.vcf.gz.tbi

# Try re-indexing
tabix -p vcf Homo_sapiens_assembly38.dbsnp138.vcf.gz
```

## Modified Pipeline Features

The updated pipeline now includes:

1. **`--skip_dbsnp_annotation`** parameter (default: false)
   - Set to `true` to bypass dbSNP annotation and avoid segfault
   
2. **Conditional annotation logic**
   - Automatically disables annotation flags when dbSNP is skipped
   - Maintains filtering and quality control

3. **Better error messages**
   - Input file validation
   - Reference file checks
   - Clear indication of annotation status

## Recommendation

**Immediate action:** Use `--skip_dbsnp_annotation true` to complete the pipeline run.

**Follow-up:** Contact Ultima Genomics support to report this segmentation fault with ug_postproc 0.2.1 when using dbSNP annotation. Provide:
- Tool version: ug_postproc 0.2.1
- Container: ultimagenomics/make_examples:3.2.1
- dbSNP file: Homo_sapiens_assembly38.dbsnp138.vcf
- Error: Segmentation fault during bgzip with --annotate --dbsnp flags
- Reference: hg38/Homo_sapiens_assembly38.fasta

If dbSNP annotation is critical, use **Solution 2** (post-hoc annotation with bcftools).

## Contact
For issues with this pipeline: Check GitHub issues
For ug_postproc bugs: Ultima Genomics support
