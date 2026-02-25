#ifdef __APPLE__
#define TT_SYM(name) _##name
#else
#define TT_SYM(name) name
#endif

// void turbotoken_arm64_decode_u32_to_u8(const uint32_t *tokens, size_t len, uint8_t *out)
// x0 = tokens, x1 = len, x2 = out
// Caller is responsible for ensuring all token values are <= 255.
.text
.globl TT_SYM(turbotoken_arm64_decode_u32_to_u8)
.p2align 2
TT_SYM(turbotoken_arm64_decode_u32_to_u8):
    cbz x1, .Ldone

.Lloop16:
    cmp x1, #16
    b.lo .Ltail

    prfm pldl1keep, [x0, #64]
    ld1 {v0.4s, v1.4s, v2.4s, v3.4s}, [x0], #64
    xtn v0.4h, v0.4s
    xtn2 v0.8h, v1.4s
    xtn v2.4h, v2.4s
    xtn2 v2.8h, v3.4s
    xtn v0.8b, v0.8h
    xtn2 v0.16b, v2.8h
    st1 {v0.16b}, [x2], #16

    sub x1, x1, #16
    b .Lloop16

.Ltail:
    cbz x1, .Ldone
.Ltail_loop:
    ldr w3, [x0], #4
    strb w3, [x2], #1
    subs x1, x1, #1
    b.ne .Ltail_loop

.Ldone:
    ret
