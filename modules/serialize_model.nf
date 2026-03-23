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
    echo "=========================================="
    echo "SERIALIZE_MODEL Process"
    echo "=========================================="
    echo "Model: ${onnx_file.name}"
    echo "Use Serialized: ${params.use_serialized_model}"
    echo "TensorRT Workspace: ${params.trt_workspace_size_mb} MB"
    echo ""
    
    # Skip if serialization disabled
    if [ "${params.use_serialized_model}" -eq 0 ]; then
        echo "ℹ️  Serialization disabled (use_serialized_model=0)"
        touch ${onnx_file.name}.serialized
        exit 0
    fi
    
    echo "🔄 Triggering TensorRT serialization..."
    echo "   This may take 2-5 minutes depending on GPU and model complexity"
    echo ""
    
    # Create minimal parameters file to trigger model loading
    cat > test_params.ini <<EOF
[call_variants]
model = ${onnx_file}
use_serialized_model = ${params.use_serialized_model}
trt_workspace_size_mb = ${params.trt_workspace_size_mb}
num_infer_threads_per_gpu = 1
use_gpus = ${params.use_gpus}
gpu_id = ${params.gpu_id}
ensemble_size = 1
random_seed = 1000
reference_rows = 2
sample_heights = 10
num_uncompr_threads = 1
uncompr_buf_size_gb = 1
num_conversion_threads = 1
EOF
    
    # Create minimal dummy input files to satisfy the binary
    touch dummy.tfrecord.gz
    echo -e "sample1" > dummy_samples.txt
    
    # Run call_variants - it will:
    # 1. Initialize and load the model
    # 2. Detect no .serialized file exists
    # 3. Generate the .serialized file from .onnx
    # 4. Fail when it tries to process (no valid input) - that's OK!
    echo "Running call_variants to trigger serialization..."
    timeout 600 call_variants test_params.ini >serialization.log 2>&1 || {
        EXIT_CODE=\$?
        echo "call_variants exited with code: \$EXIT_CODE (expected - we're just serializing)"
    }
    
    # Verify the serialized file was created
    if [ -f "${onnx_file.name}.serialized" ] && [ -s "${onnx_file.name}.serialized" ]; then
        SIZE=\$(stat -c%s "${onnx_file.name}.serialized" 2>/dev/null || stat -f%z "${onnx_file.name}.serialized" 2>/dev/null || echo "unknown")
        
        if [ "\$SIZE" != "unknown" ]; then
            SIZE_MB=\$(echo "scale=2; \${SIZE}/1024/1024" | bc 2>/dev/null || echo "\$(expr \${SIZE} / 1048576)")
            echo ""
            echo "=========================================="
            echo "✅ Serialized model generated successfully!"
            echo "=========================================="
            echo "File: ${onnx_file.name}.serialized"
            echo "Size: \${SIZE} bytes (\${SIZE_MB} MB)"
            echo ""
            echo "This serialized model will be reused for all"
            echo "CALL_VARIANTS tasks, saving 2-5 min per task."
            echo "Cached in: ${params.output_dir}/model_cache/"
            echo "=========================================="
        else
            echo "✅ Serialized model generated successfully!"
            echo "File: ${onnx_file.name}.serialized"
        fi
    else
        echo ""
        echo "=========================================="
        echo "❌ ERROR: Serialized model not created"
        echo "=========================================="
        echo ""
        echo "Last 50 lines of serialization log:"
        tail -n 50 serialization.log 2>/dev/null || echo "No log available"
        echo ""
        echo "Checking for .serialized files in current directory:"
        ls -lh *.serialized 2>/dev/null || echo "No .serialized files found"
        exit 1
    fi
    
    # Clean up dummy files (keep serialization.log for debugging)
    rm -f dummy.tfrecord.gz dummy_samples.txt test_params.ini
    """
}
