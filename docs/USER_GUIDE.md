# Ultima Genomics Germline Variant Calling Pipeline - User Guide

## Overview

This Nextflow pipeline implements the Efficient DeepVariant (DV) germline variant calling workflow for Ultima Genomics sequencing data. It is adapted from the [Ultimagen healthomics-workflows](https://github.com/Ultimagen/healthomics-workflows/blob/main/workflows/efficient_dv/howto-germline-calling-efficient-dv.md).

## Pipeline Steps

1. **Scatter Intervals**: Divides the genome into smaller regions for parallel processing
2. **Convert to BED**: Converts interval files to BED format
3. **Make Examples**: Creates TFRecord examples from CRAM files for each genomic region
4. **Call Variants**: Uses the DeepVariant model to call variants from TFRecords
5. **Post Process**: Merges variant calls, applies filters, and generates final VCF/gVCF

## Quick Start

### Minimum Required Parameters

```bash
nextflow run main.nf \
  --cram /path/to/sample.cram \
  --cram_index /path/to/sample.cram.crai \
  --sample_name my_sample \
  --output_dir results/ \
  -profile docker
```

### Full Example with Custom Parameters

```bash
nextflow run main.nf \
  --cram gs://my-bucket/sample.cram \
  --cram_index gs://my-bucket/sample.cram.crai \
  --sample_name my_sample \
  --output_dir gs://my-bucket/results/ \
  --ref_fasta gs://my-refs/hg38.fasta \
  --ref_fasta_index gs://my-refs/hg38.fasta.fai \
  --ref_dict gs://my-refs/hg38.dict \
  --intervals gs://my-refs/wgs_calling_regions.interval_list \
  --scatter_count 40 \
  --make_gvcf true \
  --annotation_beds /path/to/regions1.bed,/path/to/regions2.bed \
  -profile google
```

## Input Parameters

### Required Parameters

| Parameter | Description |
|-----------|-------------|
| `--cram` | Path to input CRAM file |
| `--cram_index` | Path to CRAM index file (.crai) |

### Common Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--output_dir` | `results` | Output directory for results |
| `--sample_name` | `sample` | Sample name for output VCF |
| `--scatter_count` | `40` | Number of parallel regions |
| `--make_gvcf` | `false` | Generate gVCF output |

### Reference Files

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--ref_fasta` | Broad hg38 | Reference genome FASTA |
| `--ref_fasta_index` | Broad hg38 | Reference FASTA index (.fai) |
| `--ref_dict` | Broad hg38 | Reference dictionary (.dict) |
| `--intervals` | Broad WGS regions | Calling intervals |

### Model and Annotation

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--model_onnx` | Ultima germline v1.14 | DeepVariant ONNX model |
| `--annotation_beds` | `null` | Comma-separated BED files for annotation |
| `--dbsnp` | Broad dbSNP138 | dbSNP VCF for annotation |
| `--skip_dbsnp_annotation` | `false` | Skip dbSNP annotation (use if crashes occur) |
| `--filters_file` | `null` | Custom filters file |

### Advanced Parameters

See the main.nf file for the full list of configurable parameters including:
- make_examples parameters (base quality, mapping quality, coverage, etc.)
- call_variants parameters (GPU settings, ensemble size, etc.)
- post_process parameters (flow order, gVCF settings, etc.)

## Execution Profiles

The pipeline includes several pre-configured profiles:

### Docker (Local Execution)

```bash
nextflow run main.nf --cram sample.cram --cram_index sample.cram.crai -profile docker
```

### Singularity (HPC Clusters)

```bash
nextflow run main.nf --cram sample.cram --cram_index sample.cram.crai -profile singularity
```

### AWS Batch

```bash
# Edit nextflow.config to set your queue name and region
nextflow run main.nf --cram s3://bucket/sample.cram --cram_index s3://bucket/sample.cram.crai -profile awsbatch
```

### Google Cloud Batch

```bash
# Edit nextflow.config to set your project ID and region
nextflow run main.nf --cram gs://bucket/sample.cram --cram_index gs://bucket/sample.cram.crai -profile google
```

### GPU Acceleration

For GPU-accelerated variant calling:

```bash
# Docker with GPU
nextflow run main.nf --cram sample.cram --cram_index sample.cram.crai -profile docker,gpu

# Singularity with GPU
nextflow run main.nf --cram sample.cram --cram_index sample.cram.crai -profile singularity,singularity_gpu
```

## Output Files

The pipeline produces the following outputs in `--output_dir`:

### Main Outputs

- `{sample_name}.vcf.gz` - Final variant calls in VCF format
- `{sample_name}.g.vcf.gz` - gVCF file (if `--make_gvcf true`)

### Execution Reports

- `timeline.html` - Timeline of process execution
- `report.html` - Resource usage report
- `trace.txt` - Detailed trace of all tasks
- `dag.svg` - Directed acyclic graph of the workflow

## Resource Requirements

### Default Process Resources

| Process | CPUs | Memory | Notes |
|---------|------|--------|-------|
| SCATTER_INTERVALS | 2 | 4 GB | Fast, minimal resources |
| CONVERT_INTERVALS_TO_BED | 1 | 2 GB | Fast, minimal resources |
| MAKE_EXAMPLES | 8 | 32 GB | Parallelized across scatter regions |
| CALL_VARIANTS | 8 | 32 GB | Can use GPU acceleration |
| POST_PROCESS | 4 | 16 GB | Single task, merges all results |

You can override these in your own config file or by modifying `nextflow.config`.

## Troubleshooting

### Common Issues

**1. dbSNP annotation crashes**
- Set `--skip_dbsnp_annotation true` to disable dbSNP annotation
- This is a known issue with some ug_postproc versions

**2. Out of memory errors**
- Increase memory in `nextflow.config` for the failing process
- Reduce `--scatter_count` to process fewer regions in parallel

**3. GPU not detected**
- Ensure NVIDIA drivers are installed
- Use `-profile gpu` or `-profile singularity_gpu`
- Check that `--use_gpus 1` is set (default)

**4. File not found errors**
- Verify all input file paths are correct
- For cloud storage, ensure credentials are properly configured
- Check that index files match the data files

### Getting Help

For issues specific to:
- **Pipeline logic**: Check the [Ultimagen workflows repository](https://github.com/Ultimagen/healthomics-workflows)
- **Nextflow usage**: See [Nextflow documentation](https://nextflow.io/docs/latest/)
- **Container issues**: Verify Docker/Singularity installation and permissions

## Advanced Usage

### Custom Parameters File

Create a `params.yaml` file:

```yaml
cram: /path/to/sample.cram
cram_index: /path/to/sample.cram.crai
sample_name: my_sample
output_dir: results/
scatter_count: 60
make_gvcf: true
min_base_quality: 10
max_reads_per_region: 2000
```

Run with:
```bash
nextflow run main.nf -params-file params.yaml -profile docker
```

### Resume Failed Runs

Nextflow automatically caches completed tasks. To resume after a failure:

```bash
nextflow run main.nf --cram sample.cram --cram_index sample.cram.crai -profile docker -resume
```

### Custom Configuration

Create a custom config file `my_config.config`:

```groovy
process {
    withName: 'MAKE_EXAMPLES' {
        cpus = 16
        memory = '64 GB'
    }
    
    withName: 'CALL_VARIANTS' {
        cpus = 16
        memory = '64 GB'
        accelerator = 2  // Use 2 GPUs
    }
}
```

Run with:
```bash
nextflow run main.nf -c my_config.config --cram sample.cram --cram_index sample.cram.crai -profile docker
```

## Performance Optimization

### For Faster Execution

1. **Increase scatter count**: Use `--scatter_count 80` for more parallelization (requires more resources)
2. **Use GPU acceleration**: Add `-profile gpu` for 5-10x faster variant calling
3. **Optimize resources**: Increase CPUs/memory for MAKE_EXAMPLES and CALL_VARIANTS
4. **Use cloud executors**: AWS Batch or Google Batch can scale to hundreds of parallel tasks

### For Lower Resource Usage

1. **Decrease scatter count**: Use `--scatter_count 20` for less parallelization
2. **Reduce max reads**: Lower `--max_reads_per_region` to reduce memory usage
3. **Use local executor**: Run with `-profile standard` for single-machine execution

## Citation

If you use this pipeline, please cite:

- Ultima Genomics for the original workflow and tools
- DeepVariant: Poplin et al. (2018) doi: 10.1038/nbt.4235
- Nextflow: Di Tommaso et al. (2017) doi: 10.1038/nbt.3820
