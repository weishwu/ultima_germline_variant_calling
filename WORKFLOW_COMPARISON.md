# Workflow Comparison: Before vs After Optimization

## BEFORE: Original Workflow (Redundant Serialization)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PIPELINE START                                   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                        ┌───────────────────────┐
                        │  SCATTER_INTERVALS    │
                        │  (Split regions)      │
                        └───────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │                               │
                    ▼                               ▼
        ┌──────────────────────┐      ┌──────────────────────┐
        │ CONVERT_TO_BED       │      │ CONVERT_TO_BED       │
        │ (Shard 1)            │ ...  │ (Shard N)            │
        └──────────────────────┘      └──────────────────────┘
                    │                               │
                    ▼                               ▼
        ┌──────────────────────┐      ┌──────────────────────┐
        │ MAKE_EXAMPLES        │      │ MAKE_EXAMPLES        │
        │ (Shard 1)            │ ...  │ (Shard N)            │
        │ Output: tfrecord.gz  │      │ Output: tfrecord.gz  │
        └──────────────────────┘      └──────────────────────┘
                    │                               │
                    └───────────────┬───────────────┘
                                    │
                                    ▼
                        ┌───────────────────────┐
                        │   CALL_VARIANTS       │
                        │                       │
                        │ ⚠️  PROBLEM:          │
                        │ Serializes ONNX       │
                        │ model EVERY time      │
                        │ (2-5 min overhead)    │
                        │                       │
                        │ If scattered: N×      │
                        │ serialization cost!   │
                        └───────────────────────┘
                                    │
                                    ▼
                        ┌───────────────────────┐
                        │   POST_PROCESS        │
                        │   (Generate VCF)      │
                        └───────────────────────┘
                                    │
                                    ▼
                        ┌───────────────────────┐
                        │    FINAL VCF OUTPUT   │
                        └───────────────────────┘

⏱️  Total Serialization Time: N shards × 2-5 min = 10-50+ minutes wasted!
```

## AFTER: Optimized Workflow (Serialize Once, Reuse Many)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PIPELINE START                                   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │                               │
                    ▼                               ▼
        ┌──────────────────────┐      ┌──────────────────────┐
        │ ✨ SERIALIZE_MODEL   │      │  SCATTER_INTERVALS    │
        │                      │      │  (Split regions)      │
        │ • Run ONCE           │      └──────────────────────┘
        │ • Generate .serial   │                  │
        │ • Cache with storeDir│      ┌───────────┴───────────┐
        │ • 2-5 min (one-time) │      │                       │
        │                      │      ▼                       ▼
        │ Output:              │  ┌──────────────┐  ┌──────────────┐
        │ model.onnx.serialized│  │CONVERT_TO_BED│  │CONVERT_TO_BED│
        └──────────────────────┘  │  (Shard 1)   │  │  (Shard N)   │
                    │             └──────────────┘  └──────────────┘
                    │                     │                  │
                    │                     ▼                  ▼
                    │             ┌──────────────┐  ┌──────────────┐
                    │             │MAKE_EXAMPLES │  │MAKE_EXAMPLES │
                    │             │  (Shard 1)   │  │  (Shard N)   │
                    │             │tfrecord.gz   │  │tfrecord.gz   │
                    │             └──────────────┘  └──────────────┘
                    │                     │                  │
                    │                     └────────┬─────────┘
                    │                              │
                    └──────────────┬───────────────┘
                                   │
                                   ▼
                        ┌─────────────────────────┐
                        │   CALL_VARIANTS         │
                        │                         │
                        │ ✅ OPTIMIZED:           │
                        │ Uses pre-serialized     │
                        │ model from cache        │
                        │                         │
                        │ • No serialization wait │
                        │ • Instant model load    │
                        │ • Reused across shards  │
                        └─────────────────────────┘
                                   │
                                   ▼
                        ┌─────────────────────────┐
                        │   POST_PROCESS          │
                        │   (Generate VCF)        │
                        └─────────────────────────┘
                                   │
                                   ▼
                        ┌─────────────────────────┐
                        │    FINAL VCF OUTPUT     │
                        └─────────────────────────┘

⏱️  Total Serialization Time: 1 × 2-5 min = 2-5 minutes (90% reduction!)
💾 Cached for subsequent runs = ~0 min!
```

## Key Improvements

| Aspect | Before | After | Improvement |
|--------|--------|-------|-------------|
| **Model Serialization** | N times (per shard/task) | 1 time (at start) | 90%+ reduction |
| **Serialization Time** | N × 2-5 min | 1 × 2-5 min | ~27 min saved (10 shards) |
| **GPU Efficiency** | Idle during each serialization | Idle only once | Better utilization |
| **Subsequent Runs** | Full serialization each time | Cached (instant) | Near-zero overhead |
| **Resource Usage** | Same GPU requirements | Same GPU requirements | No extra resources |

## Execution Flow Details

### Step 1: Model Serialization (NEW)
```
SERIALIZE_MODEL
├── Input: model.onnx
├── Action: Generate TensorRT serialized model
├── Output: model.onnx.serialized
├── Cache: storeDir (persists across runs)
└── Time: 2-5 minutes (once per unique ONNX file)
```

### Step 2: Parallel Example Generation (UNCHANGED)
```
SCATTER → CONVERT → MAKE_EXAMPLES (parallel)
├── Shards: 1..N (typically 10-50)
├── Output: tfrecord.gz files
└── Independent from model serialization
```

### Step 3: Variant Calling (OPTIMIZED)
```
CALL_VARIANTS
├── Input: 
│   ├── tfrecords (from MAKE_EXAMPLES)
│   ├── model.onnx (original)
│   └── model.onnx.serialized (pre-generated) ← KEY CHANGE
├── Action: Load serialized model (instant)
├── Output: called variants
└── Time: No serialization overhead!
```

## Cache Behavior

### First Pipeline Run
```
1. Check: model.onnx.serialized exists in storeDir? ❌ NO
2. Action: SERIALIZE_MODEL runs (~2-5 min)
3. Cache: model.onnx.serialized saved to storeDir
4. Use: CALL_VARIANTS uses cached model
```

### Subsequent Pipeline Runs (Same ONNX)
```
1. Check: model.onnx.serialized exists in storeDir? ✅ YES
2. Action: SERIALIZE_MODEL skipped (cache hit)
3. Use: CALL_VARIANTS uses cached model immediately
4. Time: ~0 seconds overhead
```

### Different ONNX Model
```
1. Check: new_model.onnx.serialized exists? ❌ NO
2. Action: SERIALIZE_MODEL runs for new model
3. Cache: new_model.onnx.serialized saved separately
4. Result: Multiple models can be cached concurrently
```

## Performance Metrics

### Example: 10-Shard Pipeline

#### Before Optimization
```
Serialization: 10 shards × 3 min/shard = 30 min
Variant Calling: 10 shards × 5 min/shard = 50 min
─────────────────────────────────────────────────
Total Time: 80 minutes
```

#### After Optimization (First Run)
```
Serialization: 1 × 3 min = 3 min
Variant Calling: 10 shards × 5 min/shard = 50 min
─────────────────────────────────────────────────
Total Time: 53 minutes (-34% faster)
```

#### After Optimization (Subsequent Runs)
```
Serialization: Cache hit = 0 min
Variant Calling: 10 shards × 5 min/shard = 50 min
─────────────────────────────────────────────────
Total Time: 50 minutes (-37.5% faster)
```

## Summary

The optimization transforms the pipeline from a **serialize-per-task** pattern to a **serialize-once-reuse-many** pattern, delivering:

✅ **90%+ reduction** in model serialization overhead  
✅ **No quality impact** - same variant calling results  
✅ **Cache persistence** - even faster subsequent runs  
✅ **No additional resources** - same GPU requirements  
✅ **Better GPU utilization** - less idle time  
✅ **Scalable** - benefit grows with number of shards  
