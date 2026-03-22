process CALL_VARIANTS {
    container 'docker://ultimagenomics/call_variants:3.0.0'
    publishDir "${params.output_dir}/raw_variants", mode: 'copy', pattern: "call_variants.*.gz"
    
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
