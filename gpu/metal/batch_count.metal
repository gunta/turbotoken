#include <metal_stdlib>
using namespace metal;

kernel void batch_count(device const uchar *input [[buffer(0)]],
                        device uint *output [[buffer(1)]],
                        uint id [[thread_position_in_grid]]) {
    // Placeholder shader.
    output[id] = input[id] > 0 ? 1 : 0;
}
