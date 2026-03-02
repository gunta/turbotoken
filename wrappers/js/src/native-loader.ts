import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const BYTES_PER_U32 = 4;
const require = createRequire(import.meta.url);

type FfiArgType = "ptr" | "usize";
type FfiReturnType = "isize" | "ptr";

interface FfiFnDef {
  args: readonly FfiArgType[];
  returns: FfiReturnType;
}

interface NativeSymbols {
  turbotoken_encode_utf8_bytes(
    textPtr: Uint8Array | number,
    textLen: number,
    outTokensPtr: Uint32Array | number,
    outCap: number,
  ): number | bigint;
  turbotoken_decode_utf8_bytes(
    tokensPtr: Uint32Array | number,
    tokenLen: number,
    outBytesPtr: Uint8Array | number,
    outCap: number,
  ): number | bigint;
  turbotoken_count_bpe_from_ranks(
    rankPtr: Uint8Array,
    rankLen: number,
    textPtr: Uint8Array,
    textLen: number,
  ): number | bigint;
  turbotoken_is_within_token_limit_bpe_from_ranks(
    rankPtr: Uint8Array,
    rankLen: number,
    textPtr: Uint8Array,
    textLen: number,
    tokenLimit: number,
  ): number | bigint;
  turbotoken_encode_bpe_from_ranks(
    rankPtr: Uint8Array,
    rankLen: number,
    textPtr: Uint8Array,
    textLen: number,
    outTokensPtr: Uint32Array | number,
    outCap: number,
  ): number | bigint;
  turbotoken_decode_bpe_from_ranks(
    rankPtr: Uint8Array,
    rankLen: number,
    tokensPtr: Uint32Array,
    tokenLen: number,
    outBytesPtr: Uint8Array | number,
    outCap: number,
  ): number | bigint;
}

interface BunDynamicLibrary {
  symbols: NativeSymbols;
  close?: () => void;
}

interface BunFfiModule {
  dlopen(path: string, symbols: Record<string, FfiFnDef>): BunDynamicLibrary;
}

export interface NativeLoadOptions {
  nativeLibPath?: string;
  forceReload?: boolean;
}

let nativeBridgePromise: Promise<NativeBridge> | null = null;

function parseString(raw: string | undefined): string | null {
  if (!raw) {
    return null;
  }
  const value = raw.trim();
  if (value.length === 0) {
    return null;
  }
  return value;
}

function nativeLibExtension(): string | null {
  if (typeof process === "undefined") {
    return null;
  }
  switch (process.platform) {
    case "darwin":
      return "dylib";
    case "linux":
      return "so";
    case "win32":
      return "dll";
    default:
      return null;
  }
}

function optionalNativePackages(): string[] {
  if (typeof process === "undefined") {
    return [];
  }
  const key = `${process.platform}-${process.arch}`;
  switch (key) {
    case "darwin-arm64":
      return ["@turbotoken/native-darwin-arm64"];
    case "linux-x64":
      return ["@turbotoken/native-linux-x64-gnu", "@turbotoken/native-linux-x64-musl"];
    case "linux-arm64":
      return ["@turbotoken/native-linux-arm64-gnu", "@turbotoken/native-linux-arm64-musl"];
    case "win32-x64":
      return ["@turbotoken/native-win32-x64-msvc", "@turbotoken/native-win32-x64-gnu"];
    default:
      return [];
  }
}

function resolveOptionalPackageLibs(ext: string): string[] {
  const out: string[] = [];
  for (const pkg of optionalNativePackages()) {
    try {
      const pkgJsonPath = require.resolve(`${pkg}/package.json`);
      const pkgRoot = dirname(pkgJsonPath);
      const names = ext === "dll"
        ? ["turbotoken.dll", "libturbotoken.dll"]
        : [`libturbotoken.${ext}`];
      for (const name of names) {
        out.push(resolve(pkgRoot, name));
      }
    } catch {
      // optional package not installed
    }
  }
  return out;
}

function uniquePaths(paths: readonly string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const path of paths) {
    if (seen.has(path)) {
      continue;
    }
    seen.add(path);
    out.push(path);
  }
  return out;
}

function nativePathCandidates(options: NativeLoadOptions): string[] {
  const explicit = options.nativeLibPath?.trim();
  if (explicit && explicit.length > 0) {
    return [explicit];
  }
  const envPath = parseString(process.env.TURBOTOKEN_NATIVE_LIB_PATH);
  if (envPath) {
    return [envPath];
  }
  const ext = nativeLibExtension();
  if (!ext) {
    return [];
  }

  const names = ext === "dll"
    ? ["turbotoken.dll", "libturbotoken.dll"]
    : [`libturbotoken.${ext}`];
  const platformKey = typeof process === "undefined" ? "unknown" : `${process.platform}-${process.arch}`;
  const localHostCandidates = names.map((name) =>
    new URL(`../native/host/${platformKey}/${name}`, import.meta.url)
  );
  const zigOutCandidates = names.flatMap((name) => [
    new URL(`../../../zig-out/lib/${name}`, import.meta.url),
    new URL(`../../../zig-out/bin/${name}`, import.meta.url),
  ]);
  const cwdCandidates = names.flatMap((name) => {
    if (typeof process === "undefined" || typeof process.cwd !== "function") {
      return [];
    }
    const cwd = process.cwd();
    return [
      resolve(cwd, "zig-out", "lib", name),
      resolve(cwd, "zig-out", "bin", name),
    ];
  });

  const urlPaths = [...localHostCandidates, ...zigOutCandidates]
    .map((url) => (url.protocol === "file:" ? fileURLToPath(url) : null))
    .filter((path): path is string => path != null);

  return uniquePaths([
    ...resolveOptionalPackageLibs(ext),
    ...urlPaths,
    ...cwdCandidates,
  ]);
}

function asNumber(value: number | bigint): number {
  if (typeof value === "number") {
    return value;
  }
  const converted = Number(value);
  if (!Number.isFinite(converted)) {
    throw new Error(`native bridge returned non-finite value: ${String(value)}`);
  }
  return converted;
}

function checkCallResult(value: number | bigint, op: string): number {
  const result = asNumber(value);
  if (result < 0) {
    throw new Error(`native ${op} failed (${result})`);
  }
  return result;
}

function toBytes(input: string | Uint8Array): Uint8Array {
  return typeof input === "string" ? new TextEncoder().encode(input) : input;
}

async function loadBunFfi(): Promise<BunFfiModule> {
  if (typeof Bun === "undefined") {
    throw new Error("native backend requires Bun runtime (bun:ffi)");
  }
  return import("bun:ffi") as Promise<BunFfiModule>;
}

async function instantiateBridge(options: NativeLoadOptions): Promise<NativeBridge> {
  const ffi = await loadBunFfi();
  const candidates = nativePathCandidates(options);
  if (candidates.length === 0) {
    throw new Error("no native library candidates for this platform");
  }

  const symbolDefs: Record<string, FfiFnDef> = {
    turbotoken_encode_utf8_bytes: { args: ["ptr", "usize", "ptr", "usize"], returns: "isize" },
    turbotoken_decode_utf8_bytes: { args: ["ptr", "usize", "ptr", "usize"], returns: "isize" },
    turbotoken_count_bpe_from_ranks: { args: ["ptr", "usize", "ptr", "usize"], returns: "isize" },
    turbotoken_is_within_token_limit_bpe_from_ranks: { args: ["ptr", "usize", "ptr", "usize", "usize"], returns: "isize" },
    turbotoken_encode_bpe_from_ranks: { args: ["ptr", "usize", "ptr", "usize", "ptr", "usize"], returns: "isize" },
    turbotoken_decode_bpe_from_ranks: { args: ["ptr", "usize", "ptr", "usize", "ptr", "usize"], returns: "isize" },
  };

  let lastError: unknown = null;
  for (const path of candidates) {
    if (!existsSync(path)) {
      continue;
    }
    try {
      const lib = ffi.dlopen(path, symbolDefs);
      return new NativeBridge(path, lib);
    } catch (error) {
      lastError = error;
    }
  }

  const detail = lastError ? ` last error: ${String(lastError)}` : "";
  throw new Error(`failed to load native bridge from ${candidates.length} candidates.${detail}`);
}

export async function loadNative(options: NativeLoadOptions = {}): Promise<NativeBridge> {
  if (options.forceReload) {
    nativeBridgePromise = instantiateBridge(options);
    return nativeBridgePromise;
  }
  if (nativeBridgePromise === null) {
    nativeBridgePromise = instantiateBridge(options);
  }
  return nativeBridgePromise;
}

export function clearNativeCache(): void {
  nativeBridgePromise = null;
}

export class NativeBridge {
  readonly kind = "native";

  constructor(
    readonly libraryPath: string,
    private readonly lib: BunDynamicLibrary,
  ) {}

  close(): void {
    this.lib.close?.();
  }

  encodeUtf8Bytes(input: string | Uint8Array): number[] {
    const bytes = toBytes(input);
    if (bytes.byteLength === 0) {
      return [];
    }
    const needed = checkCallResult(
      this.lib.symbols.turbotoken_encode_utf8_bytes(bytes, bytes.byteLength, 0, 0),
      "turbotoken_encode_utf8_bytes(size)",
    );
    if (needed === 0) {
      return [];
    }
    const out = new Uint32Array(needed);
    const written = checkCallResult(
      this.lib.symbols.turbotoken_encode_utf8_bytes(bytes, bytes.byteLength, out, out.length),
      "turbotoken_encode_utf8_bytes(write)",
    );
    return Array.from(out.subarray(0, written));
  }

  decodeUtf8Bytes(tokens: readonly number[]): Uint8Array {
    if (tokens.length === 0) {
      return new Uint8Array(0);
    }
    const inTokens = new Uint32Array(tokens.length);
    for (let i = 0; i < tokens.length; i += 1) {
      inTokens[i] = tokens[i] >>> 0;
    }
    const needed = checkCallResult(
      this.lib.symbols.turbotoken_decode_utf8_bytes(inTokens, inTokens.length, 0, 0),
      "turbotoken_decode_utf8_bytes(size)",
    );
    if (needed === 0) {
      return new Uint8Array(0);
    }
    const out = new Uint8Array(needed);
    const written = checkCallResult(
      this.lib.symbols.turbotoken_decode_utf8_bytes(inTokens, inTokens.length, out, out.length),
      "turbotoken_decode_utf8_bytes(write)",
    );
    return out.slice(0, written);
  }

  countBpeFromRanks(rankPayload: Uint8Array, input: string | Uint8Array): number {
    const text = toBytes(input);
    return checkCallResult(
      this.lib.symbols.turbotoken_count_bpe_from_ranks(
        rankPayload,
        rankPayload.byteLength,
        text,
        text.byteLength,
      ),
      "turbotoken_count_bpe_from_ranks",
    );
  }

  isWithinTokenLimitBpeFromRanks(
    rankPayload: Uint8Array,
    input: string | Uint8Array,
    tokenLimit: number,
  ): number | false {
    if (tokenLimit < 0) {
      throw new Error("tokenLimit must be >= 0");
    }
    const text = toBytes(input);
    const result = asNumber(this.lib.symbols.turbotoken_is_within_token_limit_bpe_from_ranks(
      rankPayload,
      rankPayload.byteLength,
      text,
      text.byteLength,
      tokenLimit,
    ));
    if (result === -2) {
      return false;
    }
    if (result < 0) {
      throw new Error(`native turbotoken_is_within_token_limit_bpe_from_ranks failed (${result})`);
    }
    return result;
  }

  encodeBpeFromRanks(rankPayload: Uint8Array, input: string | Uint8Array): number[] {
    const text = toBytes(input);
    const needed = checkCallResult(
      this.lib.symbols.turbotoken_encode_bpe_from_ranks(
        rankPayload,
        rankPayload.byteLength,
        text,
        text.byteLength,
        0,
        0,
      ),
      "turbotoken_encode_bpe_from_ranks(size)",
    );
    if (needed === 0) {
      return [];
    }
    const out = new Uint32Array(needed);
    const written = checkCallResult(
      this.lib.symbols.turbotoken_encode_bpe_from_ranks(
        rankPayload,
        rankPayload.byteLength,
        text,
        text.byteLength,
        out,
        out.length,
      ),
      "turbotoken_encode_bpe_from_ranks(write)",
    );
    return Array.from(out.subarray(0, written));
  }

  decodeBpeFromRanks(rankPayload: Uint8Array, tokens: readonly number[]): Uint8Array {
    if (tokens.length === 0) {
      return new Uint8Array(0);
    }
    const inTokens = new Uint32Array(tokens.length);
    for (let i = 0; i < tokens.length; i += 1) {
      inTokens[i] = tokens[i] >>> 0;
    }
    const needed = checkCallResult(
      this.lib.symbols.turbotoken_decode_bpe_from_ranks(
        rankPayload,
        rankPayload.byteLength,
        inTokens,
        inTokens.length,
        0,
        0,
      ),
      "turbotoken_decode_bpe_from_ranks(size)",
    );
    if (needed === 0) {
      return new Uint8Array(0);
    }
    const out = new Uint8Array(needed);
    const written = checkCallResult(
      this.lib.symbols.turbotoken_decode_bpe_from_ranks(
        rankPayload,
        rankPayload.byteLength,
        inTokens,
        inTokens.length,
        out,
        out.length,
      ),
      "turbotoken_decode_bpe_from_ranks(write)",
    );
    return out.slice(0, written);
  }
}
