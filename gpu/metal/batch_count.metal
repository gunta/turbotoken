#include <metal_stdlib>
using namespace metal;

kernel void tt_count_nonzero_segments(
    device const uchar *input [[buffer(0)]],
    device const uint *offsets [[buffer(1)]],
    device uint *output [[buffer(2)]],
    constant uint &segment_count [[buffer(3)]],
    uint segment_id [[threadgroup_position_in_grid]],
    uint lane_id [[thread_index_in_threadgroup]],
    uint lanes_per_group [[threads_per_threadgroup]],
    uint simdgroup_id [[simdgroup_index_in_threadgroup]],
    uint simdgroups_per_group [[simdgroups_per_threadgroup]]
) {
    if (segment_id >= segment_count) {
        return;
    }

    uint start = offsets[segment_id];
    uint end = offsets[segment_id + 1];
    uint local_total = 0;
    uint idx = start + lane_id;
    uint stride = lanes_per_group;
    for (; idx + (stride * 15) < end; idx += stride * 16) {
        local_total += input[idx] != 0 ? 1u : 0u;
        local_total += input[idx + stride] != 0 ? 1u : 0u;
        local_total += input[idx + (stride * 2)] != 0 ? 1u : 0u;
        local_total += input[idx + (stride * 3)] != 0 ? 1u : 0u;
        local_total += input[idx + (stride * 4)] != 0 ? 1u : 0u;
        local_total += input[idx + (stride * 5)] != 0 ? 1u : 0u;
        local_total += input[idx + (stride * 6)] != 0 ? 1u : 0u;
        local_total += input[idx + (stride * 7)] != 0 ? 1u : 0u;
        local_total += input[idx + (stride * 8)] != 0 ? 1u : 0u;
        local_total += input[idx + (stride * 9)] != 0 ? 1u : 0u;
        local_total += input[idx + (stride * 10)] != 0 ? 1u : 0u;
        local_total += input[idx + (stride * 11)] != 0 ? 1u : 0u;
        local_total += input[idx + (stride * 12)] != 0 ? 1u : 0u;
        local_total += input[idx + (stride * 13)] != 0 ? 1u : 0u;
        local_total += input[idx + (stride * 14)] != 0 ? 1u : 0u;
        local_total += input[idx + (stride * 15)] != 0 ? 1u : 0u;
    }
    for (; idx < end; idx += lanes_per_group) {
        local_total += input[idx] != 0 ? 1u : 0u;
    }

    uint simd_total = simd_sum(local_total);

    if (simdgroups_per_group <= 1) {
        if (simd_is_first()) {
            output[segment_id] = simd_total;
        }
        return;
    }

    threadgroup uint partial[256];
    if (simd_is_first()) {
        partial[simdgroup_id] = simd_total;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (simdgroup_id == 0) {
        uint group_total = lane_id < simdgroups_per_group ? partial[lane_id] : 0u;
        group_total = simd_sum(group_total);
        if (simd_is_first()) {
            output[segment_id] = group_total;
        }
    }
}
