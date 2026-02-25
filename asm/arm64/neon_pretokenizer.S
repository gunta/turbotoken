#ifdef __APPLE__
#define TT_SYM(name) _##name
#else
#define TT_SYM(name) name
#endif

// size_t turbotoken_arm64_count_non_ascii(const uint8_t *bytes, size_t len)
// x0 = bytes, x1 = len
// returns count of bytes with high bit set.
.text
.globl TT_SYM(turbotoken_arm64_count_non_ascii)
.p2align 2
TT_SYM(turbotoken_arm64_count_non_ascii):
    mov x2, #0
    mov x4, #0
    eor v31.16b, v31.16b, v31.16b
    cbz x1, .Ldone

.Lloop64:
    cmp x1, #64
    b.lo .Lflush64
    prfm pldl1keep, [x0, #128]
    ld1 {v0.16b, v1.16b, v2.16b, v3.16b}, [x0], #64

    ushr v4.16b, v0.16b, #7
    ushr v5.16b, v1.16b, #7
    ushr v6.16b, v2.16b, #7
    ushr v7.16b, v3.16b, #7
    uaddlp v4.8h, v4.16b
    uaddlp v5.8h, v5.16b
    uaddlp v6.8h, v6.16b
    uaddlp v7.8h, v7.16b
    add v4.8h, v4.8h, v5.8h
    add v6.8h, v6.8h, v7.8h
    add v4.8h, v4.8h, v6.8h
    add v31.8h, v31.8h, v4.8h
    add x4, x4, #1
    and x5, x4, #3
    cbnz x5, .Lloop64_skip_flush
    uaddlv s8, v31.8h
    umov w3, v8.s[0]
    add x2, x2, x3
    eor v31.16b, v31.16b, v31.16b

.Lloop64_skip_flush:

    sub x1, x1, #64
    b .Lloop64

.Lflush64:
    and x5, x4, #3
    cbz x5, .Lloop16
    uaddlv s8, v31.8h
    umov w3, v8.s[0]
    add x2, x2, x3
    eor v31.16b, v31.16b, v31.16b

.Lloop16:
    cmp x1, #16
    b.lo .Ltail
    prfm pldl1keep, [x0, #64]
    ld1 {v0.16b}, [x0], #16
    ushr v1.16b, v0.16b, #7
    uaddlp v1.8h, v1.16b
    uaddlv s2, v1.8h
    umov w3, v2.s[0]
    add x2, x2, x3
    sub x1, x1, #16
    b .Lloop16

.Ltail:
    cbz x1, .Ldone
.Ltail_loop:
    ldrb w3, [x0], #1
    lsr w3, w3, #7
    add x2, x2, x3
    subs x1, x1, #1
    b.ne .Ltail_loop

.Ldone:
    mov x0, x2
    ret

// size_t turbotoken_arm64_count_non_ascii_dotprod(const uint8_t *bytes, size_t len)
// x0 = bytes, x1 = len
// returns count of bytes with high bit set.
.arch armv8-a+dotprod
.globl TT_SYM(turbotoken_arm64_count_non_ascii_dotprod)
.p2align 2
TT_SYM(turbotoken_arm64_count_non_ascii_dotprod):
    mov x2, #0
    cbz x1, .Ldot_done

    movi v30.16b, #1

.Ldot_loop64:
    cmp x1, #64
    b.lo .Ldot_loop16
    prfm pldl1keep, [x0, #128]
    ld1 {v0.16b, v1.16b, v2.16b, v3.16b}, [x0], #64

    ushr v0.16b, v0.16b, #7
    ushr v1.16b, v1.16b, #7
    ushr v2.16b, v2.16b, #7
    ushr v3.16b, v3.16b, #7

    eor v20.16b, v20.16b, v20.16b
    udot v20.4s, v0.16b, v30.16b
    udot v20.4s, v1.16b, v30.16b
    udot v20.4s, v2.16b, v30.16b
    udot v20.4s, v3.16b, v30.16b
    addv s21, v20.4s
    umov w3, v21.s[0]
    add x2, x2, x3

    sub x1, x1, #64
    b .Ldot_loop64

.Ldot_loop16:
    cmp x1, #16
    b.lo .Ldot_tail
    prfm pldl1keep, [x0, #64]
    ld1 {v0.16b}, [x0], #16

    ushr v0.16b, v0.16b, #7
    eor v20.16b, v20.16b, v20.16b
    udot v20.4s, v0.16b, v30.16b
    addv s21, v20.4s
    umov w3, v21.s[0]
    add x2, x2, x3

    sub x1, x1, #16
    b .Ldot_loop16

.Ldot_tail:
    cbz x1, .Ldot_done
.Ldot_tail_loop:
    ldrb w3, [x0], #1
    lsr w3, w3, #7
    add x2, x2, x3
    subs x1, x1, #1
    b.ne .Ldot_tail_loop

.Ldot_done:
    mov x0, x2
    ret
