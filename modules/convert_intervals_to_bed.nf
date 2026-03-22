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
