# Technical Documentation

## Architecture Overview

This pipeline is built using Nextflow DSL2 with a modular architecture. Each major step is implemented as a separate module for maintainability and reusability.

## Directory Structure

```
ultima_germline_variant_calling/
├── main.nf                          # Main workflow orchestration
├── nextflow.config                  # Configuration and profiles
├── modules/                         # Individual process modules
│   ├── scatter_intervals.nf         # Genome interval scattering
│   ├── convert_intervals_to_bed.nf  # Interval to BED conversion
│   ├── make_examples.nf             # TFRecord generation
│   ├── call_variants.nf             # Variant calling with DV
│   └── post_process.nf              # VCF merging and filtering
└── docs/
    ├── USER_GUIDE.md               # User documentation
    └── TECHNICAL.md                # This file
```

## Module Details

### 1. SCATTER_INTERVALS

**Purpose**: Divides the genome into smaller regions for parallel processing.

**Container**: `broadinstitute/gatk:latest`

**Inputs**:
- `intervals`: Interval list file (Picard format)

**Outputs**:
- Multiple interval files (one per scatter)

**Implementation**:
```groovy
gatk SplitIntervals \
    -R ${ref_fasta} \
    -L ${intervals} \
    --scatter-count ${params.scatter_count} \
    -O scattered_intervals
```

**Key Parameters**:
- `scatter_count`: Number of parallel regions (default: 40)

### 2. CONVERT_INTERVALS_TO_BED

**Purpose**: Converts Picard interval format to BED format required by make_examples.

**Container**: `broadinstitute/gatk:latest`

**Inputs**:
- `interval_file`: Picard interval file

**Outputs**:
- BED file with same basename

**Implementation**:
```groovy
gatk IntervalListToBed \
    -I ${interval_file} \
    -O ${bed_file}
```

### 3. MAKE_EXAMPLES

**Purpose**: Generates TFRecord examples from aligned reads for DeepVariant.

**Container**: `ultimagenomics/make_examples:3.2.1`

**Inputs**:
- `bed_with_id`: Tuple of [shard_id, bed_file]
- `cram`: CRAM file
- `cram_index`: CRAM index
- `ref_fasta`: Reference genome
- `ref_fasta_index`: Reference index
- `ref_dict`: Reference dictionary

**Outputs**:
- `tfrecord`: TFRecord files for variant calling
- `gvcf_tfrecord`: TFRecord files for gVCF generation (optional)

**Key Parameters**:
- `min_base_quality`: Minimum base quality (default: 5)
- `min_mapq`: Minimum mapping quality (default: 5)
- `max_reads_per_region`: Max reads to process (default: 1500)
- `optimal_coverages`: Target coverage normalization (default: 50)
- `add_ins_size_channel`: Add insert size channel (default: true)

**Conditional Logic**:
- gVCF generation enabled with `--make_gvcf true`
- Insert size channel added with `--add_ins_size_channel true`

### 4. CALL_VARIANTS

**Purpose**: Calls variants using the DeepVariant ONNX model.

**Container**: `ultimagenomics/call_variants:3.0.0`

**Inputs**:
- `tfrecords`: All TFRecord files (collected)
- `model_onnx`: DeepVariant model file

**Outputs**:
- Multiple compressed variant call files

**Implementation**:
- Generates INI configuration file dynamically
- Processes all TFRecords in parallel
- Supports GPU acceleration

**Key Parameters**:
- `use_gpus`: Enable GPU (default: 1)
- `gpu_id`: GPU device ID (default: 0)
- `num_infer_threads_per_gpu`: Inference threads (default: 2)
- `ensemble_size`: Ensemble size for averaging (default: 7)
- `trt_workspace_size_mb`: TensorRT workspace (default: 2000 MB)

**GPU Configuration**:
- Docker: Use `-profile gpu` with `--gpus all`
- Singularity: Use `-profile singularity_gpu` with `--nv`

### 5. POST_PROCESS

**Purpose**: Merges variant calls, applies filters, and generates final VCF/gVCF.

**Container**: `ultimagenomics/make_examples:3.2.1`

**Inputs**:
- `called_variants`: All variant call files (collected)
- `gvcf_tfrecords`: TFRecords for gVCF (optional)
- Reference files (fasta, index, dict)
- `annotation_beds`: BED files for annotation (optional)
- `dbsnp`: dbSNP VCF (optional)
- `filters_file`: Custom filters (optional)

**Outputs**:
- `vcf`: Final VCF file
- `gvcf`: gVCF file (optional)

**Key Parameters**:
- `flow_order`: Flow order for Ultima data (default: "TGCA")
- `make_gvcf`: Enable gVCF output (default: false)
- `gq_resolution`: GQ resolution for gVCF (optional)
- `skip_dbsnp_annotation`: Skip dbSNP (default: false)

**Conditional Logic**:
- Annotation enabled if BED files or dbSNP provided
- Filtering enabled if filters_file provided
- gVCF generation enabled with `--make_gvcf true`

## Channel Flow

```
intervals_ch
    ↓
SCATTER_INTERVALS
    ↓ (multiple scattered intervals)
CONVERT_INTERVALS_TO_BED
    ↓ (BED files with shard IDs)
MAKE_EXAMPLES (parallel)
    ↓ (TFRecords from all shards)
    ↓ collect()
CALL_VARIANTS
    ↓ (variant calls)
    ↓ collect()
POST_PROCESS
    ↓
Final VCF/gVCF
```

## Data Dependencies

### Channel Transformations

1. **Scattering**:
```groovy
SCATTER_INTERVALS.out.intervals
    .flatten()  // Unpack list to individual files
    .map { file -> 
        def shard_id = file.baseName.replaceAll('scattered_', '')
        [shard_id, file]  // Create [id, file] tuple
    }
```

2. **Collection**:
```groovy
MAKE_EXAMPLES.out.tfrecord.collect()  // Wait for all shards
```

3. **Optional Files**:
```groovy
annotation_beds_ch = params.annotation_beds ? 
    channel.fromPath(params.annotation_beds.tokenize(','), checkIfExists: true).collect() : 
    channel.value(file('NO_FILE_ANNOTATION'))
```

## Parameter Inheritance

Parameters are defined in three layers:

1. **Default values** in `main.nf`
2. **Profile overrides** in `nextflow.config`
3. **Command-line overrides** via `--param value`

Command-line parameters take precedence over all others.

## Error Handling

### Retry Strategy

Default: 2 retries for all processes
```groovy
process {
    errorStrategy = 'retry'
    maxRetries = 2
}
```

### Common Failure Modes

1. **Out of Memory**:
   - Increase process memory in config
   - Reduce `--max_reads_per_region`
   - Decrease `--scatter_count`

2. **GPU Errors**:
   - Verify GPU availability
   - Reduce `--num_infer_threads_per_gpu`
   - Decrease `--trt_workspace_size_mb`

3. **dbSNP Annotation Crashes**:
   - Set `--skip_dbsnp_annotation true`
   - Known issue with some ug_postproc versions

## Performance Tuning

### Parallelization

The pipeline parallelizes at two levels:

1. **Scatter-based**: Multiple regions processed simultaneously
   - Controlled by `--scatter_count`
   - Higher = more parallelism, more resources needed

2. **Within-process**: Threading within each process
   - MAKE_EXAMPLES: 8 CPUs default
   - CALL_VARIANTS: 8 CPUs + GPU optional

### Bottlenecks

1. **MAKE_EXAMPLES**: I/O bound, scales well with scatter count
2. **CALL_VARIANTS**: Compute bound, benefits from GPU acceleration
3. **POST_PROCESS**: Single task, cannot be parallelized

### Recommendations

- **Small genomes/exomes**: `scatter_count = 20`
- **Whole genomes**: `scatter_count = 40-80`
- **High-coverage WGS**: Use GPU acceleration

## Container Images

All containers are official Ultima Genomics Docker images:

- **make_examples**: `ultimagenomics/make_examples:3.2.1`
  - Used for: MAKE_EXAMPLES, POST_PROCESS
  - Tools: make_examples_ultima, ug_postproc

- **call_variants**: `ultimagenomics/call_variants:3.0.0`
  - Used for: CALL_VARIANTS
  - Tools: call_variants
  - GPU support: CUDA/TensorRT

- **GATK**: `broadinstitute/gatk:latest`
  - Used for: SCATTER_INTERVALS, CONVERT_INTERVALS_TO_BED
  - Tools: SplitIntervals, IntervalListToBed

## Testing

### Quick Test

Use the `test` profile for rapid validation:

```bash
nextflow run main.nf \
  --cram test_data/small.cram \
  --cram_index test_data/small.cram.crai \
  -profile docker,test
```

The test profile reduces:
- `scatter_count` to 2
- Memory to 4 GB per process
- CPUs to 2 per process

### Integration Testing

For full pipeline testing:
1. Use a small chromosome (e.g., chr22)
2. Set appropriate intervals file
3. Verify all outputs are generated
4. Check execution reports

## Extension Points

### Adding New Processes

1. Create module in `modules/my_process.nf`
2. Define process with inputs/outputs
3. Add `include` statement to `main.nf`
4. Wire into workflow block
5. Add configuration to `nextflow.config`

### Custom Annotations

To add custom annotation:
1. Prepare BED files with desired regions
2. Pass via `--annotation_beds file1.bed,file2.bed`
3. Annotations appear in INFO field of output VCF

### Alternative Models

To use a different DeepVariant model:
1. Obtain ONNX model file
2. Pass via `--model_onnx /path/to/model.onnx`
3. Ensure model is compatible with call_variants version

## Monitoring and Debugging

### Execution Reports

Nextflow generates several reports:

- **timeline.html**: Visual timeline of all tasks
- **report.html**: Resource usage statistics
- **trace.txt**: Complete execution trace
- **dag.svg**: Workflow dependency graph

### Log Files

Individual process logs:
```
work/
└── [hash]/
    ├── .command.sh    # Script executed
    ├── .command.out   # stdout
    ├── .command.err   # stderr
    ├── .command.log   # Combined output
    └── .exitcode      # Exit code
```

### Debugging Failed Tasks

1. Find failed task in trace or timeline
2. Navigate to work directory
3. Examine `.command.err` for errors
4. Re-run command manually if needed:
   ```bash
   cd work/[hash]
   bash .command.sh
   ```

## Cloud Deployment

### AWS Batch

Requirements:
- Configured AWS Batch queue
- S3 bucket for work directory
- ECR or Docker Hub for containers

Configuration in `nextflow.config`:
```groovy
awsbatch {
    process.executor = 'awsbatch'
    process.queue = 'your-batch-queue'
    aws.region = 'us-east-1'
}
```

### Google Cloud Batch

Requirements:
- Google Cloud project with Batch API enabled
- GCS bucket for work directory
- Container Registry or Docker Hub

Configuration in `nextflow.config`:
```groovy
google {
    process.executor = 'google-batch'
    google.project = 'your-project-id'
    google.region = 'us-central1'
}
```

## Version Compatibility

- **Nextflow**: >= 25.04
- **Docker/Singularity**: Any recent version
- **Ultima Genomics Tools**: As specified in container versions
- **GATK**: Latest version (for interval operations)

## Future Enhancements

Potential improvements:

1. **Optimization flags**: Add pipeline-specific optimization modes
2. **Quality metrics**: Collect and report QC metrics
3. **Multi-sample support**: Process cohorts in single run
4. **Somatic variant calling**: Extend to tumor-normal pairs
5. **Cloud-native optimization**: Better cloud storage integration
