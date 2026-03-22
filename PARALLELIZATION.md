# Parallelization Guide

This document describes the parallelization strategies implemented in the Efficient DV Germline Variant Calling Pipeline.

## Overview

The pipeline implements a **scatter-gather** parallelization strategy that distributes work across multiple processes to maximize throughput and minimize runtime.

## Parallelization Strategy

### 1. Interval Scattering (SCATTER_INTERVALS)
- **Purpose**: Divides the genome into smaller regions (shards)
- **Default**: 40 shards (`params.scatter_count = 40`)
- **Parallelization**: Single process, creates all shards
- **Resources**: 
  - CPUs: 2 (`params.scatter_cpus`)
  - Memory: 4 GB (`params.scatter_memory`)

### 2. Interval Conversion (CONVERT_INTERVALS_TO_BED)
- **Purpose**: Converts interval lists to BED format
- **Parallelization**: **PARALLEL** - Each shard processed independently
- **Max Forks**: 20 (`params.convert_max_forks`) - Run up to 20 conversions simultaneously
- **Resources**: 
  - CPUs: 1 per task (`params.convert_cpus`)
  - Memory: 2 GB per task (`params.convert_memory`)
- **Speedup**: Near-linear with available cores (40 shards / 20 forks = ~2 waves)

### 3. Make Examples (MAKE_EXAMPLES)
- **Purpose**: Creates TensorFlow examples from alignment data
- **Parallelization**: **PARALLEL** - Each shard processed independently
- **Max Forks**: 10 (`params.make_examples_max_forks`) - Run up to 10 in parallel
- **Resources**: 
  - CPUs: 2 per task (`params.make_examples_cpus`)
  - Memory: 8 GB per task (`params.make_examples_memory`)
- **Speedup**: Near-linear with available cores (40 shards / 10 forks = ~4 waves)
- **Note**: This is typically the most time-consuming step

### 4. Call Variants (CALL_VARIANTS)
- **Purpose**: Runs inference on all TensorFlow examples
- **Parallelization**: **SINGLE PROCESS** - Processes all shards together
- **Max Forks**: 1 (GPU-intensive, controlled in config)
- **Resources**: 
  - CPUs: 8 (`params.call_variants_cpus`)
  - Memory: 32 GB (`params.call_variants_memory`)
  - GPU: 1 (when using `gpu` or `singularity_gpu` profile)
- **Note**: Benefits from GPU acceleration, not multi-process parallelization

### 5. Post Process (POST_PROCESS)
- **Purpose**: Merges variants and applies filters
- **Parallelization**: **SINGLE PROCESS** - Processes all called variants
- **Resources**: 
  - CPUs: 4 (`params.post_process_cpus`)
  - Memory: 16 GB (`params.post_process_memory`)

## Resource Configuration

### Default Resources (per process)
```groovy
params.scatter_cpus = 2
params.scatter_memory = '4 GB'

params.convert_cpus = 1
params.convert_memory = '2 GB'
params.convert_max_forks = 20

params.make_examples_cpus = 2
params.make_examples_memory = '8 GB'
params.make_examples_max_forks = 10

params.call_variants_cpus = 8
params.call_variants_memory = '32 GB'

params.post_process_cpus = 4
params.post_process_memory = '16 GB'
```

### Total Resource Requirements (Peak)

**Standard Profile (10 parallel MAKE_EXAMPLES):**
- CPUs: ~20-30 cores (10 × 2 CPUs for MAKE_EXAMPLES + overhead)
- Memory: ~80-100 GB (10 × 8 GB for MAKE_EXAMPLES + overhead)

**Parallel Profile (20 parallel MAKE_EXAMPLES):**
- CPUs: ~40-60 cores (20 × 4 CPUs for MAKE_EXAMPLES + overhead)
- Memory: ~320-350 GB (20 × 16 GB for MAKE_EXAMPLES + overhead)

## Execution Profiles

### 1. Standard Profile (Default)
```bash
nextflow run efficient_dv_germline.nf -profile standard
```
- Local execution with moderate parallelization
- Good for workstations and small clusters

### 2. Parallel Profile (High-Performance)
```bash
nextflow run efficient_dv_germline.nf -profile parallel
```
- Maximum parallelization for MAKE_EXAMPLES and CONVERT_INTERVALS_TO_BED
- Requires more resources but significantly faster
- MAKE_EXAMPLES: 20 parallel forks with 4 CPUs and 16 GB each
- CONVERT_INTERVALS_TO_BED: 40 parallel forks

### 3. GPU Profile
```bash
nextflow run efficient_dv_germline.nf -profile gpu
```
- Enables GPU acceleration for CALL_VARIANTS
- Requires NVIDIA GPU and Docker with `--gpus all` support
- Allocates 8 CPUs and 64 GB memory to CALL_VARIANTS

### 4. Singularity GPU Profile
```bash
nextflow run efficient_dv_germline.nf -profile singularity_gpu
```
- GPU acceleration using Singularity containers
- Uses `--nv` flag for NVIDIA GPU access

### 5. Cloud Profiles
```bash
# AWS Batch
nextflow run efficient_dv_germline.nf -profile aws

# Google Cloud Batch
nextflow run efficient_dv_germline.nf -profile gcp

# SLURM cluster
nextflow run efficient_dv_germline.nf -profile slurm
```

## Optimizing Parallelization

### Adjusting Scatter Count
Increase for more parallelization:
```bash
nextflow run efficient_dv_germline.nf \
  --scatter_count 80 \
  --make_examples_max_forks 20
```

### Adjusting Max Forks
Control parallel execution:
```bash
nextflow run efficient_dv_germline.nf \
  --make_examples_max_forks 15 \
  --convert_max_forks 30
```

### Custom Resource Allocation
```bash
nextflow run efficient_dv_germline.nf \
  --make_examples_cpus 4 \
  --make_examples_memory '16 GB' \
  --call_variants_cpus 16 \
  --call_variants_memory '64 GB'
```

## Performance Monitoring

The pipeline automatically generates performance reports:

1. **Trace File**: `results/trace.txt` - Detailed task-level metrics
2. **Timeline**: `results/timeline.html` - Visual timeline of task execution
3. **Report**: `results/report.html` - Overall execution summary

These reports help identify bottlenecks and optimize resource allocation.

## Best Practices

1. **Balance scatter_count and max_forks**: 
   - More shards = better parallelization but more overhead
   - Typical range: 40-100 shards

2. **Match resources to hardware**:
   - Don't exceed available CPUs/memory
   - Leave headroom for system processes

3. **Use GPU for CALL_VARIANTS**:
   - Provides 5-10x speedup over CPU-only
   - Essential for production workloads

4. **Monitor with reports**:
   - Check timeline.html to identify bottlenecks
   - Adjust resources based on actual usage

5. **Profile-specific optimization**:
   - Local: Limit parallelization to available cores
   - Cloud: Scale up scatter_count and max_forks
   - Cluster: Use queue limits in configuration

## Example Configurations

### Workstation (16 cores, 64 GB RAM)
```bash
nextflow run efficient_dv_germline.nf \
  --scatter_count 40 \
  --make_examples_max_forks 6 \
  --make_examples_cpus 2 \
  --make_examples_memory '8 GB'
```

### Server (64 cores, 256 GB RAM)
```bash
nextflow run efficient_dv_germline.nf -profile parallel \
  --scatter_count 80 \
  --make_examples_max_forks 20
```

### Cloud (Unlimited scaling)
```bash
nextflow run efficient_dv_germline.nf -profile aws \
  --scatter_count 200 \
  --make_examples_max_forks 50
```

## Troubleshooting

**Out of Memory Errors:**
- Reduce `max_forks` parameters
- Increase memory allocations
- Reduce `scatter_count`

**Slow Performance:**
- Increase `max_forks` if resources available
- Use GPU profile for CALL_VARIANTS
- Increase `scatter_count` for better parallelization

**Resource Contention:**
- Adjust `executor.queueSize` in config
- Use `submitRateLimit` to throttle job submission
- Consider using a cluster executor (SLURM, AWS Batch)
