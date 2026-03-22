#!/usr/bin/env nextflow

/*
 * Efficient DV Germline Variant Calling Pipeline
 * 
 * Based on: https://github.com/Ultimagen/healthomics-workflows/blob/main/workflows/efficient_dv/howto-germline-calling-efficient-dv.md
 */

nextflow.enable.dsl = 2

// ===== PARAMETERS =====

params.cram = null
params.cram_index = null
params.output_dir = "results"
params.sample_name = "sample"

// Reference files
params.ref_fasta = "gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta"
params.ref_fasta_index = "gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.fasta.fai"
params.ref_dict = "gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.dict"
params.intervals = "gs://gcp-public-data--broad-references/hg38/v0/wgs_calling_regions.hg38.interval_list"

// Model
params.model_onnx = "gs://concordanz/deepvariant/model/germline/v1.14/germline-ramp-8128462_shuffle_300K_ckpt_260000.onnx"

// Annotation files (optional)
params.annotation_beds = null  // Comma-separated list of BED files
params.dbsnp = "gs://gcp-public-data--broad-references/hg38/v0/Homo_sapiens_assembly38.dbsnp138.vcf"
params.filters_file = null

// Scatter parameters
params.scatter_count = 40

// make_examples parameters
params.min_base_quality = 5
params.min_mapq = 5
params.cgp_min_count_snps = 2
params.cgp_min_count_hmer_indels = 2
params.cgp_min_count_non_hmer_indels = 2
params.cgp_min_fraction_snps = 0.12
params.cgp_min_fraction_hmer_indels = 0.12
params.cgp_min_fraction_non_hmer_indels = 0.06
params.cgp_min_mapping_quality = 5
params.max_reads_per_region = 1500
params.assembly_min_base_quality = 0
params.optimal_coverages = 50
params.median_coverage = 50  // Required when using --optimal-coverages
params.add_ins_size_channel = true

// call_variants parameters
params.use_serialized_model = 1
params.trt_workspace_size_mb = 2000
params.num_infer_threads_per_gpu = 2
params.use_gpus = 1
params.gpu_id = 0
params.num_uncompr_threads = 8
params.uncompr_buf_size_gb = 1
params.num_conversion_threads = 2
params.ensemble_size = 7
params.random_seed = 1000
params.reference_rows = 5
params.sample_heights = 100
params.shuffle_all_samples = false

// post_process parameters
params.flow_order = "TGCA"
params.make_gvcf = false
params.gvcf_p_error = 0.005
params.gvcf_outfile = null
params.gq_resolution = null

// ===== PROCESSES =====

process SCATTER_INTERVALS {
    container 'docker://broadinstitute/picard:latest'
    
    input:
    path interval_list
    
    output:
    path "out/scattered_*.interval_list", emit: intervals
    
    script:
    """
    mkdir -p out
    java -jar /usr/picard/picard.jar IntervalListTools \\
        SCATTER_COUNT=${params.scatter_count} \\
        SUBDIVISION_MODE=BALANCING_WITHOUT_INTERVAL_SUBDIVISION_WITH_OVERFLOW \\
        UNIQUE=true \\
        SORT=true \\
        BREAK_BANDS_AT_MULTIPLES_OF=100000 \\
        INPUT=${interval_list} \\
        OUTPUT=out
    
    # Rename to have consistent naming
    cd out
    for f in temp_*/*.interval_list; do
        num=\$(basename \$(dirname \$f) | sed 's/temp_0*//')
        mv \$f scattered_\${num}.interval_list
    done
    """
}

process CONVERT_INTERVALS_TO_BED {
    container 'docker://ubuntu:22.04'
    
    input:
    path interval_list
    
    output:
    path "*.bed", emit: bed
    
    script:
    def bed_name = interval_list.baseName + ".bed"
    """
    cat ${interval_list} | grep -v @ | awk 'BEGIN{OFS="\\t"}{print \$1,\$2-1,\$3}' > ${bed_name}
    """
}

process MAKE_EXAMPLES {
    container 'docker://ultimagenomics/make_examples:3.2.1'
    
    input:
    tuple val(shard_id), path(bed)
    path cram
    path cram_index
    path ref_fasta
    path ref_fasta_index
    path ref_dict
    
    output:
    path "${shard_id}.tfrecord.gz", emit: tfrecord
    path "${shard_id}.gvcf.tfrecord.gz", optional: true, emit: gvcf_tfrecord
    
    script:
    def add_ins_size = params.add_ins_size_channel ? "--add-ins-size-channel" : ""
    def gvcf_args = params.make_gvcf ? "--gvcf --p-error ${params.gvcf_p_error}" : ""
    
    """
    tool \\
        --input ${cram} \\
        --cram-index ${cram_index} \\
        --bed ${bed} \\
        --output ${shard_id} \\
        --reference ${ref_fasta} \\
        --min-base-quality ${params.min_base_quality} \\
        --min-mapq ${params.min_mapq} \\
        --cgp-min-count-snps ${params.cgp_min_count_snps} \\
        --cgp-min-count-hmer-indels ${params.cgp_min_count_hmer_indels} \\
        --cgp-min-count-non-hmer-indels ${params.cgp_min_count_non_hmer_indels} \\
        --cgp-min-fraction-snps ${params.cgp_min_fraction_snps} \\
        --cgp-min-fraction-hmer-indels ${params.cgp_min_fraction_hmer_indels} \\
        --cgp-min-fraction-non-hmer-indels ${params.cgp_min_fraction_non_hmer_indels} \\
        --cgp-min-mapping-quality ${params.cgp_min_mapping_quality} \\
        --max-reads-per-region ${params.max_reads_per_region} \\
        --assembly-min-base-quality ${params.assembly_min_base_quality} \\
        --optimal-coverages ${params.optimal_coverages} \\
        --median-coverage ${params.median_coverage} \\
        ${add_ins_size} \\
        ${gvcf_args}
    """
}

process CALL_VARIANTS {
    container 'docker://ultimagenomics/call_variants:3.0.0'
    
    input:
    path tfrecords
    path model_onnx
    
    output:
    path "call_variants.*.gz", emit: called_variants
    
    script:
    def tfrecord_list = tfrecords.collect { it.name }.sort()
    def num_examples = tfrecord_list.size()
    
    """
    # Create INI file
    cat > params.ini <<EOF
[RT classification]
onnxFileName = ${model_onnx}
useSerializedModel = ${params.use_serialized_model}
trtWorkspaceSizeMB = ${params.trt_workspace_size_mb}
numInferTreadsPerGpu = ${params.num_infer_threads_per_gpu}
useGPUs = ${params.use_gpus}
gpuid = ${params.gpu_id}

[debug]
logFileFolder = .

[ensemble]
ensembleSize = ${params.ensemble_size}
randomSeed = ${params.random_seed}
referenceRows = ${params.reference_rows}
sampleHeights = ${params.sample_heights}
shuffleAllSamples = ${params.shuffle_all_samples}

[general]
tfrecord = 1
compressed = 1
outputInOneFile = 0
numUncomprThreads = ${params.num_uncompr_threads}
uncomprBufSizeGB = ${params.uncompr_buf_size_gb}
outputFileName = call_variants
numConversionThreads = ${params.num_conversion_threads}
numExampleFiles = ${num_examples}

EOF

    # Add example files to INI
    count=1
    for f in ${tfrecord_list.join(' ')}; do
        echo "exampleFile\$count = \$f" >> params.ini
        count=\$((count + 1))
    done
    
    # Run call_variants
    call_variants --param params.ini
    """
}

process POST_PROCESS {
    container 'docker://ultimagenomics/make_examples:3.2.1'
    publishDir "${params.output_dir}", mode: 'copy'
    
    input:
    path called_variants
    path gvcf_tfrecords
    path ref_fasta
    path ref_fasta_index
    path ref_dict
    path annotation_beds
    path dbsnp
    path filters_file
    
    output:
    path "${params.sample_name}.vcf.gz", emit: vcf
    path "${params.sample_name}.g.vcf.gz", optional: true, emit: gvcf
    
    script:
    def called_list = called_variants instanceof List ? called_variants.join(',') : called_variants
    def annotate = annotation_beds.name != 'NO_FILE' ? "--annotate --bed_annotation_files ${annotation_beds}" : ""
    def filter_args = filters_file.name != 'NO_FILE' ? "--filter --filters_file ${filters_file}" : ""
    def dbsnp_arg = dbsnp.name != 'NO_FILE' ? "--dbsnp ${dbsnp}" : ""
    
    def gvcf_args = ""
    if (params.make_gvcf && gvcf_tfrecords.name != 'NO_FILE') {
        def gvcf_list = gvcf_tfrecords instanceof List ? gvcf_tfrecords.join(',') : gvcf_tfrecords
        def gvcf_out = params.gvcf_outfile ?: "${params.sample_name}.g.vcf.gz"
        gvcf_args = "--gvcf_outfile ${gvcf_out} --nonvariant_site_tfrecord_path ${gvcf_list}"
        
        if (params.gq_resolution) {
            gvcf_args += " --gq-resolution ${params.gq_resolution}"
        }
    }
    
    """
    ug_postproc \\
        --infile ${called_list} \\
        --ref ${ref_fasta} \\
        --outfile ${params.sample_name}.vcf.gz \\
        --consider_strand_bias \\
        --flow_order ${params.flow_order} \\
        ${annotate} \\
        --qual_filter 1 \\
        ${filter_args} \\
        ${dbsnp_arg} \\
        ${gvcf_args}
    """
}

// ===== WORKFLOW =====

workflow {
    // Input validation
    if (!params.cram) {
        error "Please provide --cram parameter"
    }
    if (!params.cram_index) {
        error "Please provide --cram_index parameter"
    }
    
    // Create channels
    cram_ch = channel.fromPath(params.cram, checkIfExists: true)
    cram_index_ch = channel.fromPath(params.cram_index, checkIfExists: true)
    intervals_ch = channel.fromPath(params.intervals, checkIfExists: true)
    
    ref_fasta_ch = channel.fromPath(params.ref_fasta, checkIfExists: true)
    ref_fasta_index_ch = channel.fromPath(params.ref_fasta_index, checkIfExists: true)
    ref_dict_ch = channel.fromPath(params.ref_dict, checkIfExists: true)
    
    model_ch = channel.fromPath(params.model_onnx, checkIfExists: true)
    
    // Optional files
    annotation_beds_ch = params.annotation_beds ? 
        channel.fromPath(params.annotation_beds.tokenize(','), checkIfExists: true).collect() : 
        channel.value(file('NO_FILE'))
    
    dbsnp_ch = params.dbsnp ? 
        channel.fromPath(params.dbsnp, checkIfExists: true) : 
        channel.value(file('NO_FILE'))
    
    filters_ch = params.filters_file ? 
        channel.fromPath(params.filters_file, checkIfExists: true) : 
        channel.value(file('NO_FILE'))
    
    // Scatter intervals
    SCATTER_INTERVALS(intervals_ch)
    
    // Convert to BED
    scattered_beds = SCATTER_INTERVALS.out.intervals
        .flatten()
        .map { file -> 
            def shard_id = file.baseName.replaceAll('scattered_', '')
            [shard_id, file]
        }
    
    CONVERT_INTERVALS_TO_BED(
        scattered_beds.map { it[1] }
    )
    
    // Combine shard_id with BED files
    beds_with_id = CONVERT_INTERVALS_TO_BED.out.bed
        .flatten()
        .map { file ->
            def shard_id = file.baseName.replaceAll('scattered_', '').replaceAll('.bed', '')
            [shard_id, file]
        }
    
    // Make examples
    MAKE_EXAMPLES(
        beds_with_id,
        cram_ch,
        cram_index_ch,
        ref_fasta_ch,
        ref_fasta_index_ch,
        ref_dict_ch
    )
    
    // Call variants
    CALL_VARIANTS(
        MAKE_EXAMPLES.out.tfrecord.collect(),
        model_ch
    )
    
    // Collect gvcf tfrecords if making gvcf
    gvcf_tfrecords_ch = params.make_gvcf ? 
        MAKE_EXAMPLES.out.gvcf_tfrecord.collect() : 
        channel.value(file('NO_FILE'))
    
    // Post process
    POST_PROCESS(
        CALL_VARIANTS.out.called_variants.collect(),
        gvcf_tfrecords_ch,
        ref_fasta_ch,
        ref_fasta_index_ch,
        ref_dict_ch,
        annotation_beds_ch,
        dbsnp_ch,
        filters_ch
    )
}
