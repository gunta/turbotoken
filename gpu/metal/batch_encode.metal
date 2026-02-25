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
        const device uint4 *in128 = (const device uint4 *)(input + idx);
        device uint4 *out4 = (device uint4 *)(output + idx);

        const uint4 p0 = in128[0];
        const uint4 p1 = in128[1];
        const uint4 p2 = in128[2];
        const uint4 p3 = in128[3];

        out4[0] = uint4(p0[0] & 0xffu, (p0[0] >> 8) & 0xffu, (p0[0] >> 16) & 0xffu, (p0[0] >> 24) & 0xffu);
        out4[1] = uint4(p0[1] & 0xffu, (p0[1] >> 8) & 0xffu, (p0[1] >> 16) & 0xffu, (p0[1] >> 24) & 0xffu);
        out4[2] = uint4(p0[2] & 0xffu, (p0[2] >> 8) & 0xffu, (p0[2] >> 16) & 0xffu, (p0[2] >> 24) & 0xffu);
        out4[3] = uint4(p0[3] & 0xffu, (p0[3] >> 8) & 0xffu, (p0[3] >> 16) & 0xffu, (p0[3] >> 24) & 0xffu);
        out4[4] = uint4(p1[0] & 0xffu, (p1[0] >> 8) & 0xffu, (p1[0] >> 16) & 0xffu, (p1[0] >> 24) & 0xffu);
        out4[5] = uint4(p1[1] & 0xffu, (p1[1] >> 8) & 0xffu, (p1[1] >> 16) & 0xffu, (p1[1] >> 24) & 0xffu);
        out4[6] = uint4(p1[2] & 0xffu, (p1[2] >> 8) & 0xffu, (p1[2] >> 16) & 0xffu, (p1[2] >> 24) & 0xffu);
        out4[7] = uint4(p1[3] & 0xffu, (p1[3] >> 8) & 0xffu, (p1[3] >> 16) & 0xffu, (p1[3] >> 24) & 0xffu);
        out4[8] = uint4(p2[0] & 0xffu, (p2[0] >> 8) & 0xffu, (p2[0] >> 16) & 0xffu, (p2[0] >> 24) & 0xffu);
        out4[9] = uint4(p2[1] & 0xffu, (p2[1] >> 8) & 0xffu, (p2[1] >> 16) & 0xffu, (p2[1] >> 24) & 0xffu);
        out4[10] = uint4(p2[2] & 0xffu, (p2[2] >> 8) & 0xffu, (p2[2] >> 16) & 0xffu, (p2[2] >> 24) & 0xffu);
        out4[11] = uint4(p2[3] & 0xffu, (p2[3] >> 8) & 0xffu, (p2[3] >> 16) & 0xffu, (p2[3] >> 24) & 0xffu);
        out4[12] = uint4(p3[0] & 0xffu, (p3[0] >> 8) & 0xffu, (p3[0] >> 16) & 0xffu, (p3[0] >> 24) & 0xffu);
        out4[13] = uint4(p3[1] & 0xffu, (p3[1] >> 8) & 0xffu, (p3[1] >> 16) & 0xffu, (p3[1] >> 24) & 0xffu);
        out4[14] = uint4(p3[2] & 0xffu, (p3[2] >> 8) & 0xffu, (p3[2] >> 16) & 0xffu, (p3[2] >> 24) & 0xffu);
        out4[15] = uint4(p3[3] & 0xffu, (p3[3] >> 8) & 0xffu, (p3[3] >> 16) & 0xffu, (p3[3] >> 24) & 0xffu);
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
