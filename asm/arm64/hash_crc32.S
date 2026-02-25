#ifdef __APPLE__
#define TT_SYM(name) _##name
#else
#define TT_SYM(name) name
#endif

// uint64_t turbotoken_arm64_hash_crc32_u64(uint64_t key)
// x0 = key
// returns zero-extended 32-bit CRC hash in x0.
.text
.arch armv8-a+crc
.globl TT_SYM(turbotoken_arm64_hash_crc32_u64)
.p2align 2
TT_SYM(turbotoken_arm64_hash_crc32_u64):
    mov w8, #0
    crc32x w8, w8, x0
    uxtw x0, w8
    ret
