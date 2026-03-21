# Efficient DV Germline Variant Calling Pipeline

Nextflow implementation of the Efficient DV germline variant calling workflow from Ultimagen.

**Based on:** [howto-germline-calling-efficient-dv.md](https://github.com/Ultimagen/healthomics-workflows/blob/main/workflows/efficient_dv/howto-germline-calling-efficient-dv.md)

## Quick Start

```bash
nextflow run efficient_dv_germline.nf \
    --cram sample.cram \
    --cram_index sample.cram.crai \
    --sample_name my_sample \
    --output_dir results
```

## Required Parameters

- `--cram`: Input CRAM file (aligned, sorted, duplicate-marked)
- `--cram_index`: CRAM index file (.crai)

## Optional Parameters

### Input/Output
- `--output_dir`: Output directory (default: "results")
- `--sample_name`: Sample name for output files (default: "sample")

### Reference Files (defaults to hg38)
- `--ref_fasta`: Reference FASTA
- `--ref_fasta_index`: Reference FASTA index
- `--ref_dict`: Reference dictionary
- `--intervals`: Calling regions interval list

### Model
- `--model_onnx`: DeepVariant model in ONNX format (default: v1.14 germline model)

### Annotation
- `--annotation_beds`: Comma-separated list of BED files for annotation
- `--dbsnp`: dbSNP VCF for annotation
- `--filters_file`: File with JEXL filter expressions

### Pipeline Parameters
- `--scatter_count`: Number of genomic intervals to scatter (default: 40)
- `--make_gvcf`: Produce gVCF output (default: false)

### Pangenome Support
- `--pangenome_haps`: CRAM file with pangenome-derived haplotypes (optional)

## Example: With gVCF Output

```bash
nextflow run efficient_dv_germline.nf \
    --cram sample.cram \
    --cram_index sample.cram.crai \
    --sample_name my_sample \
    --make_gvcf true \
    --output_dir results
```

## Example: With Pangenome Haplotypes

```bash
nextflow run efficient_dv_germline.nf \
    --cram sample.cram \
    --cram_index sample.cram.crai \
    --pangenome_haps haplotypes.cram \
    --model_onnx gs://concordanz/deepvariant/model/germline/v1.15/germline-pangenome-ramp-9003772_shuffle_haplotypes_best.onnx \
    --sample_name my_sample \
    --output_dir results
```

## Outputs

- `{sample_name}.vcf.gz`: Filtered variant calls
- `{sample_name}.g.vcf.gz`: Genomic VCF (if `--make_gvcf` is enabled)

## Requirements

- Nextflow 25.04+
- Docker or Singularity
- GPU for call_variants step (nvidia-p100 or nvidia-v100)
