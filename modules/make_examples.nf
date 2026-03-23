process MAKE_EXAMPLES {
    container 'docker://ultimagenomics/make_examples:3.2.1'
    
    input:
    tuple val(shard_id), path(bed), path(cram), path(cram_index), path(ref_fasta), path(ref_fasta_index), path(ref_dict)
    
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
        --threads ${task.cpus} \\
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
