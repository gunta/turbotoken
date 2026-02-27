const BYTES_PER_U32 = 4;

interface TurbotokenWasmExports {
  memory: WebAssembly.Memory;
  turbotoken_wasm_alloc(size: number): number;
  turbotoken_wasm_free(ptr: number, size: number): void;
  turbotoken_encode_utf8_bytes(
    textPtr: number,
    textLen: number,
    outTokensPtr: number,
    outCap: number,
  ): number;
  turbotoken_decode_utf8_bytes(
    tokensPtr: number,
    tokenLen: number,
    outBytesPtr: number,
    outCap: number,
  ): number;
  turbotoken_count_bpe_from_ranks(rankPtr: number, rankLen: number, textPtr: number, textLen: number): number;
  turbotoken_encode_bpe_from_ranks(
    rankPtr: number,
    rankLen: number,
    textPtr: number,
    textLen: number,
    outTokensPtr: number,
    outCap: number,
  ): number;
  turbotoken_decode_bpe_from_ranks(
    rankPtr: number,
    rankLen: number,
    tokensPtr: number,
    tokenLen: number,
    outBytesPtr: number,
    outCap: number,
  ): number;
  turbotoken_train_bpe_from_chunk_counts(
    chunksPtr: number,
    chunksLen: number,
    offsetsPtr: number,
    offsetsLen: number,
    countsPtr: number,
    countsLen: number,
    vocabSize: number,
    minFrequency: number,
    outMergesPtr: number,
    outCap: number,
  ): number;
}

export interface WasmLoadOptions {
  wasmPath?: string;
  wasmUrl?: string;
  wasmBytes?: ArrayBuffer | Uint8Array;
  imports?: WebAssembly.Imports;
  forceReload?: boolean;
}

export interface BpeMerge {
  left: number;
  right: number;
  newId: number;
}

let wasmBridgePromise: Promise<WasmBridge> | null = null;

function defaultWasmPath(): string {
  if (typeof process !== "undefined" && typeof process.cwd === "function") {
    return `${process.cwd()}/zig-out/bin/turbotoken.wasm`;
  }
  throw new Error("No default WASM path in this runtime; provide wasmPath, wasmUrl, or wasmBytes.");
}

async function readLocalFile(path: string): Promise<Uint8Array> {
  if (typeof Bun !== "undefined") {
    return new Uint8Array(await Bun.file(path).arrayBuffer());
  }
  const fs = await import("node:fs/promises");
  return new Uint8Array(await fs.readFile(path));
}

async function loadWasmBytes(options: WasmLoadOptions): Promise<Uint8Array> {
  if (options.wasmBytes !== undefined) {
    return options.wasmBytes instanceof Uint8Array ? options.wasmBytes : new Uint8Array(options.wasmBytes);
  }
  if (options.wasmUrl !== undefined) {
    const response = await fetch(options.wasmUrl);
    if (!response.ok) {
      throw new Error(`Failed to fetch WASM from ${options.wasmUrl}: HTTP ${response.status}`);
    }
    return new Uint8Array(await response.arrayBuffer());
  }
  const path = options.wasmPath ?? defaultWasmPath();
  return readLocalFile(path);
}

async function instantiateBridge(options: WasmLoadOptions): Promise<WasmBridge> {
  const bytes = await loadWasmBytes(options);
  const imports = options.imports ?? {};
  const instantiated = await WebAssembly.instantiate(bytes, imports);
  const instance = instantiated.instance as WebAssembly.Instance;
  const rawExports = instance.exports as unknown as TurbotokenWasmExports;

  if (typeof rawExports.turbotoken_wasm_alloc !== "function") {
    throw new Error("WASM module is missing turbotoken_wasm_alloc export");
  }
  if (typeof rawExports.turbotoken_wasm_free !== "function") {
    throw new Error("WASM module is missing turbotoken_wasm_free export");
  }
  if (rawExports.memory === undefined) {
    throw new Error("WASM module is missing exported memory");
  }
  return new WasmBridge(rawExports);
}

export async function loadWasm(options: WasmLoadOptions = {}): Promise<WasmBridge> {
  if (options.forceReload) {
    wasmBridgePromise = instantiateBridge(options);
    return wasmBridgePromise;
  }
  if (wasmBridgePromise === null) {
    wasmBridgePromise = instantiateBridge(options);
  }
  return wasmBridgePromise;
}

export function clearWasmCache(): void {
  wasmBridgePromise = null;
}

export class WasmBridge {
  private readonly encoder = new TextEncoder();

  constructor(private readonly exports: TurbotokenWasmExports) {}

  private heapU8(): Uint8Array {
    return new Uint8Array(this.exports.memory.buffer);
  }

  private alloc(size: number): number {
    if (size <= 0) {
      return 0;
    }
    const ptr = this.exports.turbotoken_wasm_alloc(size);
    if (ptr === 0) {
      throw new Error(`WASM allocation failed for ${size} bytes`);
    }
    return ptr;
  }

  private free(ptr: number, size: number): void {
    if (ptr === 0 || size <= 0) {
      return;
    }
    this.exports.turbotoken_wasm_free(ptr, size);
  }

  private withBytes<T>(input: Uint8Array, fn: (ptr: number, len: number) => T): T {
    if (input.byteLength === 0) {
      return fn(0, 0);
    }
    const ptr = this.alloc(input.byteLength);
    try {
      this.heapU8().set(input, ptr);
      return fn(ptr, input.byteLength);
    } finally {
      this.free(ptr, input.byteLength);
    }
  }

  private readBytes(ptr: number, len: number): Uint8Array {
    if (len <= 0) {
      return new Uint8Array(0);
    }
    return this.heapU8().slice(ptr, ptr + len);
  }

  private readU32List(ptr: number, len: number): number[] {
    if (len <= 0) {
      return [];
    }
    const out = new Array<number>(len);
    const view = new DataView(this.exports.memory.buffer);
    for (let i = 0; i < len; i += 1) {
      out[i] = view.getUint32(ptr + (i * BYTES_PER_U32), true);
    }
    return out;
  }

  private writeU32List(ptr: number, values: readonly number[]): void {
    if (values.length === 0) {
      return;
    }
    const view = new DataView(this.exports.memory.buffer);
    for (let i = 0; i < values.length; i += 1) {
      view.setUint32(ptr + (i * BYTES_PER_U32), values[i] >>> 0, true);
    }
  }

  private toBytes(input: string | Uint8Array): Uint8Array {
    return typeof input === "string" ? this.encoder.encode(input) : input;
  }

  encodeUtf8Bytes(input: string | Uint8Array): number[] {
    const bytes = this.toBytes(input);
    return this.withBytes(bytes, (textPtr, textLen) => {
      const needed = this.exports.turbotoken_encode_utf8_bytes(textPtr, textLen, 0, 0);
      if (needed < 0) {
        throw new Error("WASM turbotoken_encode_utf8_bytes failed");
      }
      if (needed === 0) {
        return [];
      }
      const outBytes = needed * BYTES_PER_U32;
      const outPtr = this.alloc(outBytes);
      try {
        const written = this.exports.turbotoken_encode_utf8_bytes(textPtr, textLen, outPtr, needed);
        if (written < 0) {
          throw new Error("WASM turbotoken_encode_utf8_bytes write pass failed");
        }
        return this.readU32List(outPtr, written);
      } finally {
        this.free(outPtr, outBytes);
      }
    });
  }

  decodeUtf8Bytes(tokens: readonly number[]): Uint8Array {
    if (tokens.length === 0) {
      return new Uint8Array(0);
    }
    const tokenBytes = tokens.length * BYTES_PER_U32;
    const tokenPtr = this.alloc(tokenBytes);
    this.writeU32List(tokenPtr, tokens);
    try {
      const needed = this.exports.turbotoken_decode_utf8_bytes(tokenPtr, tokens.length, 0, 0);
      if (needed < 0) {
        throw new Error("WASM turbotoken_decode_utf8_bytes failed");
      }
      if (needed === 0) {
        return new Uint8Array(0);
      }
      const outPtr = this.alloc(needed);
      try {
        const written = this.exports.turbotoken_decode_utf8_bytes(tokenPtr, tokens.length, outPtr, needed);
        if (written < 0) {
          throw new Error("WASM turbotoken_decode_utf8_bytes write pass failed");
        }
        return this.readBytes(outPtr, written);
      } finally {
        this.free(outPtr, needed);
      }
    } finally {
      this.free(tokenPtr, tokenBytes);
    }
  }

  countBpeFromRanks(rankPayload: Uint8Array, input: string | Uint8Array): number {
    const bytes = this.toBytes(input);
    return this.withBytes(rankPayload, (rankPtr, rankLen) =>
      this.withBytes(bytes, (textPtr, textLen) => {
        const count = this.exports.turbotoken_count_bpe_from_ranks(rankPtr, rankLen, textPtr, textLen);
        if (count < 0) {
          throw new Error("WASM turbotoken_count_bpe_from_ranks failed");
        }
        return count;
      }),
    );
  }

  encodeBpeFromRanks(rankPayload: Uint8Array, input: string | Uint8Array): number[] {
    const bytes = this.toBytes(input);
    return this.withBytes(rankPayload, (rankPtr, rankLen) =>
      this.withBytes(bytes, (textPtr, textLen) => {
        const needed = this.exports.turbotoken_encode_bpe_from_ranks(rankPtr, rankLen, textPtr, textLen, 0, 0);
        if (needed < 0) {
          throw new Error("WASM turbotoken_encode_bpe_from_ranks failed");
        }
        if (needed === 0) {
          return [];
        }
        const outBytes = needed * BYTES_PER_U32;
        const outPtr = this.alloc(outBytes);
        try {
          const written = this.exports.turbotoken_encode_bpe_from_ranks(
            rankPtr,
            rankLen,
            textPtr,
            textLen,
            outPtr,
            needed,
          );
          if (written < 0) {
            throw new Error("WASM turbotoken_encode_bpe_from_ranks write pass failed");
          }
          return this.readU32List(outPtr, written);
        } finally {
          this.free(outPtr, outBytes);
        }
      }),
    );
  }

  decodeBpeFromRanks(rankPayload: Uint8Array, tokens: readonly number[]): Uint8Array {
    return this.withBytes(rankPayload, (rankPtr, rankLen) => {
      if (tokens.length === 0) {
        return new Uint8Array(0);
      }
      const tokenBytes = tokens.length * BYTES_PER_U32;
      const tokenPtr = this.alloc(tokenBytes);
      this.writeU32List(tokenPtr, tokens);
      try {
        const needed = this.exports.turbotoken_decode_bpe_from_ranks(rankPtr, rankLen, tokenPtr, tokens.length, 0, 0);
        if (needed < 0) {
          throw new Error("WASM turbotoken_decode_bpe_from_ranks failed");
        }
        if (needed === 0) {
          return new Uint8Array(0);
        }
        const outPtr = this.alloc(needed);
        try {
          const written = this.exports.turbotoken_decode_bpe_from_ranks(
            rankPtr,
            rankLen,
            tokenPtr,
            tokens.length,
            outPtr,
            needed,
          );
          if (written < 0) {
            throw new Error("WASM turbotoken_decode_bpe_from_ranks write pass failed");
          }
          return this.readBytes(outPtr, written);
        } finally {
          this.free(outPtr, needed);
        }
      } finally {
        this.free(tokenPtr, tokenBytes);
      }
    });
  }

  trainBpeFromChunkCounts(
    chunks: string | Uint8Array,
    offsets: readonly number[],
    counts: readonly number[],
    options: { vocabSize: number; minFrequency: number },
  ): BpeMerge[] {
    if (offsets.length === 0 || counts.length + 1 !== offsets.length) {
      throw new Error("offsets/counts shape mismatch");
    }
    const chunkBytes = this.toBytes(chunks);
    const offsetsBytes = offsets.length * BYTES_PER_U32;
    const countsBytes = counts.length * BYTES_PER_U32;

    return this.withBytes(chunkBytes, (chunksPtr, chunksLen) => {
      const offsetsPtr = this.alloc(offsetsBytes);
      const countsPtr = this.alloc(countsBytes);
      this.writeU32List(offsetsPtr, offsets);
      this.writeU32List(countsPtr, counts);
      try {
        const needed = this.exports.turbotoken_train_bpe_from_chunk_counts(
          chunksPtr,
          chunksLen,
          offsetsPtr,
          offsets.length,
          countsPtr,
          counts.length,
          options.vocabSize,
          options.minFrequency,
          0,
          0,
        );
        if (needed < 0) {
          throw new Error("WASM turbotoken_train_bpe_from_chunk_counts failed");
        }
        if (needed === 0) {
          return [];
        }
        const flatLen = needed * 3;
        const outBytes = flatLen * BYTES_PER_U32;
        const outPtr = this.alloc(outBytes);
        try {
          const written = this.exports.turbotoken_train_bpe_from_chunk_counts(
            chunksPtr,
            chunksLen,
            offsetsPtr,
            offsets.length,
            countsPtr,
            counts.length,
            options.vocabSize,
            options.minFrequency,
            outPtr,
            flatLen,
          );
          if (written < 0) {
            throw new Error("WASM turbotoken_train_bpe_from_chunk_counts write pass failed");
          }
          const flat = this.readU32List(outPtr, written * 3);
          const merges: BpeMerge[] = [];
          for (let i = 0; i < written; i += 1) {
            const base = i * 3;
            merges.push({
              left: flat[base],
              right: flat[base + 1],
              newId: flat[base + 2],
            });
          }
          return merges;
        } finally {
          this.free(outPtr, outBytes);
        }
      } finally {
        this.free(offsetsPtr, offsetsBytes);
        this.free(countsPtr, countsBytes);
      }
    });
  }
}
