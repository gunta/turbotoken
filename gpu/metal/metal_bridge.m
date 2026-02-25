#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static NSString *const kKernelSource =
    @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"\n"
    @"constant uint TT_ENCODE_BYTES_PER_THREAD = 512;\n"
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
    @"    for (; idx + 32 <= end; idx += 32) {\n"
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
    @"    for (; idx + (stride * 7) < end; idx += stride * 8) {\n"
    @"        local_total += input[idx] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + stride] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 2)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 3)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 4)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 5)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 6)] != 0 ? 1u : 0u;\n"
    @"        local_total += input[idx + (stride * 7)] != 0 ? 1u : 0u;\n"
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

static pthread_mutex_t g_state_lock = PTHREAD_MUTEX_INITIALIZER;
static bool g_initialized = false;
static char g_last_error[512] = "";

static id<MTLDevice> g_device = nil;
static id<MTLCommandQueue> g_queue = nil;
static id<MTLComputePipelineState> g_encode_pipeline = nil;
static id<MTLComputePipelineState> g_count_pipeline = nil;
static id<MTLComputePipelineState> g_stitch_pipeline = nil;

static id<MTLBuffer> g_input_buffer = nil;
static NSUInteger g_input_capacity = 0;
static id<MTLBuffer> g_output_u32_buffer = nil;
static NSUInteger g_output_u32_capacity = 0;
static id<MTLBuffer> g_offsets_u32_buffer = nil;
static NSUInteger g_offsets_u32_capacity = 0;

static const NSUInteger kEncodeBytesPerThread = 512;

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
    } else if (avg_bytes >= 1536) {
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

static bool init_metal_locked(void) {
    if (g_initialized) {
        return g_device != nil &&
            g_queue != nil &&
            g_encode_pipeline != nil &&
            g_count_pipeline != nil &&
            g_stitch_pipeline != nil;
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
        id<MTLLibrary> library = [g_device newLibraryWithSource:kKernelSource options:opts error:&error];
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

const char *turbotoken_metal_version(void) {
    return "metal-byte-path-v4";
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

    id<MTLCommandBuffer> command_buffer = [g_queue commandBuffer];
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

    id<MTLCommandBuffer> command_buffer = [g_queue commandBuffer];
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

    id<MTLCommandBuffer> command_buffer = [g_queue commandBuffer];
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
