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

.Lloop64:
    cmp x1, #64
    b.lo .Lloop16

    prfm pldl1keep, [x0, #256]
    prfm pstl1keep, [x2, #64]

    // block 0
    ld1 {v0.4s, v1.4s, v2.4s, v3.4s}, [x0], #64
    xtn v0.4h, v0.4s
    xtn2 v0.8h, v1.4s
    xtn v2.4h, v2.4s
    xtn2 v2.8h, v3.4s
    xtn v0.8b, v0.8h
    xtn2 v0.16b, v2.8h
    st1 {v0.16b}, [x2], #16

    // block 1
    ld1 {v0.4s, v1.4s, v2.4s, v3.4s}, [x0], #64
    xtn v0.4h, v0.4s
    xtn2 v0.8h, v1.4s
    xtn v2.4h, v2.4s
    xtn2 v2.8h, v3.4s
    xtn v0.8b, v0.8h
    xtn2 v0.16b, v2.8h
    st1 {v0.16b}, [x2], #16

    // block 2
    ld1 {v0.4s, v1.4s, v2.4s, v3.4s}, [x0], #64
    xtn v0.4h, v0.4s
    xtn2 v0.8h, v1.4s
    xtn v2.4h, v2.4s
    xtn2 v2.8h, v3.4s
    xtn v0.8b, v0.8h
    xtn2 v0.16b, v2.8h
    st1 {v0.16b}, [x2], #16

    // block 3
    ld1 {v0.4s, v1.4s, v2.4s, v3.4s}, [x0], #64
    xtn v0.4h, v0.4s
    xtn2 v0.8h, v1.4s
    xtn v2.4h, v2.4s
    xtn2 v2.8h, v3.4s
    xtn v0.8b, v0.8h
    xtn2 v0.16b, v2.8h
    st1 {v0.16b}, [x2], #16

    sub x1, x1, #64
    b .Lloop64

.Lloop16:
    cmp x1, #16
    b.lo .Ltail

    prfm pldl1keep, [x0, #64]
    prfm pstl1keep, [x2, #16]
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

// uint32_t turbotoken_arm64_validate_and_decode_u32_to_u8(const uint32_t *tokens, size_t len, uint8_t *out)
// x0 = tokens, x1 = len, x2 = out
// returns 1 if all token values <= 255, else 0.
.globl TT_SYM(turbotoken_arm64_validate_and_decode_u32_to_u8)
.p2align 2
TT_SYM(turbotoken_arm64_validate_and_decode_u32_to_u8):
    eor v24.16b, v24.16b, v24.16b
    eor v25.16b, v25.16b, v25.16b
    eor v26.16b, v26.16b, v26.16b
    eor v27.16b, v27.16b, v27.16b
    cbz x1, .Lvd_done_ok

.Lvd_loop64:
    cmp x1, #64
    b.lo .Lvd_loop16

    prfm pldl1keep, [x0, #256]
    prfm pstl1keep, [x2, #64]

    // block 0
    ld1 {v0.4s, v1.4s, v2.4s, v3.4s}, [x0], #64

    umax v24.4s, v24.4s, v0.4s
    umax v24.4s, v24.4s, v1.4s
    umax v24.4s, v24.4s, v2.4s
    umax v24.4s, v24.4s, v3.4s

    xtn v0.4h, v0.4s
    xtn2 v0.8h, v1.4s
    xtn v2.4h, v2.4s
    xtn2 v2.8h, v3.4s
    xtn v0.8b, v0.8h
    xtn2 v0.16b, v2.8h
    st1 {v0.16b}, [x2], #16

    // block 1
    ld1 {v0.4s, v1.4s, v2.4s, v3.4s}, [x0], #64

    umax v25.4s, v25.4s, v0.4s
    umax v25.4s, v25.4s, v1.4s
    umax v25.4s, v25.4s, v2.4s
    umax v25.4s, v25.4s, v3.4s

    xtn v0.4h, v0.4s
    xtn2 v0.8h, v1.4s
    xtn v2.4h, v2.4s
    xtn2 v2.8h, v3.4s
    xtn v0.8b, v0.8h
    xtn2 v0.16b, v2.8h
    st1 {v0.16b}, [x2], #16

    // block 2
    ld1 {v0.4s, v1.4s, v2.4s, v3.4s}, [x0], #64

    umax v26.4s, v26.4s, v0.4s
    umax v26.4s, v26.4s, v1.4s
    umax v26.4s, v26.4s, v2.4s
    umax v26.4s, v26.4s, v3.4s

    xtn v0.4h, v0.4s
    xtn2 v0.8h, v1.4s
    xtn v2.4h, v2.4s
    xtn2 v2.8h, v3.4s
    xtn v0.8b, v0.8h
    xtn2 v0.16b, v2.8h
    st1 {v0.16b}, [x2], #16

    // block 3
    ld1 {v0.4s, v1.4s, v2.4s, v3.4s}, [x0], #64

    umax v27.4s, v27.4s, v0.4s
    umax v27.4s, v27.4s, v1.4s
    umax v27.4s, v27.4s, v2.4s
    umax v27.4s, v27.4s, v3.4s

    xtn v0.4h, v0.4s
    xtn2 v0.8h, v1.4s
    xtn v2.4h, v2.4s
    xtn2 v2.8h, v3.4s
    xtn v0.8b, v0.8h
    xtn2 v0.16b, v2.8h
    st1 {v0.16b}, [x2], #16

    sub x1, x1, #64
    b .Lvd_loop64

.Lvd_loop16:
    cmp x1, #16
    b.lo .Lvd_tail

    prfm pldl1keep, [x0, #64]
    prfm pstl1keep, [x2, #16]
    ld1 {v0.4s, v1.4s, v2.4s, v3.4s}, [x0], #64

    umax v24.4s, v24.4s, v0.4s
    umax v24.4s, v24.4s, v1.4s
    umax v24.4s, v24.4s, v2.4s
    umax v24.4s, v24.4s, v3.4s

    xtn v0.4h, v0.4s
    xtn2 v0.8h, v1.4s
    xtn v2.4h, v2.4s
    xtn2 v2.8h, v3.4s
    xtn v0.8b, v0.8h
    xtn2 v0.16b, v2.8h
    st1 {v0.16b}, [x2], #16

    sub x1, x1, #16
    b .Lvd_loop16

.Lvd_tail:
    cbz x1, .Lvd_finish
.Lvd_tail_loop:
    ldr w3, [x0], #4
    cmp w3, #255
    b.hi .Lvd_invalid
    strb w3, [x2], #1
    subs x1, x1, #1
    b.ne .Lvd_tail_loop

.Lvd_finish:
    umax v24.4s, v24.4s, v25.4s
    umax v26.4s, v26.4s, v27.4s
    umax v24.4s, v24.4s, v26.4s
    umaxv s9, v24.4s
    umov w9, v9.s[0]
    cmp w9, #255
    b.hi .Lvd_invalid

.Lvd_done_ok:
    mov w0, #1
    ret

.Lvd_invalid:
    mov w0, #0
    ret

// void turbotoken_arm64_encode_u8_to_u32(const uint8_t *bytes, size_t len, uint32_t *out)
// x0 = bytes, x1 = len, x2 = out
.globl TT_SYM(turbotoken_arm64_encode_u8_to_u32)
.p2align 2
TT_SYM(turbotoken_arm64_encode_u8_to_u32):
    cbz x1, .Lenc_done

.Lenc_loop64:
    cmp x1, #64
    b.lo .Lenc_loop16

    prfm pldl1keep, [x0, #128]
    prfm pstl1keep, [x2, #256]

    ld1 {v16.16b, v17.16b, v18.16b, v19.16b}, [x0], #64

    // block 0
    uxtl v1.8h, v16.8b
    uxtl2 v2.8h, v16.16b
    uxtl v3.4s, v1.4h
    uxtl2 v4.4s, v1.8h
    uxtl v5.4s, v2.4h
    uxtl2 v6.4s, v2.8h
    st1 {v3.4s, v4.4s, v5.4s, v6.4s}, [x2], #64

    // block 1
    uxtl v1.8h, v17.8b
    uxtl2 v2.8h, v17.16b
    uxtl v3.4s, v1.4h
    uxtl2 v4.4s, v1.8h
    uxtl v5.4s, v2.4h
    uxtl2 v6.4s, v2.8h
    st1 {v3.4s, v4.4s, v5.4s, v6.4s}, [x2], #64

    // block 2
    uxtl v1.8h, v18.8b
    uxtl2 v2.8h, v18.16b
    uxtl v3.4s, v1.4h
    uxtl2 v4.4s, v1.8h
    uxtl v5.4s, v2.4h
    uxtl2 v6.4s, v2.8h
    st1 {v3.4s, v4.4s, v5.4s, v6.4s}, [x2], #64

    // block 3
    uxtl v1.8h, v19.8b
    uxtl2 v2.8h, v19.16b
    uxtl v3.4s, v1.4h
    uxtl2 v4.4s, v1.8h
    uxtl v5.4s, v2.4h
    uxtl2 v6.4s, v2.8h
    st1 {v3.4s, v4.4s, v5.4s, v6.4s}, [x2], #64

    sub x1, x1, #64
    b .Lenc_loop64

.Lenc_loop16:
    cmp x1, #16
    b.lo .Lenc_tail

    prfm pldl1keep, [x0, #64]
    prfm pstl1keep, [x2, #64]
    ld1 {v0.16b}, [x0], #16
    uxtl v1.8h, v0.8b
    uxtl2 v2.8h, v0.16b
    uxtl v3.4s, v1.4h
    uxtl2 v4.4s, v1.8h
    uxtl v5.4s, v2.4h
    uxtl2 v6.4s, v2.8h
    st1 {v3.4s, v4.4s, v5.4s, v6.4s}, [x2], #64

    sub x1, x1, #16
    b .Lenc_loop16

.Lenc_tail:
    cbz x1, .Lenc_done
.Lenc_tail_loop:
    ldrb w3, [x0], #1
    str w3, [x2], #4
    subs x1, x1, #1
    b.ne .Lenc_tail_loop

.Lenc_done:
    ret
