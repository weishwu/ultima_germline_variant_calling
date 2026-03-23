#!/usr/bin/env nextflow

/*
 * Efficient DV Germline Variant Calling Pipeline (Modularized)
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
params.skip_dbsnp_annotation = false  // Set to true if ug_postproc crashes with dbSNP

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

// ===== MODULE IMPORTS =====

include { SERIALIZE_MODEL } from './modules/serialize_model.nf'
include { SCATTER_INTERVALS } from './modules/scatter_intervals.nf'
include { CONVERT_INTERVALS_TO_BED } from './modules/convert_intervals_to_bed.nf'
include { MAKE_EXAMPLES } from './modules/make_examples.nf'
include { CALL_VARIANTS } from './modules/call_variants.nf'
include { POST_PROCESS } from './modules/post_process.nf'

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
        channel.value(file('NO_FILE_ANNOTATION'))
    
    dbsnp_ch = params.dbsnp ? 
        channel.fromPath(params.dbsnp, checkIfExists: true) : 
        channel.value(file('NO_FILE_DBSNP'))
    
    filters_ch = params.filters_file ? 
        channel.fromPath(params.filters_file, checkIfExists: true) : 
        channel.value(file('NO_FILE_FILTERS'))
    
    // ===== STEP 1: Serialize ONNX model (once, cached across runs) =====
    SERIALIZE_MODEL(model_ch)
    
    // Extract the serialized model from the tuple output
    serialized_model_ch = SERIALIZE_MODEL.out.model_with_serialized.map { onnx, serialized -> serialized }
    
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
    
    // Make examples - combine bed files with reference files
    make_examples_input = beds_with_id.combine(cram_ch)
        .combine(cram_index_ch)
        .combine(ref_fasta_ch)
        .combine(ref_fasta_index_ch)
        .combine(ref_dict_ch)
    
    MAKE_EXAMPLES(
        make_examples_input
    )
    
    // Call variants with pre-serialized model
    CALL_VARIANTS(
        MAKE_EXAMPLES.out.tfrecord.collect(),
        model_ch,
        serialized_model_ch
    )
    
    // Collect gvcf tfrecords if making gvcf
    gvcf_tfrecords_ch = params.make_gvcf ? 
        MAKE_EXAMPLES.out.gvcf_tfrecord.collect() : 
        channel.value(file('NO_FILE_GVCF'))
    
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
