#ifdef __APPLE__
#define TT_SYM(name) _##name
#else
#define TT_SYM(name) name
#endif

// size_t turbotoken_arm64_count_non_ascii_sme(const uint8_t *bytes, size_t len)
// x0 = bytes, x1 = len
// returns count of bytes with high bit set.
//
// Prototype kernel:
// - enters SME streaming mode
// - processes full streaming-vector chunks with SVE predicates
// - falls back to predicated tail for remaining bytes
.text
.arch armv9.2-a+sme
.globl TT_SYM(turbotoken_arm64_count_non_ascii_sme)
.p2align 2
TT_SYM(turbotoken_arm64_count_non_ascii_sme):
    mov x2, #0
    cbz x1, .Ldone

    smstart sm
    cntb x4
    lsl x6, x4, #2
    ptrue p0.b

.Lloop4:
    cmp x1, x6
    b.lo .Lloop1
    prfm pldl1keep, [x0, #256]

    ld1b { z0.b }, p0/z, [x0]
    cmplt p1.b, p0/z, z0.b, #0
    cntp x3, p0, p1.b
    add x2, x2, x3

    add x0, x0, x4
    ld1b { z1.b }, p0/z, [x0]
    cmplt p1.b, p0/z, z1.b, #0
    cntp x3, p0, p1.b
    add x2, x2, x3

    add x0, x0, x4
    ld1b { z2.b }, p0/z, [x0]
    cmplt p1.b, p0/z, z2.b, #0
    cntp x3, p0, p1.b
    add x2, x2, x3

    add x0, x0, x4
    ld1b { z3.b }, p0/z, [x0]
    cmplt p1.b, p0/z, z3.b, #0
    cntp x3, p0, p1.b
    add x2, x2, x3

    add x0, x0, x4
    sub x1, x1, x6
    b .Lloop4

.Lloop1:
    cmp x1, x4
    b.lo .Ltail

    ld1b { z0.b }, p0/z, [x0]
    cmplt p1.b, p0/z, z0.b, #0
    cntp x3, p0, p1.b
    add x2, x2, x3

    add x0, x0, x4
    sub x1, x1, x4
    b .Lloop1

.Ltail:
    cbz x1, .Lstream_done
    mov x5, #0
    whilelt p0.b, x5, x1
    ld1b { z0.b }, p0/z, [x0]
    cmplt p1.b, p0/z, z0.b, #0
    cntp x3, p0, p1.b
    add x2, x2, x3

.Lstream_done:
    smstop sm

.Ldone:
    mov x0, x2
    ret
