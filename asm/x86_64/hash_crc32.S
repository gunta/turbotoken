#ifdef __APPLE__
#define TT_SYM(name) _##name
#else
#define TT_SYM(name) name
#endif

// uint64_t turbotoken_x86_hash_crc32_u64(uint64_t key)
// rdi = key
// returns zero-extended 32-bit CRC hash in rax.
.text
.globl TT_SYM(turbotoken_x86_hash_crc32_u64)
.p2align 4, 0x90
TT_SYM(turbotoken_x86_hash_crc32_u64):
    xorl %eax, %eax
    crc32q %rdi, %rax
    ret
