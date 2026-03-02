const libSuffix = Deno.build.os === "windows"
  ? "turbotoken.dll"
  : Deno.build.os === "darwin"
  ? "libturbotoken.dylib"
  : "libturbotoken.so";

function findLibrary(): string {
  const envPath = Deno.env.get("TURBOTOKEN_NATIVE_LIB");
  if (envPath) return envPath;

  const searchPaths = [
    `./${libSuffix}`,
    `./zig-out/lib/${libSuffix}`,
    `../../zig-out/lib/${libSuffix}`,
    `../zig-out/lib/${libSuffix}`,
    `/usr/local/lib/${libSuffix}`,
    `/usr/lib/${libSuffix}`,
  ];

  for (const p of searchPaths) {
    try {
      Deno.statSync(p);
      return p;
    } catch {
      // continue
    }
  }

  return libSuffix;
}

const libPath = findLibrary();

export const lib = Deno.dlopen(libPath, {
  turbotoken_version: {
    parameters: [],
    result: "pointer",
  },
  turbotoken_clear_rank_table_cache: {
    parameters: [],
    result: "void",
  },
  turbotoken_encode_bpe_from_ranks: {
    parameters: ["pointer", "usize", "pointer", "usize", "pointer", "usize"],
    result: "isize",
  },
  turbotoken_decode_bpe_from_ranks: {
    parameters: ["pointer", "usize", "pointer", "usize", "pointer", "usize"],
    result: "isize",
  },
  turbotoken_count_bpe_from_ranks: {
    parameters: ["pointer", "usize", "pointer", "usize"],
    result: "isize",
  },
  turbotoken_is_within_token_limit_bpe_from_ranks: {
    parameters: ["pointer", "usize", "pointer", "usize", "usize"],
    result: "isize",
  },
  turbotoken_encode_bpe_file_from_ranks: {
    parameters: ["pointer", "usize", "pointer", "usize", "pointer", "usize"],
    result: "isize",
  },
  turbotoken_count_bpe_file_from_ranks: {
    parameters: ["pointer", "usize", "pointer", "usize"],
    result: "isize",
  },
  turbotoken_is_within_token_limit_bpe_file_from_ranks: {
    parameters: ["pointer", "usize", "pointer", "usize", "usize"],
    result: "isize",
  },
});

export function readCString(ptr: Deno.PointerObject): string {
  const view = new Deno.UnsafePointerView(ptr);
  return view.getCString();
}

export function twoPassEncode(
  rankBuf: Uint8Array,
  inputBuf: Uint8Array,
  ffiCall: (
    rankPtr: Deno.PointerObject,
    rankLen: number,
    inputPtr: Deno.PointerObject,
    inputLen: number,
    outPtr: Deno.PointerObject | null,
    outCap: number,
  ) => number | bigint,
): Uint32Array {
  const rankPtr = Deno.UnsafePointer.of(rankBuf)!;
  const inputPtr = Deno.UnsafePointer.of(inputBuf)!;

  const sizeResult = Number(
    ffiCall(rankPtr, rankBuf.length, inputPtr, inputBuf.length, null!, 0),
  );
  if (sizeResult < 0) {
    throw new Error(`FFI size query returned error code ${sizeResult}`);
  }
  if (sizeResult === 0) return new Uint32Array(0);

  const outBuf = new Uint32Array(sizeResult);
  const outPtr = Deno.UnsafePointer.of(new Uint8Array(outBuf.buffer))!;
  const written = Number(
    ffiCall(
      rankPtr,
      rankBuf.length,
      inputPtr,
      inputBuf.length,
      outPtr,
      sizeResult,
    ),
  );
  if (written < 0) {
    throw new Error(`FFI fill returned error code ${written}`);
  }
  return written < sizeResult ? outBuf.slice(0, written) : outBuf;
}

export function twoPassDecode(
  rankBuf: Uint8Array,
  tokenBuf: Uint32Array,
  ffiCall: (
    rankPtr: Deno.PointerObject,
    rankLen: number,
    inputPtr: Deno.PointerObject,
    inputLen: number,
    outPtr: Deno.PointerObject | null,
    outCap: number,
  ) => number | bigint,
): Uint8Array {
  const rankPtr = Deno.UnsafePointer.of(rankBuf)!;
  const inputPtr = Deno.UnsafePointer.of(new Uint8Array(tokenBuf.buffer))!;

  const sizeResult = Number(
    ffiCall(rankPtr, rankBuf.length, inputPtr, tokenBuf.length, null!, 0),
  );
  if (sizeResult < 0) {
    throw new Error(`FFI size query returned error code ${sizeResult}`);
  }
  if (sizeResult === 0) return new Uint8Array(0);

  const outBuf = new Uint8Array(sizeResult);
  const outPtr = Deno.UnsafePointer.of(outBuf)!;
  const written = Number(
    ffiCall(
      rankPtr,
      rankBuf.length,
      inputPtr,
      tokenBuf.length,
      outPtr,
      sizeResult,
    ),
  );
  if (written < 0) {
    throw new Error(`FFI fill returned error code ${written}`);
  }
  return written < sizeResult ? outBuf.slice(0, written) : outBuf;
}
