#include <metal_stdlib>
using namespace metal;

constant uint TT_ENCODE_BYTES_PER_THREAD = 512;

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
    uint idx = base;
    for (; idx + 32 <= end; idx += 32) {
        const device uchar4 *in4 = (const device uchar4 *)(input + idx);
        device uint4 *out4 = (device uint4 *)(output + idx);
        out4[0] = uint4(in4[0]);
        out4[1] = uint4(in4[1]);
        out4[2] = uint4(in4[2]);
        out4[3] = uint4(in4[3]);
        out4[4] = uint4(in4[4]);
        out4[5] = uint4(in4[5]);
        out4[6] = uint4(in4[6]);
        out4[7] = uint4(in4[7]);
    }
    for (; idx + 4 <= end; idx += 4) {
        const device uchar4 *in4 = (const device uchar4 *)(input + idx);
        device uint4 *out4 = (device uint4 *)(output + idx);
        out4[0] = uint4(in4[0]);
    }
    for (; idx < end; idx += 1) {
        output[idx] = static_cast<uint>(input[idx]);
    }
}
