process SERIALIZE_MODEL {
    tag "Serialize ONNX model"
    
    container 'docker://ultimagenomics/call_variants:3.0.0'
    
    // Use storeDir to cache the serialized model across pipeline runs
    // This ensures the model is only serialized once and reused
    storeDir "${params.output_dir}/model_cache"
    
    accelerator 1, type: 'nvidia-tesla-v100'
    
    input:
    path onnx_file
    
    output:
    tuple path(onnx_file), path("${onnx_file.name}.serialized"), emit: model_with_serialized
    
    script:
    """
    echo "Generating serialized TensorRT model for ${onnx_file.name}"
    echo "This will be cached and reused across all pipeline runs"
    echo ""
    
    # Create a minimal test to trigger serialization
    # We'll use the call_variants binary with a dummy command that triggers model loading
    cat > test_params.ini <<EOF
[general]
onnxFilename = ${onnx_file}
useSerializedModel = 1
numExampleFiles = 1
exampleFile1 = dummy.tfrecord.gz

[model]
trtWorkspaceSizeMb = ${params.trt_workspace_size_mb}
numInferThreadsPerGpu = ${task.cpus}
useGpus = ${params.use_gpus}
gpuId = ${params.gpu_id}
ensembleSize = ${params.ensemble_size}
randomSeed = ${params.random_seed}
referenceRows = ${params.reference_rows}
sampleHeights = ${params.sample_heights}
shuffleAllSamples = ${params.shuffle_all_samples ? 1 : 0}

[uncompression]
numThreads = ${task.cpus}
bufSizeGb = ${params.uncompr_buf_size_gb}

[conversion]
numThreads = ${task.cpus}
EOF

    # Create a tiny dummy tfrecord just to satisfy the binary
    # (it won't actually process this, just load the model)
    touch dummy.tfrecord.gz
    
    # Run call_variants with --help or a quick init to trigger serialization
    # The binary will:
    # 1. Look for ${onnx_file}.serialized
    # 2. Not find it
    # 3. Generate it from the .onnx file
    # 4. Exit (we don't actually run inference)
    
    echo "Triggering TensorRT serialization..."
    echo "This may take 2-5 minutes depending on GPU and model complexity"
    echo ""
    
    # We need to actually trigger model loading, which happens during initialization
    # The trick: run with an invalid/empty input that causes quick exit after model load
    timeout 600 call_variants test_params.ini || true
    
    # Verify the serialized file was created
    if [ -f "${onnx_file.name}.serialized" ]; then
        SIZE=\$(stat -c%s "${onnx_file.name}.serialized" 2>/dev/null || stat -f%z "${onnx_file.name}.serialized" 2>/dev/null)
        echo ""
        echo "✅ Serialized model generated successfully!"
        echo "   File: ${onnx_file.name}.serialized"
        echo "   Size: \${SIZE} bytes (\$(echo "scale=2; \${SIZE}/1024/1024" | bc) MB)"
        echo ""
        echo "This serialized model will be reused for all CALL_VARIANTS tasks"
        echo "Cached in: ${params.output_dir}/model_cache/"
    else
        echo "❌ ERROR: Serialized model not created"
        exit 1
    fi
    
    # Clean up dummy files
    rm -f dummy.tfrecord.gz test_params.ini
    """
}
