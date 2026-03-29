# Ultima Genomics Germline Variant Calling Pipeline

This pipeline implements the Efficient DeepVariant (DV) germline variant calling workflow for Ultima Genomics sequencing data. It is a **modularized Nextflow DSL2** implementation adapted from the [Ultimagen healthomics-workflows](https://github.com/Ultimagen/healthomics-workflows/blob/main/workflows/efficient_dv/howto-germline-calling-efficient-dv.md).

## Features

✅ **Modular architecture** - Each step is a separate, reusable module  
✅ **GPU acceleration** - Optional GPU support for faster variant calling  
✅ **Cloud-ready** - Profiles for AWS Batch, Google Cloud Batch, and local execution  
✅ **Flexible configuration** - Extensive parameters for customization  
✅ **gVCF support** - Optional gVCF generation for population-scale studies  
✅ **Comprehensive reporting** - Timeline, resource usage, and execution reports  

## Pipeline Overview

The pipeline consists of five main steps:

1. **SCATTER_INTERVALS** - Divides genome into parallel regions
2. **CONVERT_INTERVALS_TO_BED** - Converts interval format for processing
3. **MAKE_EXAMPLES** - Generates TFRecord examples from aligned reads
4. **CALL_VARIANTS** - Calls variants using DeepVariant ONNX model
5. **POST_PROCESS** - Merges calls, applies filters, generates final VCF

## Quick Start

### Minimum Required Command

```bash
nextflow run main.nf \
  --cram /path/to/sample.cram \
  --cram_index /path/to/sample.cram.crai \
  --sample_name my_sample \
  --output_dir results/ \
  -profile docker
```

### With GPU Acceleration

```bash
nextflow run main.nf \
  --cram /path/to/sample.cram \
  --cram_index /path/to/sample.cram.crai \
  --sample_name my_sample \
  --output_dir results/ \
  -profile docker,gpu
```

### With gVCF Output

```bash
nextflow run main.nf \
  --cram /path/to/sample.cram \
  --cram_index /path/to/sample.cram.crai \
  --sample_name my_sample \
  --output_dir results/ \
  --make_gvcf true \
  -profile docker
```

## Output Files

The pipeline produces the following in the `results/` directory (or your specified `--output_dir`):

### Variant Calls
- `final_variants/{sample_name}.vcf.gz` - Final filtered and annotated variant calls
- `final_variants/{sample_name}.g.vcf.gz` - gVCF file (if `--make_gvcf true`)
- `raw_variants/call_variants.*.gz` - Raw variant calls directly from CALL_VARIANTS (before post-processing)

### Execution Reports
- `timeline.html` - Execution timeline visualization
- `report.html` - Resource usage and execution statistics
- `trace.txt` - Detailed task execution trace
- `dag.svg` - Workflow execution graph

## Documentation

📖 **[User Guide](docs/USER_GUIDE.md)** - Complete usage instructions, parameters, and examples  
🔧 **[Technical Documentation](docs/TECHNICAL.md)** - Architecture, development, and advanced topics  

## Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--cram` | Required | Input CRAM file |
| `--cram_index` | Required | CRAM index (.crai) |
| `--sample_name` | `sample` | Sample name for output |
| `--output_dir` | `results` | Output directory |
| `--scatter_count` | `40` | Number of parallel regions |
| `--make_gvcf` | `false` | Generate gVCF output |

See the User Guide for the complete parameter list.

## Execution Profiles

- `docker` - Local execution with Docker
- `singularity` - HPC clusters with Singularity
- `awsbatch` - AWS Batch cloud execution
- `google` - Google Cloud Batch execution
- `gpu` - Enable GPU acceleration
- `test` - Quick test with minimal resources

Combine profiles with commas: `-profile docker,gpu`

## Requirements

- Nextflow >= 25.04
- Docker or Singularity
- Optional: NVIDIA GPU with CUDA for accelerated calling

## Project Structure

```
ultima_germline_variant_calling/
├── main.nf                          # Main workflow orchestration
├── nextflow.config                  # Configuration and profiles
├── modules/                         # Individual process modules
│   ├── scatter_intervals.nf
│   ├── convert_intervals_to_bed.nf
│   ├── make_examples.nf
│   ├── call_variants.nf
│   └── post_process.nf
└── docs/
    ├── USER_GUIDE.md               # User documentation
    └── TECHNICAL.md                # Technical documentation
```

## Legacy Files

The directory contains the original monolithic implementation:
- `efficient_dv_germline.nf` - Original single-file implementation
- `efficient_dv_germline.ori.nf` - Backup of original

**For new projects, use `main.nf` which provides the modularized implementation.**

## Citation

If you use this pipeline, please cite:

- Ultima Genomics for the original workflow and tools
- DeepVariant: Poplin et al. (2018) doi: 10.1038/nbt.4235
- Nextflow: Di Tommaso et al. (2017) doi: 10.1038/nbt.3820

## License

This pipeline is adapted from the Ultimagen healthomics-workflows repository. Please refer to their licensing terms for usage restrictions.
