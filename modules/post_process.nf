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
    
    // Check if we need annotation (for BED files or dbSNP)
    def has_annotation_beds = !annotation_beds.name.startsWith('NO_FILE')
    def has_dbsnp = !dbsnp.name.startsWith('NO_FILE') && !params.skip_dbsnp_annotation
    def needs_annotate = has_annotation_beds || has_dbsnp
    
    def annotate = needs_annotate ? "--annotate" : ""
    def bed_files = has_annotation_beds ? "--bed_annotation_files ${annotation_beds}" : ""
    def dbsnp_arg = has_dbsnp ? "--dbsnp ${dbsnp}" : ""
    def filter_args = !filters_file.name.startsWith('NO_FILE') ? "--filter --filters_file ${filters_file}" : ""
    
    def gvcf_args = ""
    if (params.make_gvcf && !gvcf_tfrecords.name.startsWith('NO_FILE')) {
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
        ${bed_files} \\
        --qual_filter 1 \\
        ${filter_args} \\
        ${dbsnp_arg} \\
        ${gvcf_args}
    """
}
