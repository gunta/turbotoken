#include <metal_stdlib>
using namespace metal;

kernel void tt_count_nonzero_segments(
    device const uchar *input [[buffer(0)]],
    device const uint *offsets [[buffer(1)]],
    device uint *output [[buffer(2)]],
    constant uint &segment_count [[buffer(3)]],
    uint segment_id [[threadgroup_position_in_grid]],
    uint lane_id [[thread_index_in_threadgroup]],
    uint lanes_per_group [[threads_per_threadgroup]]
) {
    if (segment_id >= segment_count) {
        return;
    }

    uint start = offsets[segment_id];
    uint end = offsets[segment_id + 1];
    uint local_total = 0;
    for (uint idx = start + lane_id; idx < end; idx += lanes_per_group) {
        local_total += input[idx] != 0 ? 1u : 0u;
    }

    threadgroup uint partial[256];
    partial[lane_id] = local_total;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint stride = lanes_per_group >> 1; stride > 0; stride >>= 1) {
        if (lane_id < stride) {
            partial[lane_id] += partial[lane_id + stride];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    if (lane_id == 0) {
        output[segment_id] = partial[0];
    }
}
