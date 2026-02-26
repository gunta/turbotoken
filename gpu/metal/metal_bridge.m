#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <pthread.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static NSString *const kKernelSource =
    @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"\n"
    @"constant uint TT_ENCODE_BYTES_PER_THREAD = 2048;\n"
    @"\n"
    @"kernel void tt_encode_u8_to_u32(\n"
    @"    const device uchar *input [[buffer(0)]],\n"
    @"    device uint *output [[buffer(1)]],\n"
    @"    constant uint &total_len [[buffer(2)]],\n"
    @"    uint gid [[thread_position_in_grid]]) {\n"
    @"    uint base = gid * TT_ENCODE_BYTES_PER_THREAD;\n"
    @"    if (base >= total_len) {\n"
    @"        return;\n"
    @"    }\n"
    @"    uint end = min(base + TT_ENCODE_BYTES_PER_THREAD, total_len);\n"
    @"    uint idx = base;\n"
    @"    for (; idx + 64 <= end; idx += 64) {\n"
    @"        const device uchar4 *in4 = (const device uchar4 *)(input + idx);\n"
    @"        device uint4 *out4 = (device uint4 *)(output + idx);\n"
    @"        out4[0] = uint4(in4[0]);\n"
    @"        out4[1] = uint4(in4[1]);\n"
    @"        out4[2] = uint4(in4[2]);\n"
    @"        out4[3] = uint4(in4[3]);\n"
    @"        out4[4] = uint4(in4[4]);\n"
    @"        out4[5] = uint4(in4[5]);\n"
    @"        out4[6] = uint4(in4[6]);\n"
    @"        out4[7] = uint4(in4[7]);\n"
    @"        out4[8] = uint4(in4[8]);\n"
    @"        out4[9] = uint4(in4[9]);\n"
    @"        out4[10] = uint4(in4[10]);\n"
    @"        out4[11] = uint4(in4[11]);\n"
    @"        out4[12] = uint4(in4[12]);\n"
    @"        out4[13] = uint4(in4[13]);\n"
    @"        out4[14] = uint4(in4[14]);\n"
    @"        out4[15] = uint4(in4[15]);\n"
    @"    }\n"
    @"    for (; idx + 4 <= end; idx += 4) {\n"
    @"        const device uchar4 *in4 = (const device uchar4 *)(input + idx);\n"
    @"        device uint4 *out4 = (device uint4 *)(output + idx);\n"
    @"        out4[0] = uint4(in4[0]);\n"
    @"    }\n"
    @"    for (; idx < end; idx += 1) {\n"
    @"        output[idx] = (uint)input[idx];\n"
    @"    }\n"
    @"}\n"
    @"\n"
    @"kernel void tt_count_nonzero_segments(\n"
    @"    const device uchar *input [[buffer(0)]],\n"
    @"    const device uint *offsets [[buffer(1)]],\n"
    @"    device uint *counts [[buffer(2)]],\n"
    @"    constant uint &segment_count [[buffer(3)]],\n"
    @"    uint segment_id [[threadgroup_position_in_grid]],\n"
    @"    uint lane_id [[thread_index_in_threadgroup]],\n"
    @"    uint lanes_per_group [[threads_per_threadgroup]],\n"
    @"    uint simdgroup_id [[simdgroup_index_in_threadgroup]],\n"
    @"    uint simdgroups_per_group [[simdgroups_per_threadgroup]]) {\n"
    @"    if (segment_id >= segment_count) {\n"
    @"        return;\n"
    @"    }\n"
    @"    uint start = offsets[segment_id];\n"
    @"    uint end = offsets[segment_id + 1];\n"
    @"    uint local_total = 0;\n"
    @"    uint idx = start + lane_id;\n"
    @"    uint stride = lanes_per_group;\n"
    @"    for (; idx + (stride * 15) < end; idx += stride * 16) {\n"
    @"        local_total += input[idx] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + stride] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 2)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 3)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 4)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 5)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 6)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 7)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 8)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 9)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 10)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 11)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 12)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 13)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 14)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 15)] != 0 ? 1u : 0u;\n"
    @"    }\n"
    @"    for (; idx < end; idx += lanes_per_group) {\n"
    @"        local_total += input[idx] != 0 ? 1u : 0u;\n"
    @"    }\n"
    @"    uint simd_total = simd_sum(local_total);\n"
    @"    if (simdgroups_per_group <= 1) {\n"
    @"        if (simd_is_first()) {\n"
    @"            counts[segment_id] = simd_total;\n"
    @"        }\n"
    @"        return;\n"
    @"    }\n"
    @"    threadgroup uint partial[256];\n"
    @"    if (simd_is_first()) {\n"
    @"        partial[simdgroup_id] = simd_total;\n"
    @"    }\n"
    @"    threadgroup_barrier(mem_flags::mem_threadgroup);\n"
    @"    if (simdgroup_id == 0) {\n"
    @"        uint group_total = lane_id < simdgroups_per_group ? partial[lane_id] : 0u;\n"
    @"        group_total = simd_sum(group_total);\n"
    @"        if (simd_is_first()) {\n"
    @"            counts[segment_id] = group_total;\n"
    @"        }\n"
    @"    }\n"
    @"}\n"
    @"\n"
    @"kernel void tt_chunk_owner_flags(\n"
    @"    const device uint *token_starts [[buffer(0)]],\n"
    @"    const device uint *source_chunks [[buffer(1)]],\n"
    @"    device uint *out_flags [[buffer(2)]],\n"
    @"    constant uint &token_count [[buffer(3)]],\n"
    @"    constant uint &chunk_bytes [[buffer(4)]],\n"
    @"    constant uint &num_chunks [[buffer(5)]],\n"
    @"    uint gid [[thread_position_in_grid]]) {\n"
    @"    if (gid >= token_count) {\n"
    @"        return;\n"
    @"    }\n"
    @"    uint owner = chunk_bytes > 0 ? (token_starts[gid] / chunk_bytes) : 0;\n"
    @"    if (num_chunks > 0 && owner >= num_chunks) {\n"
    @"        owner = num_chunks - 1;\n"
    @"    }\n"
    @"    out_flags[gid] = owner == source_chunks[gid] ? 1u : 0u;\n"
    @"}\n";

static NSString *const kBpeKernelSource =
    @"\n"
    @"constant uint TT_BPE_NULL = 0xffffffffu;\n"
    @"constant uint TT_BPE_DEAD = 0xfffffffeu;\n"
    @"constant uint TT_BPE_INVALID = 0xffffffffu;\n"
    @"constant uint TT_BPE_MAX_PROBES = 64u;\n"
    @"\n"
    @"struct tt_rank_entry {\n"
    @"    uint key_a;\n"
    @"    uint key_b;\n"
    @"    uint merge_rank;\n"
    @"    uint merged_token;\n"
    @"};\n"
    @"\n"
    @"inline uint tt_hash_pair(uint a, uint b) {\n"
    @"    uint h = 2166136261u;\n"
    @"    h = (h ^ a) * 16777619u;\n"
    @"    h = (h ^ b) * 16777619u;\n"
    @"    return h;\n"
    @"}\n"
    @"\n"
    @"inline bool tt_rank_lookup(\n"
    @"    const device tt_rank_entry *table,\n"
    @"    uint table_mask,\n"
    @"    uint left,\n"
    @"    uint right,\n"
    @"    thread uint &rank,\n"
    @"    thread uint &merged)\n"
    @"{\n"
    @"    uint slot = tt_hash_pair(left, right) & table_mask;\n"
    @"    for (uint probe = 0; probe < TT_BPE_MAX_PROBES; probe += 1) {\n"
    @"        const device tt_rank_entry &entry = table[(slot + probe) & table_mask];\n"
    @"        if (entry.merge_rank == TT_BPE_INVALID) {\n"
    @"            return false;\n"
    @"        }\n"
    @"        if (entry.key_a == left && entry.key_b == right) {\n"
    @"            rank = entry.merge_rank;\n"
    @"            merged = entry.merged_token;\n"
    @"            return true;\n"
    @"        }\n"
    @"    }\n"
    @"    return false;\n"
    @"}\n"
    @"\n"
    @"kernel void tt_bpe_reset_counters(\n"
    @"    device atomic_uint *min_rank_atomic [[buffer(0)]],\n"
    @"    device atomic_uint *merge_count [[buffer(1)]],\n"
    @"    uint gid [[thread_position_in_grid]]) {\n"
    @"    if (gid == 0) {\n"
    @"        atomic_store_explicit(min_rank_atomic, TT_BPE_INVALID, memory_order_relaxed);\n"
    @"        atomic_store_explicit(merge_count, 0u, memory_order_relaxed);\n"
    @"    }\n"
    @"}\n"
    @"\n"
    @"kernel void tt_bpe_find_candidates(\n"
    @"    const device uint *tokens [[buffer(0)]],\n"
    @"    const device uint *next [[buffer(1)]],\n"
    @"    device uint *pair_ranks [[buffer(2)]],\n"
    @"    device uint *pair_merged [[buffer(3)]],\n"
    @"    const device tt_rank_entry *rank_table [[buffer(4)]],\n"
    @"    constant uint &node_count [[buffer(5)]],\n"
    @"    constant uint &rank_table_size [[buffer(6)]],\n"
    @"    uint gid [[thread_position_in_grid]]) {\n"
    @"    if (gid >= node_count) {\n"
    @"        return;\n"
    @"    }\n"
    @"    uint right = next[gid];\n"
    @"    if (right == TT_BPE_NULL || right == TT_BPE_DEAD || right >= node_count) {\n"
    @"        pair_ranks[gid] = TT_BPE_INVALID;\n"
    @"        pair_merged[gid] = TT_BPE_INVALID;\n"
    @"        return;\n"
    @"    }\n"
    @"    if (next[gid] == TT_BPE_DEAD) {\n"
    @"        pair_ranks[gid] = TT_BPE_INVALID;\n"
    @"        pair_merged[gid] = TT_BPE_INVALID;\n"
    @"        return;\n"
    @"    }\n"
    @"    if (rank_table_size == 0 || (rank_table_size & (rank_table_size - 1)) != 0) {\n"
    @"        pair_ranks[gid] = TT_BPE_INVALID;\n"
    @"        pair_merged[gid] = TT_BPE_INVALID;\n"
    @"        return;\n"
    @"    }\n"
    @"\n"
    @"    uint rank = TT_BPE_INVALID;\n"
    @"    uint merged = TT_BPE_INVALID;\n"
    @"    const uint left_token = tokens[gid];\n"
    @"    const uint right_token = tokens[right];\n"
    @"    const bool found = tt_rank_lookup(\n"
    @"        rank_table,\n"
    @"        rank_table_size - 1,\n"
    @"        left_token,\n"
    @"        right_token,\n"
    @"        rank,\n"
    @"        merged);\n"
    @"\n"
    @"    if (found) {\n"
    @"        pair_ranks[gid] = rank;\n"
    @"        pair_merged[gid] = merged;\n"
    @"    } else {\n"
    @"        pair_ranks[gid] = TT_BPE_INVALID;\n"
    @"        pair_merged[gid] = TT_BPE_INVALID;\n"
    @"    }\n"
    @"}\n"
    @"\n"
    @"kernel void tt_bpe_find_min_rank(\n"
    @"    const device uint *pair_ranks [[buffer(0)]],\n"
    @"    device atomic_uint *out_min_rank [[buffer(1)]],\n"
    @"    constant uint &node_count [[buffer(2)]],\n"
    @"    uint gid [[thread_position_in_grid]]) {\n"
    @"    if (gid >= node_count) {\n"
    @"        return;\n"
    @"    }\n"
    @"    const uint rank = pair_ranks[gid];\n"
    @"    if (rank != TT_BPE_INVALID) {\n"
    @"        atomic_fetch_min_explicit(out_min_rank, rank, memory_order_relaxed);\n"
    @"    }\n"
    @"}\n"
    @"\n"
    @"kernel void tt_bpe_mark_merges(\n"
    @"    const device uint *prev [[buffer(0)]],\n"
    @"    const device uint *next [[buffer(1)]],\n"
    @"    const device uint *pair_ranks [[buffer(2)]],\n"
    @"    device uint *merge_flags [[buffer(3)]],\n"
    @"    const device atomic_uint *min_rank_atomic [[buffer(4)]],\n"
    @"    constant uint &node_count [[buffer(5)]],\n"
    @"    uint gid [[thread_position_in_grid]]) {\n"
    @"    if (gid >= node_count) {\n"
    @"        return;\n"
    @"    }\n"
    @"\n"
    @"    const uint min_rank = atomic_load_explicit(min_rank_atomic, memory_order_relaxed);\n"
    @"    if (min_rank == TT_BPE_INVALID) {\n"
    @"        merge_flags[gid] = 0u;\n"
    @"        return;\n"
    @"    }\n"
    @"\n"
    @"    const uint right = next[gid];\n"
    @"    if (right == TT_BPE_NULL || right == TT_BPE_DEAD || right >= node_count) {\n"
    @"        merge_flags[gid] = 0u;\n"
    @"        return;\n"
    @"    }\n"
    @"\n"
    @"    const uint rank = pair_ranks[gid];\n"
    @"    if (rank != min_rank) {\n"
    @"        merge_flags[gid] = 0u;\n"
    @"        return;\n"
    @"    }\n"
    @"\n"
    @"    const uint left_prev = prev[gid];\n"
    @"    if (left_prev != TT_BPE_NULL && left_prev != TT_BPE_DEAD && left_prev < node_count) {\n"
    @"        if (next[left_prev] == gid && pair_ranks[left_prev] == min_rank) {\n"
    @"            merge_flags[gid] = 0u;\n"
    @"            return;\n"
    @"        }\n"
    @"    }\n"
    @"\n"
    @"    merge_flags[gid] = 1u;\n"
    @"}\n"
    @"\n"
    @"kernel void tt_bpe_apply_merges(\n"
    @"    device uint *tokens [[buffer(0)]],\n"
    @"    device uint *prev [[buffer(1)]],\n"
    @"    device uint *next [[buffer(2)]],\n"
    @"    const device uint *pair_merged [[buffer(3)]],\n"
    @"    const device uint *merge_flags [[buffer(4)]],\n"
    @"    device atomic_uint *merge_count [[buffer(5)]],\n"
    @"    constant uint &node_count [[buffer(6)]],\n"
    @"    uint gid [[thread_position_in_grid]]) {\n"
    @"    if (gid >= node_count) {\n"
    @"        return;\n"
    @"    }\n"
    @"    if (merge_flags[gid] == 0u) {\n"
    @"        return;\n"
    @"    }\n"
    @"\n"
    @"    const uint right = next[gid];\n"
    @"    if (right == TT_BPE_NULL || right == TT_BPE_DEAD || right >= node_count) {\n"
    @"        return;\n"
    @"    }\n"
    @"\n"
    @"    const uint merged = pair_merged[gid];\n"
    @"    if (merged == TT_BPE_INVALID) {\n"
    @"        return;\n"
    @"    }\n"
    @"\n"
    @"    const uint next_next = next[right];\n"
    @"    tokens[gid] = merged;\n"
    @"    next[gid] = next_next;\n"
    @"    if (next_next != TT_BPE_NULL && next_next != TT_BPE_DEAD && next_next < node_count) {\n"
    @"        prev[next_next] = gid;\n"
    @"    }\n"
    @"\n"
    @"    prev[right] = TT_BPE_DEAD;\n"
    @"    next[right] = TT_BPE_DEAD;\n"
    @"    atomic_fetch_add_explicit(merge_count, 1u, memory_order_relaxed);\n"
    @"}\n";

static pthread_mutex_t g_state_lock = PTHREAD_MUTEX_INITIALIZER;
static bool g_initialized = false;
static char g_last_error[512] = "";

static id<MTLDevice> g_device = nil;
static id<MTLCommandQueue> g_queue = nil;
static id<MTLComputePipelineState> g_encode_pipeline = nil;
static id<MTLComputePipelineState> g_count_pipeline = nil;
static id<MTLComputePipelineState> g_stitch_pipeline = nil;
static id<MTLComputePipelineState> g_bpe_reset_pipeline = nil;
static id<MTLComputePipelineState> g_bpe_find_pipeline = nil;
static id<MTLComputePipelineState> g_bpe_min_pipeline = nil;
static id<MTLComputePipelineState> g_bpe_mark_pipeline = nil;
static id<MTLComputePipelineState> g_bpe_apply_pipeline = nil;

static id<MTLBuffer> g_input_buffer = nil;
static NSUInteger g_input_capacity = 0;
static id<MTLBuffer> g_output_u32_buffer = nil;
static NSUInteger g_output_u32_capacity = 0;
static id<MTLBuffer> g_offsets_u32_buffer = nil;
static NSUInteger g_offsets_u32_capacity = 0;
static id<MTLBuffer> g_bpe_tokens_u32_buffer = nil;
static NSUInteger g_bpe_tokens_u32_capacity = 0;
static id<MTLBuffer> g_bpe_prev_u32_buffer = nil;
static NSUInteger g_bpe_prev_u32_capacity = 0;
static id<MTLBuffer> g_bpe_next_u32_buffer = nil;
static NSUInteger g_bpe_next_u32_capacity = 0;
static id<MTLBuffer> g_bpe_pair_rank_u32_buffer = nil;
static NSUInteger g_bpe_pair_rank_u32_capacity = 0;
static id<MTLBuffer> g_bpe_pair_merged_u32_buffer = nil;
static NSUInteger g_bpe_pair_merged_u32_capacity = 0;
static id<MTLBuffer> g_bpe_merge_flags_u32_buffer = nil;
static NSUInteger g_bpe_merge_flags_u32_capacity = 0;
static id<MTLBuffer> g_bpe_min_rank_u32_buffer = nil;
static NSUInteger g_bpe_min_rank_u32_capacity = 0;
static id<MTLBuffer> g_bpe_merge_count_u32_buffer = nil;
static NSUInteger g_bpe_merge_count_u32_capacity = 0;
static id<MTLBuffer> g_bpe_rank_table_u32_buffer = nil;
static NSUInteger g_bpe_rank_table_u32_capacity = 0;
static uint32_t g_bpe_rank_table_entries = 0;
static bool g_bpe_rank_table_ready = false;
static uint32_t g_bpe_byte_token_map[256];
static bool g_bpe_byte_token_map_ready = false;

static const NSUInteger kEncodeBytesPerThread = 2048;
static const uint32_t kBpeNullIndex = 0xffffffffu;
static const uint32_t kBpeDeadIndex = 0xfffffffeu;
static const uint32_t kBpeInvalid = 0xffffffffu;

static uint64_t g_last_encode_cpu_ns = 0;
static uint64_t g_last_encode_gpu_ns = 0;
static uint64_t g_last_encode_bytes = 0;
static uint64_t g_last_encode_dispatch_threads = 0;

static uint64_t g_last_count_cpu_ns = 0;
static uint64_t g_last_count_gpu_ns = 0;
static uint64_t g_last_count_bytes = 0;
static uint64_t g_last_count_segments = 0;
static uint64_t g_last_count_lanes = 0;

static uint64_t g_last_stitch_cpu_ns = 0;
static uint64_t g_last_stitch_gpu_ns = 0;
static uint64_t g_last_stitch_tokens = 0;
static uint64_t g_last_stitch_chunk_bytes = 0;
static uint64_t g_last_stitch_num_chunks = 0;
static uint64_t g_last_bpe_cpu_ns = 0;
static uint64_t g_last_bpe_gpu_ns = 0;
static uint64_t g_last_bpe_rounds = 0;
static uint64_t g_last_bpe_input_bytes = 0;
static uint64_t g_last_bpe_output_tokens = 0;

static void set_error_locked(const char *message) {
    if (message == NULL || message[0] == '\0') {
        g_last_error[0] = '\0';
        return;
    }
    snprintf(g_last_error, sizeof(g_last_error), "%s", message);
}

static void set_error_ns_locked(const char *prefix, NSError *error) {
    if (error == nil) {
        set_error_locked(prefix);
        return;
    }

    NSString *desc = [error localizedDescription];
    if (desc == nil) {
        set_error_locked(prefix);
        return;
    }

    snprintf(
        g_last_error,
        sizeof(g_last_error),
        "%s: %s",
        prefix,
        [desc UTF8String]
    );
}

static uint64_t monotonic_now_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_UPTIME_RAW, &ts) != 0) {
        return 0;
    }
    return ((uint64_t)ts.tv_sec * 1000000000ull) + (uint64_t)ts.tv_nsec;
}

static uint64_t command_buffer_gpu_ns(id<MTLCommandBuffer> command_buffer) {
    const NSTimeInterval start = [command_buffer GPUStartTime];
    const NSTimeInterval end = [command_buffer GPUEndTime];
    if (end > start && start > 0.0) {
        return (uint64_t)((end - start) * 1000000000.0);
    }
    return 0;
}

static NSUInteger round_capacity(NSUInteger needed) {
    NSUInteger cap = 4096;
    while (cap < needed && cap < (NSUIntegerMax / 2)) {
        cap <<= 1;
    }
    if (cap < needed) {
        return needed;
    }
    return cap;
}

static bool ensure_buffer_locked(
    id<MTLBuffer> __strong *buffer,
    NSUInteger *capacity,
    NSUInteger needed_bytes,
    const char *label
) {
    if (needed_bytes == 0) {
        return true;
    }
    if (*buffer != nil && *capacity >= needed_bytes) {
        return true;
    }

    const NSUInteger target = round_capacity(needed_bytes);
    id<MTLBuffer> next =
        [g_device newBufferWithLength:target options:MTLResourceStorageModeShared];
    if (next == nil) {
        char msg[256];
        snprintf(msg, sizeof(msg), "failed to allocate %s buffer (%lu bytes)", label, (unsigned long)target);
        set_error_locked(msg);
        return false;
    }

    *buffer = next;
    *capacity = target;
    return true;
}

static MTLSize threads_per_group_for(id<MTLComputePipelineState> pipeline) {
    NSUInteger width = [pipeline threadExecutionWidth];
    NSUInteger max_threads = [pipeline maxTotalThreadsPerThreadgroup];

    NSUInteger threads = width > 0 ? width * 8 : 256;
    if (threads > max_threads) {
        threads = max_threads;
    }
    if (threads == 0) {
        threads = 1;
    }
    return MTLSizeMake(threads, 1, 1);
}

static MTLSize encode_threads_per_group_for(id<MTLComputePipelineState> pipeline) {
    NSUInteger width = [pipeline threadExecutionWidth];
    NSUInteger max_threads = [pipeline maxTotalThreadsPerThreadgroup];
    if (width == 0) {
        width = 32;
    }

    // Each thread processes a larger byte chunk, so favor occupancy over giant groups.
    NSUInteger threads = width * 2;
    if (threads > max_threads) {
        threads = max_threads;
    }
    if (threads < width) {
        threads = width;
    }
    if (threads == 0) {
        threads = 1;
    }
    return MTLSizeMake(threads, 1, 1);
}

static NSUInteger floor_power_of_two(NSUInteger value) {
    if (value <= 1) {
        return 1;
    }
    NSUInteger out = 1;
    while ((out << 1) <= value) {
        out <<= 1;
    }
    return out;
}

static bool is_power_of_two_u32(uint32_t value) {
    return value > 0 && (value & (value - 1u)) == 0u;
}

static NSUInteger count_threads_per_group_for(
    id<MTLComputePipelineState> pipeline,
    size_t input_len,
    size_t segment_count
) {
    const NSUInteger max_threads = [pipeline maxTotalThreadsPerThreadgroup];
    const NSUInteger capped = max_threads < 256 ? max_threads : 256;
    if (capped == 0) {
        return 1;
    }

    NSUInteger width = [pipeline threadExecutionWidth];
    if (width == 0) {
        width = 32;
    }
    if (width > capped) {
        width = capped;
    }
    width = floor_power_of_two(width);

    const NSUInteger avg_bytes = segment_count > 0 ? (NSUInteger)(input_len / segment_count) : 0;
    NSUInteger target = width;
    if (avg_bytes >= 4096) {
        target = width * 8;
    } else if (avg_bytes >= 1024) {
        target = width * 4;
    } else if (avg_bytes >= 384) {
        target = width * 2;
    }

    if (target > capped) {
        target = capped;
    }
    if (target < width) {
        target = width;
    }
    return floor_power_of_two(target);
}

static uint32_t bpe_rounds_per_submit(void) {
    const uint32_t default_value = 1u;
    const char *raw = getenv("TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT");
    if (raw == NULL || raw[0] == '\0') {
        return default_value;
    }

    char *end = NULL;
    unsigned long parsed = strtoul(raw, &end, 10);
    if (end == raw || parsed == 0ul) {
        return default_value;
    }
    if (parsed > 32ul) {
        parsed = 32ul;
    }
    return (uint32_t)parsed;
}

static bool init_metal_locked(void) {
    if (g_initialized) {
        return g_device != nil &&
            g_queue != nil &&
            g_encode_pipeline != nil &&
            g_count_pipeline != nil &&
            g_stitch_pipeline != nil &&
            g_bpe_reset_pipeline != nil &&
            g_bpe_find_pipeline != nil &&
            g_bpe_min_pipeline != nil &&
            g_bpe_mark_pipeline != nil &&
            g_bpe_apply_pipeline != nil;
    }
    g_initialized = true;

    @autoreleasepool {
        g_device = MTLCreateSystemDefaultDevice();
        if (g_device == nil) {
            set_error_locked("Metal unavailable: no default device");
            return false;
        }

        g_queue = [g_device newCommandQueue];
        if (g_queue == nil) {
            set_error_locked("Metal unavailable: failed to create command queue");
            return false;
        }

        MTLCompileOptions *opts = [MTLCompileOptions new];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [opts setFastMathEnabled:YES];
#pragma clang diagnostic pop

        NSError *error = nil;
        NSString *full_kernel_source = [kKernelSource stringByAppendingString:kBpeKernelSource];
        id<MTLLibrary> library = [g_device newLibraryWithSource:full_kernel_source options:opts error:&error];
        if (library == nil) {
            set_error_ns_locked("failed to compile Metal kernels", error);
            return false;
        }

        id<MTLFunction> encode_fn = [library newFunctionWithName:@"tt_encode_u8_to_u32"];
        if (encode_fn == nil) {
            set_error_locked("failed to resolve kernel tt_encode_u8_to_u32");
            return false;
        }
        g_encode_pipeline = [g_device newComputePipelineStateWithFunction:encode_fn error:&error];
        if (g_encode_pipeline == nil) {
            set_error_ns_locked("failed to create encode pipeline", error);
            return false;
        }

        id<MTLFunction> count_fn = [library newFunctionWithName:@"tt_count_nonzero_segments"];
        if (count_fn == nil) {
            set_error_locked("failed to resolve kernel tt_count_nonzero_segments");
            return false;
        }
        g_count_pipeline = [g_device newComputePipelineStateWithFunction:count_fn error:&error];
        if (g_count_pipeline == nil) {
            set_error_ns_locked("failed to create count pipeline", error);
            return false;
        }

        id<MTLFunction> stitch_fn = [library newFunctionWithName:@"tt_chunk_owner_flags"];
        if (stitch_fn == nil) {
            set_error_locked("failed to resolve kernel tt_chunk_owner_flags");
            return false;
        }
        g_stitch_pipeline = [g_device newComputePipelineStateWithFunction:stitch_fn error:&error];
        if (g_stitch_pipeline == nil) {
            set_error_ns_locked("failed to create stitch pipeline", error);
            return false;
        }

        id<MTLFunction> bpe_reset_fn = [library newFunctionWithName:@"tt_bpe_reset_counters"];
        if (bpe_reset_fn == nil) {
            set_error_locked("failed to resolve kernel tt_bpe_reset_counters");
            return false;
        }
        g_bpe_reset_pipeline = [g_device newComputePipelineStateWithFunction:bpe_reset_fn error:&error];
        if (g_bpe_reset_pipeline == nil) {
            set_error_ns_locked("failed to create bpe-reset pipeline", error);
            return false;
        }

        id<MTLFunction> bpe_find_fn = [library newFunctionWithName:@"tt_bpe_find_candidates"];
        if (bpe_find_fn == nil) {
            set_error_locked("failed to resolve kernel tt_bpe_find_candidates");
            return false;
        }
        g_bpe_find_pipeline = [g_device newComputePipelineStateWithFunction:bpe_find_fn error:&error];
        if (g_bpe_find_pipeline == nil) {
            set_error_ns_locked("failed to create bpe-find pipeline", error);
            return false;
        }

        id<MTLFunction> bpe_min_fn = [library newFunctionWithName:@"tt_bpe_find_min_rank"];
        if (bpe_min_fn == nil) {
            set_error_locked("failed to resolve kernel tt_bpe_find_min_rank");
            return false;
        }
        g_bpe_min_pipeline = [g_device newComputePipelineStateWithFunction:bpe_min_fn error:&error];
        if (g_bpe_min_pipeline == nil) {
            set_error_ns_locked("failed to create bpe-min pipeline", error);
            return false;
        }

        id<MTLFunction> bpe_mark_fn = [library newFunctionWithName:@"tt_bpe_mark_merges"];
        if (bpe_mark_fn == nil) {
            set_error_locked("failed to resolve kernel tt_bpe_mark_merges");
            return false;
        }
        g_bpe_mark_pipeline = [g_device newComputePipelineStateWithFunction:bpe_mark_fn error:&error];
        if (g_bpe_mark_pipeline == nil) {
            set_error_ns_locked("failed to create bpe-mark pipeline", error);
            return false;
        }

        id<MTLFunction> bpe_apply_fn = [library newFunctionWithName:@"tt_bpe_apply_merges"];
        if (bpe_apply_fn == nil) {
            set_error_locked("failed to resolve kernel tt_bpe_apply_merges");
            return false;
        }
        g_bpe_apply_pipeline = [g_device newComputePipelineStateWithFunction:bpe_apply_fn error:&error];
        if (g_bpe_apply_pipeline == nil) {
            set_error_ns_locked("failed to create bpe-apply pipeline", error);
            return false;
        }
    }

    set_error_locked("");
    return true;
}

static bool wait_for_completion_locked(id<MTLCommandBuffer> command_buffer, const char *label) {
    [command_buffer commit];
    [command_buffer waitUntilCompleted];
    if ([command_buffer status] != MTLCommandBufferStatusCompleted) {
        NSError *error = [command_buffer error];
        set_error_ns_locked(label, error);
        return false;
    }
    return true;
}

static id<MTLCommandBuffer> create_command_buffer_locked(void) {
    if (g_queue == nil) {
        return nil;
    }
    if ([g_queue respondsToSelector:@selector(commandBufferWithUnretainedReferences)]) {
        return [g_queue commandBufferWithUnretainedReferences];
    }
    return [g_queue commandBuffer];
}

const char *turbotoken_metal_version(void) {
    return "metal-byte-path-v7";
}

const char *turbotoken_metal_last_error(void) {
    pthread_mutex_lock(&g_state_lock);
    const char *error = g_last_error[0] == '\0' ? NULL : g_last_error;
    pthread_mutex_unlock(&g_state_lock);
    return error;
}

uint64_t turbotoken_metal_last_encode_cpu_ns(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_encode_cpu_ns;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_encode_gpu_ns(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_encode_gpu_ns;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_encode_bytes(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_encode_bytes;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_encode_dispatch_threads(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_encode_dispatch_threads;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_count_cpu_ns(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_count_cpu_ns;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_count_gpu_ns(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_count_gpu_ns;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_count_bytes(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_count_bytes;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_count_segments(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_count_segments;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_count_lanes(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_count_lanes;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_stitch_cpu_ns(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_stitch_cpu_ns;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_stitch_gpu_ns(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_stitch_gpu_ns;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_stitch_tokens(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_stitch_tokens;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_stitch_chunk_bytes(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_stitch_chunk_bytes;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_stitch_num_chunks(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_stitch_num_chunks;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_bpe_cpu_ns(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_bpe_cpu_ns;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_bpe_gpu_ns(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_bpe_gpu_ns;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_bpe_rounds(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_bpe_rounds;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_bpe_input_bytes(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_bpe_input_bytes;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

uint64_t turbotoken_metal_last_bpe_output_tokens(void) {
    pthread_mutex_lock(&g_state_lock);
    const uint64_t value = g_last_bpe_output_tokens;
    pthread_mutex_unlock(&g_state_lock);
    return value;
}

int turbotoken_metal_available(void) {
    pthread_mutex_lock(&g_state_lock);
    const bool ok = init_metal_locked();
    pthread_mutex_unlock(&g_state_lock);
    return ok ? 1 : 0;
}

long turbotoken_metal_encode_utf8_bytes(
    const unsigned char *input,
    size_t input_len,
    uint32_t *out_tokens,
    size_t out_cap
) {
    if (input_len > UINT32_MAX) {
        return -1;
    }
    if (input_len > 0 && input == NULL) {
        return -1;
    }
    if (out_tokens == NULL || out_cap == 0) {
        return (long)input_len;
    }
    if (out_cap < input_len) {
        return -1;
    }
    if (input_len == 0) {
        return 0;
    }

    pthread_mutex_lock(&g_state_lock);
    if (!init_metal_locked()) {
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }

    const NSUInteger in_bytes = (NSUInteger)input_len;
    const NSUInteger out_bytes = (NSUInteger)input_len * sizeof(uint32_t);
    const uint64_t cpu_start_ns = monotonic_now_ns();

    id<MTLBuffer> input_buffer = [g_device newBufferWithBytesNoCopy:(void *)input
                                                              length:in_bytes
                                                             options:MTLResourceStorageModeShared
                                                         deallocator:nil];
    if (input_buffer == nil) {
        if (!ensure_buffer_locked(&g_input_buffer, &g_input_capacity, in_bytes, "input")) {
            pthread_mutex_unlock(&g_state_lock);
            return -1;
        }
        memcpy([g_input_buffer contents], input, in_bytes);
        input_buffer = g_input_buffer;
    }

    bool needs_output_copy = false;
    id<MTLBuffer> output_buffer = [g_device newBufferWithBytesNoCopy:(void *)out_tokens
                                                               length:out_bytes
                                                              options:MTLResourceStorageModeShared
                                                          deallocator:nil];
    if (output_buffer == nil) {
        if (!ensure_buffer_locked(&g_output_u32_buffer, &g_output_u32_capacity, out_bytes, "output")) {
            pthread_mutex_unlock(&g_state_lock);
            return -1;
        }
        output_buffer = g_output_u32_buffer;
        needs_output_copy = true;
    }

    id<MTLCommandBuffer> command_buffer = create_command_buffer_locked();
    if (command_buffer == nil) {
        set_error_locked("failed to create command buffer");
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }

    id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];
    if (encoder == nil) {
        set_error_locked("failed to create compute command encoder");
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }

    const uint32_t total_len_u32 = (uint32_t)input_len;
    [encoder setComputePipelineState:g_encode_pipeline];
    [encoder setBuffer:input_buffer offset:0 atIndex:0];
    [encoder setBuffer:output_buffer offset:0 atIndex:1];
    [encoder setBytes:&total_len_u32 length:sizeof(total_len_u32) atIndex:2];

    const NSUInteger bytes_per_thread = kEncodeBytesPerThread;
    const NSUInteger dispatch_threads = (in_bytes + bytes_per_thread - 1) / bytes_per_thread;
    const MTLSize grid = MTLSizeMake(dispatch_threads, 1, 1);
    const MTLSize threads = encode_threads_per_group_for(g_encode_pipeline);
    [encoder dispatchThreads:grid threadsPerThreadgroup:threads];
    [encoder endEncoding];

    if (!wait_for_completion_locked(command_buffer, "encode command failed")) {
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }

    if (needs_output_copy) {
        memcpy(out_tokens, [output_buffer contents], out_bytes);
    }
    const uint64_t cpu_end_ns = monotonic_now_ns();
    g_last_encode_cpu_ns = (cpu_end_ns >= cpu_start_ns) ? (cpu_end_ns - cpu_start_ns) : 0;
    g_last_encode_gpu_ns = command_buffer_gpu_ns(command_buffer);
    g_last_encode_bytes = (uint64_t)in_bytes;
    g_last_encode_dispatch_threads = (uint64_t)dispatch_threads;
    pthread_mutex_unlock(&g_state_lock);
    return (long)input_len;
}

long turbotoken_metal_count_nonzero_segments(
    const unsigned char *input,
    size_t input_len,
    const uint32_t *offsets,
    size_t offsets_len,
    uint32_t *out_counts,
    size_t out_cap
) {
    if (offsets_len < 2 || offsets == NULL) {
        return -1;
    }
    if (input_len > UINT32_MAX) {
        return -1;
    }
    if (input_len > 0 && input == NULL) {
        return -1;
    }

    const size_t segment_count = offsets_len - 1;
    if (segment_count > UINT32_MAX) {
        return -1;
    }
    if (out_counts == NULL || out_cap == 0) {
        return (long)segment_count;
    }
    if (out_cap < segment_count) {
        return -1;
    }

    uint32_t prev = offsets[0];
    if (prev != 0) {
        return -1;
    }
    for (size_t idx = 1; idx < offsets_len; idx += 1) {
        const uint32_t next = offsets[idx];
        if (next < prev || next > input_len) {
            return -1;
        }
        prev = next;
    }

    if (segment_count == 0) {
        return 0;
    }
    if (input_len == 0) {
        memset(out_counts, 0, segment_count * sizeof(uint32_t));
        return (long)segment_count;
    }

    pthread_mutex_lock(&g_state_lock);
    if (!init_metal_locked()) {
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }

    const NSUInteger in_bytes = (NSUInteger)input_len;
    const NSUInteger offsets_bytes = (NSUInteger)offsets_len * sizeof(uint32_t);
    const NSUInteger out_bytes = (NSUInteger)segment_count * sizeof(uint32_t);
    const uint64_t cpu_start_ns = monotonic_now_ns();

    id<MTLBuffer> input_buffer = [g_device newBufferWithBytesNoCopy:(void *)input
                                                              length:in_bytes
                                                             options:MTLResourceStorageModeShared
                                                         deallocator:nil];
    if (input_buffer == nil) {
        if (!ensure_buffer_locked(&g_input_buffer, &g_input_capacity, in_bytes, "input")) {
            pthread_mutex_unlock(&g_state_lock);
            return -1;
        }
        memcpy([g_input_buffer contents], input, in_bytes);
        input_buffer = g_input_buffer;
    }

    id<MTLBuffer> offsets_buffer = [g_device newBufferWithBytesNoCopy:(void *)offsets
                                                                length:offsets_bytes
                                                               options:MTLResourceStorageModeShared
                                                           deallocator:nil];
    if (offsets_buffer == nil) {
        if (!ensure_buffer_locked(&g_offsets_u32_buffer, &g_offsets_u32_capacity, offsets_bytes, "offsets")) {
            pthread_mutex_unlock(&g_state_lock);
            return -1;
        }
        memcpy([g_offsets_u32_buffer contents], offsets, offsets_bytes);
        offsets_buffer = g_offsets_u32_buffer;
    }

    bool needs_output_copy = false;
    id<MTLBuffer> output_buffer = [g_device newBufferWithBytesNoCopy:(void *)out_counts
                                                               length:out_bytes
                                                              options:MTLResourceStorageModeShared
                                                          deallocator:nil];
    if (output_buffer == nil) {
        if (!ensure_buffer_locked(&g_output_u32_buffer, &g_output_u32_capacity, out_bytes, "output")) {
            pthread_mutex_unlock(&g_state_lock);
            return -1;
        }
        output_buffer = g_output_u32_buffer;
        needs_output_copy = true;
    }

    id<MTLCommandBuffer> command_buffer = create_command_buffer_locked();
    if (command_buffer == nil) {
        set_error_locked("failed to create command buffer");
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }

    id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];
    if (encoder == nil) {
        set_error_locked("failed to create compute command encoder");
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }

    const uint32_t segment_count_u32 = (uint32_t)segment_count;
    [encoder setComputePipelineState:g_count_pipeline];
    [encoder setBuffer:input_buffer offset:0 atIndex:0];
    [encoder setBuffer:offsets_buffer offset:0 atIndex:1];
    [encoder setBuffer:output_buffer offset:0 atIndex:2];
    [encoder setBytes:&segment_count_u32 length:sizeof(segment_count_u32) atIndex:3];

    const NSUInteger lanes =
        count_threads_per_group_for(g_count_pipeline, input_len, segment_count);
    const MTLSize groups = MTLSizeMake((NSUInteger)segment_count, 1, 1);
    const MTLSize threads = MTLSizeMake(lanes, 1, 1);
    [encoder dispatchThreadgroups:groups threadsPerThreadgroup:threads];
    [encoder endEncoding];

    if (!wait_for_completion_locked(command_buffer, "count command failed")) {
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }

    if (needs_output_copy) {
        memcpy(out_counts, [output_buffer contents], out_bytes);
    }
    const uint64_t cpu_end_ns = monotonic_now_ns();
    g_last_count_cpu_ns = (cpu_end_ns >= cpu_start_ns) ? (cpu_end_ns - cpu_start_ns) : 0;
    g_last_count_gpu_ns = command_buffer_gpu_ns(command_buffer);
    g_last_count_bytes = (uint64_t)in_bytes;
    g_last_count_segments = (uint64_t)segment_count;
    g_last_count_lanes = (uint64_t)lanes;
    pthread_mutex_unlock(&g_state_lock);
    return (long)segment_count;
}

long turbotoken_metal_count_nonzero_bytes(const unsigned char *input, size_t input_len) {
    if (input_len == 0) {
        return 0;
    }
    if (input_len > UINT32_MAX) {
        return -1;
    }

    uint32_t offsets[2];
    offsets[0] = 0;
    offsets[1] = (uint32_t)input_len;

    uint32_t count = 0;
    const long rc = turbotoken_metal_count_nonzero_segments(
        input,
        input_len,
        offsets,
        2,
        &count,
        1
    );
    if (rc < 0) {
        return -1;
    }
    return (long)count;
}

long turbotoken_metal_chunk_owner_flags(
    const uint32_t *token_starts,
    const uint32_t *source_chunks,
    size_t token_len,
    uint32_t chunk_bytes,
    uint32_t num_chunks,
    uint32_t *out_flags,
    size_t out_cap
) {
    if (token_len > UINT32_MAX) {
        return -1;
    }
    if (token_len > 0 && (token_starts == NULL || source_chunks == NULL)) {
        return -1;
    }
    if (out_flags == NULL || out_cap == 0) {
        return (long)token_len;
    }
    if (out_cap < token_len) {
        return -1;
    }
    if (token_len == 0) {
        return 0;
    }
    if (chunk_bytes == 0 || num_chunks == 0) {
        return -1;
    }

    pthread_mutex_lock(&g_state_lock);
    if (!init_metal_locked()) {
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }

    const NSUInteger token_bytes = (NSUInteger)token_len * sizeof(uint32_t);
    const uint64_t cpu_start_ns = monotonic_now_ns();

    id<MTLBuffer> starts_buffer = [g_device newBufferWithBytesNoCopy:(void *)token_starts
                                                               length:token_bytes
                                                              options:MTLResourceStorageModeShared
                                                          deallocator:nil];
    if (starts_buffer == nil) {
        if (!ensure_buffer_locked(&g_offsets_u32_buffer, &g_offsets_u32_capacity, token_bytes, "token-states")) {
            pthread_mutex_unlock(&g_state_lock);
            return -1;
        }
        memcpy([g_offsets_u32_buffer contents], token_starts, token_bytes);
        starts_buffer = g_offsets_u32_buffer;
    }

    id<MTLBuffer> source_chunk_buffer = [g_device newBufferWithBytesNoCopy:(void *)source_chunks
                                                                     length:token_bytes
                                                                    options:MTLResourceStorageModeShared
                                                                deallocator:nil];
    if (source_chunk_buffer == nil) {
        if (!ensure_buffer_locked(&g_input_buffer, &g_input_capacity, token_bytes, "source-chunks")) {
            pthread_mutex_unlock(&g_state_lock);
            return -1;
        }
        memcpy([g_input_buffer contents], source_chunks, token_bytes);
        source_chunk_buffer = g_input_buffer;
    }

    bool needs_output_copy = false;
    id<MTLBuffer> output_buffer = [g_device newBufferWithBytesNoCopy:(void *)out_flags
                                                               length:token_bytes
                                                              options:MTLResourceStorageModeShared
                                                          deallocator:nil];
    if (output_buffer == nil) {
        if (!ensure_buffer_locked(&g_output_u32_buffer, &g_output_u32_capacity, token_bytes, "stitch-output")) {
            pthread_mutex_unlock(&g_state_lock);
            return -1;
        }
        output_buffer = g_output_u32_buffer;
        needs_output_copy = true;
    }

    id<MTLCommandBuffer> command_buffer = create_command_buffer_locked();
    if (command_buffer == nil) {
        set_error_locked("failed to create command buffer");
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }

    id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];
    if (encoder == nil) {
        set_error_locked("failed to create compute command encoder");
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }

    const uint32_t token_len_u32 = (uint32_t)token_len;
    [encoder setComputePipelineState:g_stitch_pipeline];
    [encoder setBuffer:starts_buffer offset:0 atIndex:0];
    [encoder setBuffer:source_chunk_buffer offset:0 atIndex:1];
    [encoder setBuffer:output_buffer offset:0 atIndex:2];
    [encoder setBytes:&token_len_u32 length:sizeof(token_len_u32) atIndex:3];
    [encoder setBytes:&chunk_bytes length:sizeof(chunk_bytes) atIndex:4];
    [encoder setBytes:&num_chunks length:sizeof(num_chunks) atIndex:5];

    const MTLSize grid = MTLSizeMake((NSUInteger)token_len, 1, 1);
    const MTLSize threads = threads_per_group_for(g_stitch_pipeline);
    [encoder dispatchThreads:grid threadsPerThreadgroup:threads];
    [encoder endEncoding];

    if (!wait_for_completion_locked(command_buffer, "stitch command failed")) {
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }

    if (needs_output_copy) {
        memcpy(out_flags, [output_buffer contents], token_bytes);
    }
    const uint64_t cpu_end_ns = monotonic_now_ns();
    g_last_stitch_cpu_ns = (cpu_end_ns >= cpu_start_ns) ? (cpu_end_ns - cpu_start_ns) : 0;
    g_last_stitch_gpu_ns = command_buffer_gpu_ns(command_buffer);
    g_last_stitch_tokens = (uint64_t)token_len;
    g_last_stitch_chunk_bytes = (uint64_t)chunk_bytes;
    g_last_stitch_num_chunks = (uint64_t)num_chunks;
    pthread_mutex_unlock(&g_state_lock);
    return (long)token_len;
}

long turbotoken_metal_bpe_set_rank_table(
    const uint32_t *entries_u32,
    size_t entry_u32_len
) {
    if (entries_u32 == NULL || entry_u32_len == 0) {
        return -1;
    }
    if ((entry_u32_len % 4) != 0) {
        return -1;
    }

    const size_t entry_count = entry_u32_len / 4;
    if (entry_count == 0 || entry_count > UINT32_MAX) {
        return -1;
    }
    if (!is_power_of_two_u32((uint32_t)entry_count)) {
        return -1;
    }

    const NSUInteger bytes = (NSUInteger)entry_u32_len * sizeof(uint32_t);
    pthread_mutex_lock(&g_state_lock);
    if (!init_metal_locked()) {
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }
    if (!ensure_buffer_locked(
            &g_bpe_rank_table_u32_buffer,
            &g_bpe_rank_table_u32_capacity,
            bytes,
            "bpe-rank-table")) {
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }

    memcpy([g_bpe_rank_table_u32_buffer contents], entries_u32, bytes);
    g_bpe_rank_table_entries = (uint32_t)entry_count;
    g_bpe_rank_table_ready = true;
    pthread_mutex_unlock(&g_state_lock);
    return (long)entry_count;
}

long turbotoken_metal_bpe_set_byte_token_map(
    const uint32_t *byte_tokens,
    size_t byte_tokens_len
) {
    if (byte_tokens == NULL || byte_tokens_len != 256) {
        return -1;
    }

    pthread_mutex_lock(&g_state_lock);
    memcpy(g_bpe_byte_token_map, byte_tokens, 256 * sizeof(uint32_t));
    g_bpe_byte_token_map_ready = true;
    pthread_mutex_unlock(&g_state_lock);
    return 256;
}

long turbotoken_metal_bpe_encode_from_bytes(
    const unsigned char *input,
    size_t input_len,
    uint32_t *out_tokens,
    size_t out_cap
) {
    if (input_len > UINT32_MAX) {
        return -1;
    }
    if (input_len > 0 && input == NULL) {
        return -1;
    }
    if (out_tokens == NULL || out_cap == 0) {
        return (long)input_len;
    }
    if (out_cap < input_len) {
        return -1;
    }
    if (input_len == 0) {
        return 0;
    }

    pthread_mutex_lock(&g_state_lock);
    if (!init_metal_locked()) {
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }
    if (!g_bpe_rank_table_ready || !g_bpe_byte_token_map_ready || g_bpe_rank_table_entries == 0) {
        set_error_locked("bpe rank table or byte-token map not initialized");
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }

    const NSUInteger node_count = (NSUInteger)input_len;
    const NSUInteger node_bytes = node_count * sizeof(uint32_t);
    const uint64_t cpu_start_ns = monotonic_now_ns();
    uint64_t total_gpu_ns = 0;

    if (!ensure_buffer_locked(&g_bpe_tokens_u32_buffer, &g_bpe_tokens_u32_capacity, node_bytes, "bpe-tokens") ||
        !ensure_buffer_locked(&g_bpe_prev_u32_buffer, &g_bpe_prev_u32_capacity, node_bytes, "bpe-prev") ||
        !ensure_buffer_locked(&g_bpe_next_u32_buffer, &g_bpe_next_u32_capacity, node_bytes, "bpe-next") ||
        !ensure_buffer_locked(&g_bpe_pair_rank_u32_buffer, &g_bpe_pair_rank_u32_capacity, node_bytes, "bpe-pair-rank") ||
        !ensure_buffer_locked(&g_bpe_pair_merged_u32_buffer, &g_bpe_pair_merged_u32_capacity, node_bytes, "bpe-pair-merged") ||
        !ensure_buffer_locked(&g_bpe_merge_flags_u32_buffer, &g_bpe_merge_flags_u32_capacity, node_bytes, "bpe-merge-flags") ||
        !ensure_buffer_locked(&g_bpe_min_rank_u32_buffer, &g_bpe_min_rank_u32_capacity, sizeof(uint32_t), "bpe-min-rank") ||
        !ensure_buffer_locked(
            &g_bpe_merge_count_u32_buffer,
            &g_bpe_merge_count_u32_capacity,
            sizeof(uint32_t),
            "bpe-merge-count")) {
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }

    uint32_t *tokens_ptr = (uint32_t *)[g_bpe_tokens_u32_buffer contents];
    uint32_t *prev_ptr = (uint32_t *)[g_bpe_prev_u32_buffer contents];
    uint32_t *next_ptr = (uint32_t *)[g_bpe_next_u32_buffer contents];
    for (NSUInteger idx = 0; idx < node_count; idx += 1) {
        tokens_ptr[idx] = g_bpe_byte_token_map[input[idx]];
        prev_ptr[idx] = (idx == 0) ? kBpeNullIndex : (uint32_t)(idx - 1);
        next_ptr[idx] = (idx + 1 < node_count) ? (uint32_t)(idx + 1) : kBpeNullIndex;
    }

    const uint32_t node_count_u32 = (uint32_t)node_count;
    const uint32_t rank_table_entries_u32 = g_bpe_rank_table_entries;
    const uint32_t rounds_per_submit = bpe_rounds_per_submit();
    uint32_t rounds = 0;

    if (rounds_per_submit <= 1u) {
        while (rounds < node_count_u32) {
            rounds += 1;
            *(uint32_t *)[g_bpe_min_rank_u32_buffer contents] = kBpeInvalid;
            *(uint32_t *)[g_bpe_merge_count_u32_buffer contents] = 0;

            id<MTLCommandBuffer> command_buffer = create_command_buffer_locked();
            if (command_buffer == nil) {
                set_error_locked("failed to create bpe command buffer");
                pthread_mutex_unlock(&g_state_lock);
                return -1;
            }

            id<MTLComputeCommandEncoder> find_encoder = [command_buffer computeCommandEncoder];
            if (find_encoder == nil) {
                set_error_locked("failed to create bpe-find encoder");
                pthread_mutex_unlock(&g_state_lock);
                return -1;
            }
            [find_encoder setComputePipelineState:g_bpe_find_pipeline];
            [find_encoder setBuffer:g_bpe_tokens_u32_buffer offset:0 atIndex:0];
            [find_encoder setBuffer:g_bpe_next_u32_buffer offset:0 atIndex:1];
            [find_encoder setBuffer:g_bpe_pair_rank_u32_buffer offset:0 atIndex:2];
            [find_encoder setBuffer:g_bpe_pair_merged_u32_buffer offset:0 atIndex:3];
            [find_encoder setBuffer:g_bpe_rank_table_u32_buffer offset:0 atIndex:4];
            [find_encoder setBytes:&node_count_u32 length:sizeof(node_count_u32) atIndex:5];
            [find_encoder setBytes:&rank_table_entries_u32 length:sizeof(rank_table_entries_u32) atIndex:6];
            [find_encoder dispatchThreads:MTLSizeMake(node_count, 1, 1)
                      threadsPerThreadgroup:threads_per_group_for(g_bpe_find_pipeline)];
            [find_encoder endEncoding];

            id<MTLComputeCommandEncoder> min_encoder = [command_buffer computeCommandEncoder];
            if (min_encoder == nil) {
                set_error_locked("failed to create bpe-min encoder");
                pthread_mutex_unlock(&g_state_lock);
                return -1;
            }
            [min_encoder setComputePipelineState:g_bpe_min_pipeline];
            [min_encoder setBuffer:g_bpe_pair_rank_u32_buffer offset:0 atIndex:0];
            [min_encoder setBuffer:g_bpe_min_rank_u32_buffer offset:0 atIndex:1];
            [min_encoder setBytes:&node_count_u32 length:sizeof(node_count_u32) atIndex:2];
            [min_encoder dispatchThreads:MTLSizeMake(node_count, 1, 1)
                     threadsPerThreadgroup:threads_per_group_for(g_bpe_min_pipeline)];
            [min_encoder endEncoding];

            id<MTLComputeCommandEncoder> mark_encoder = [command_buffer computeCommandEncoder];
            if (mark_encoder == nil) {
                set_error_locked("failed to create bpe-mark encoder");
                pthread_mutex_unlock(&g_state_lock);
                return -1;
            }
            [mark_encoder setComputePipelineState:g_bpe_mark_pipeline];
            [mark_encoder setBuffer:g_bpe_prev_u32_buffer offset:0 atIndex:0];
            [mark_encoder setBuffer:g_bpe_next_u32_buffer offset:0 atIndex:1];
            [mark_encoder setBuffer:g_bpe_pair_rank_u32_buffer offset:0 atIndex:2];
            [mark_encoder setBuffer:g_bpe_merge_flags_u32_buffer offset:0 atIndex:3];
            [mark_encoder setBuffer:g_bpe_min_rank_u32_buffer offset:0 atIndex:4];
            [mark_encoder setBytes:&node_count_u32 length:sizeof(node_count_u32) atIndex:5];
            [mark_encoder dispatchThreads:MTLSizeMake(node_count, 1, 1)
                      threadsPerThreadgroup:threads_per_group_for(g_bpe_mark_pipeline)];
            [mark_encoder endEncoding];

            id<MTLComputeCommandEncoder> apply_encoder = [command_buffer computeCommandEncoder];
            if (apply_encoder == nil) {
                set_error_locked("failed to create bpe-apply encoder");
                pthread_mutex_unlock(&g_state_lock);
                return -1;
            }
            [apply_encoder setComputePipelineState:g_bpe_apply_pipeline];
            [apply_encoder setBuffer:g_bpe_tokens_u32_buffer offset:0 atIndex:0];
            [apply_encoder setBuffer:g_bpe_prev_u32_buffer offset:0 atIndex:1];
            [apply_encoder setBuffer:g_bpe_next_u32_buffer offset:0 atIndex:2];
            [apply_encoder setBuffer:g_bpe_pair_merged_u32_buffer offset:0 atIndex:3];
            [apply_encoder setBuffer:g_bpe_merge_flags_u32_buffer offset:0 atIndex:4];
            [apply_encoder setBuffer:g_bpe_merge_count_u32_buffer offset:0 atIndex:5];
            [apply_encoder setBytes:&node_count_u32 length:sizeof(node_count_u32) atIndex:6];
            [apply_encoder dispatchThreads:MTLSizeMake(node_count, 1, 1)
                       threadsPerThreadgroup:threads_per_group_for(g_bpe_apply_pipeline)];
            [apply_encoder endEncoding];

            if (!wait_for_completion_locked(command_buffer, "bpe command failed")) {
                pthread_mutex_unlock(&g_state_lock);
                return -1;
            }

            total_gpu_ns += command_buffer_gpu_ns(command_buffer);
            const uint32_t merges = *(uint32_t *)[g_bpe_merge_count_u32_buffer contents];
            if (merges == 0) {
                break;
            }
        }
    } else {
        const MTLSize node_grid = MTLSizeMake(node_count, 1, 1);
        const MTLSize reset_grid = MTLSizeMake(1, 1, 1);
        const MTLSize reset_threads = threads_per_group_for(g_bpe_reset_pipeline);
        const MTLSize find_threads = threads_per_group_for(g_bpe_find_pipeline);
        const MTLSize min_threads = threads_per_group_for(g_bpe_min_pipeline);
        const MTLSize mark_threads = threads_per_group_for(g_bpe_mark_pipeline);
        const MTLSize apply_threads = threads_per_group_for(g_bpe_apply_pipeline);

        while (rounds < node_count_u32) {
            const uint32_t remaining = node_count_u32 - rounds;
            const uint32_t batch_rounds =
                remaining < rounds_per_submit ? remaining : rounds_per_submit;

            *(uint32_t *)[g_bpe_min_rank_u32_buffer contents] = kBpeInvalid;
            *(uint32_t *)[g_bpe_merge_count_u32_buffer contents] = 0u;

            id<MTLCommandBuffer> command_buffer = create_command_buffer_locked();
            if (command_buffer == nil) {
                set_error_locked("failed to create bpe command buffer");
                pthread_mutex_unlock(&g_state_lock);
                return -1;
            }

            id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];
            if (encoder == nil) {
                set_error_locked("failed to create bpe encoder");
                pthread_mutex_unlock(&g_state_lock);
                return -1;
            }

            for (uint32_t round_idx = 0; round_idx < batch_rounds; round_idx += 1) {
                if (round_idx > 0u) {
                    [encoder setComputePipelineState:g_bpe_reset_pipeline];
                    [encoder setBuffer:g_bpe_min_rank_u32_buffer offset:0 atIndex:0];
                    [encoder setBuffer:g_bpe_merge_count_u32_buffer offset:0 atIndex:1];
                    [encoder dispatchThreads:reset_grid threadsPerThreadgroup:reset_threads];
                }

                [encoder setComputePipelineState:g_bpe_find_pipeline];
                [encoder setBuffer:g_bpe_tokens_u32_buffer offset:0 atIndex:0];
                [encoder setBuffer:g_bpe_next_u32_buffer offset:0 atIndex:1];
                [encoder setBuffer:g_bpe_pair_rank_u32_buffer offset:0 atIndex:2];
                [encoder setBuffer:g_bpe_pair_merged_u32_buffer offset:0 atIndex:3];
                [encoder setBuffer:g_bpe_rank_table_u32_buffer offset:0 atIndex:4];
                [encoder setBytes:&node_count_u32 length:sizeof(node_count_u32) atIndex:5];
                [encoder setBytes:&rank_table_entries_u32 length:sizeof(rank_table_entries_u32) atIndex:6];
                [encoder dispatchThreads:node_grid threadsPerThreadgroup:find_threads];

                [encoder setComputePipelineState:g_bpe_min_pipeline];
                [encoder setBuffer:g_bpe_pair_rank_u32_buffer offset:0 atIndex:0];
                [encoder setBuffer:g_bpe_min_rank_u32_buffer offset:0 atIndex:1];
                [encoder setBytes:&node_count_u32 length:sizeof(node_count_u32) atIndex:2];
                [encoder dispatchThreads:node_grid threadsPerThreadgroup:min_threads];

                [encoder setComputePipelineState:g_bpe_mark_pipeline];
                [encoder setBuffer:g_bpe_prev_u32_buffer offset:0 atIndex:0];
                [encoder setBuffer:g_bpe_next_u32_buffer offset:0 atIndex:1];
                [encoder setBuffer:g_bpe_pair_rank_u32_buffer offset:0 atIndex:2];
                [encoder setBuffer:g_bpe_merge_flags_u32_buffer offset:0 atIndex:3];
                [encoder setBuffer:g_bpe_min_rank_u32_buffer offset:0 atIndex:4];
                [encoder setBytes:&node_count_u32 length:sizeof(node_count_u32) atIndex:5];
                [encoder dispatchThreads:node_grid threadsPerThreadgroup:mark_threads];

                [encoder setComputePipelineState:g_bpe_apply_pipeline];
                [encoder setBuffer:g_bpe_tokens_u32_buffer offset:0 atIndex:0];
                [encoder setBuffer:g_bpe_prev_u32_buffer offset:0 atIndex:1];
                [encoder setBuffer:g_bpe_next_u32_buffer offset:0 atIndex:2];
                [encoder setBuffer:g_bpe_pair_merged_u32_buffer offset:0 atIndex:3];
                [encoder setBuffer:g_bpe_merge_flags_u32_buffer offset:0 atIndex:4];
                [encoder setBuffer:g_bpe_merge_count_u32_buffer offset:0 atIndex:5];
                [encoder setBytes:&node_count_u32 length:sizeof(node_count_u32) atIndex:6];
                [encoder dispatchThreads:node_grid threadsPerThreadgroup:apply_threads];
            }

            [encoder endEncoding];

            if (!wait_for_completion_locked(command_buffer, "bpe command failed")) {
                pthread_mutex_unlock(&g_state_lock);
                return -1;
            }

            total_gpu_ns += command_buffer_gpu_ns(command_buffer);
            rounds += batch_rounds;
            const uint32_t merges = *(uint32_t *)[g_bpe_merge_count_u32_buffer contents];
            if (merges == 0) {
                break;
            }
        }
    }

    uint32_t head = kBpeNullIndex;
    for (uint32_t idx = 0; idx < node_count_u32; idx += 1) {
        if (prev_ptr[idx] == kBpeNullIndex && next_ptr[idx] != kBpeDeadIndex) {
            head = idx;
            break;
        }
    }
    if (head == kBpeNullIndex) {
        set_error_locked("bpe output head not found");
        pthread_mutex_unlock(&g_state_lock);
        return -1;
    }

    size_t written = 0;
    uint32_t cursor = head;
    while (cursor != kBpeNullIndex) {
        if (cursor >= node_count_u32) {
            set_error_locked("bpe output cursor out of bounds");
            pthread_mutex_unlock(&g_state_lock);
            return -1;
        }
        if (next_ptr[cursor] == kBpeDeadIndex) {
            set_error_locked("bpe output encountered dead node");
            pthread_mutex_unlock(&g_state_lock);
            return -1;
        }
        if (written >= out_cap) {
            pthread_mutex_unlock(&g_state_lock);
            return -1;
        }
        out_tokens[written] = tokens_ptr[cursor];
        written += 1;
        cursor = next_ptr[cursor];
    }

    const uint64_t cpu_end_ns = monotonic_now_ns();
    g_last_bpe_cpu_ns = (cpu_end_ns >= cpu_start_ns) ? (cpu_end_ns - cpu_start_ns) : 0;
    g_last_bpe_gpu_ns = total_gpu_ns;
    g_last_bpe_rounds = rounds;
    g_last_bpe_input_bytes = (uint64_t)input_len;
    g_last_bpe_output_tokens = (uint64_t)written;

    pthread_mutex_unlock(&g_state_lock);
    return (long)written;
}
