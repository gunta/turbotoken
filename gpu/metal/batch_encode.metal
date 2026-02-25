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
    for (; idx + 64 <= end; idx += 64) {
        const device uchar16 *in16 = (const device uchar16 *)(input + idx);
        device uint4 *out4 = (device uint4 *)(output + idx);

        const uchar16 v0 = in16[0];
        const uchar16 v1 = in16[1];
        const uchar16 v2 = in16[2];
        const uchar16 v3 = in16[3];

        out4[0] = uint4(v0[0], v0[1], v0[2], v0[3]);
        out4[1] = uint4(v0[4], v0[5], v0[6], v0[7]);
        out4[2] = uint4(v0[8], v0[9], v0[10], v0[11]);
        out4[3] = uint4(v0[12], v0[13], v0[14], v0[15]);
        out4[4] = uint4(v1[0], v1[1], v1[2], v1[3]);
        out4[5] = uint4(v1[4], v1[5], v1[6], v1[7]);
        out4[6] = uint4(v1[8], v1[9], v1[10], v1[11]);
        out4[7] = uint4(v1[12], v1[13], v1[14], v1[15]);
        out4[8] = uint4(v2[0], v2[1], v2[2], v2[3]);
        out4[9] = uint4(v2[4], v2[5], v2[6], v2[7]);
        out4[10] = uint4(v2[8], v2[9], v2[10], v2[11]);
        out4[11] = uint4(v2[12], v2[13], v2[14], v2[15]);
        out4[12] = uint4(v3[0], v3[1], v3[2], v3[3]);
        out4[13] = uint4(v3[4], v3[5], v3[6], v3[7]);
        out4[14] = uint4(v3[8], v3[9], v3[10], v3[11]);
        out4[15] = uint4(v3[12], v3[13], v3[14], v3[15]);
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
