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
