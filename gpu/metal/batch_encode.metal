#include <metal_stdlib>
using namespace metal;

constant uint TT_ENCODE_BYTES_PER_THREAD = 128;

kernel void tt_encode_u8_to_u32(
    device const uchar *input [[buffer(0)]],
    device uint *output [[buffer(1)]],
    constant uint &total_len [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    uint base = id * TT_ENCODE_BYTES_PER_THREAD;
    if (base >= total_len) {
        return;
    }
    uint end = min(base + TT_ENCODE_BYTES_PER_THREAD, total_len);
    for (uint idx = base; idx < end; idx += 1) {
        output[idx] = static_cast<uint>(input[idx]);
    }
}
