import { getEncodingSpec, type EncodingSpec } from "./registry";
import { loadWasm, type WasmBridge, type WasmLoadOptions } from "./wasm-loader";

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const rankPayloadCache = new Map<string, Promise<Uint8Array>>();

export interface EncodingOptions {
  wasm?: WasmLoadOptions;
  rankPayload?: Uint8Array;
  rankUrlOverride?: string;
  enableWasmBpe?: boolean;
  eagerLoad?: boolean;
}

async function fetchRankPayload(url: string): Promise<Uint8Array> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`failed to fetch rank payload from ${url}: HTTP ${response.status}`);
  }
  return new Uint8Array(await response.arrayBuffer());
}

function cachedRankPayload(url: string): Promise<Uint8Array> {
  const cached = rankPayloadCache.get(url);
  if (cached !== undefined) {
    return cached;
  }
  const pending = fetchRankPayload(url);
  rankPayloadCache.set(url, pending);
  return pending;
}

function decodeByteFallback(tokens: readonly number[]): string {
  const bytes = new Uint8Array(tokens.length);
  for (let i = 0; i < tokens.length; i += 1) {
    bytes[i] = tokens[i] & 0xff;
  }
  return decoder.decode(bytes);
}

function encodeByteFallback(text: string): number[] {
  return Array.from(encoder.encode(text));
}

export class Encoding {
  private readonly spec: EncodingSpec;
  private readonly wasmOptions: WasmLoadOptions;
  private readonly rankUrlOverride?: string;
  private readonly enableWasmBpe: boolean;

  private bridge: WasmBridge | null = null;
  private rankPayload: Uint8Array | null = null;
  private loadPromise: Promise<void> | null = null;

  constructor(public readonly name: string, options: EncodingOptions = {}) {
    this.spec = getEncodingSpec(name);
    this.wasmOptions = options.wasm ?? {};
    this.rankUrlOverride = options.rankUrlOverride;
    this.rankPayload = options.rankPayload ?? null;
    this.enableWasmBpe = options.enableWasmBpe ?? false;

    if (options.eagerLoad) {
      void this.ready();
    }
  }

  static async create(name: string, options: EncodingOptions = {}): Promise<Encoding> {
    const enc = new Encoding(name, options);
    await enc.ready();
    return enc;
  }

  isReady(): boolean {
    if (!this.enableWasmBpe) {
      return this.bridge !== null;
    }
    return this.bridge !== null && this.rankPayload !== null;
  }

  async ready(): Promise<void> {
    if (this.isReady()) {
      return;
    }
    if (this.loadPromise === null) {
      this.loadPromise = this.load();
    }
    await this.loadPromise;
  }

  private async load(): Promise<void> {
    const bridgePromise = loadWasm(this.wasmOptions);
    const rankPromise: Promise<Uint8Array | null> = this.enableWasmBpe
      ? this.rankPayload !== null
        ? Promise.resolve(this.rankPayload)
        : cachedRankPayload(this.rankUrlOverride ?? this.spec.rankFileUrl)
      : Promise.resolve(this.rankPayload);

    const [bridge, rankPayload] = await Promise.all([bridgePromise, rankPromise]);
    this.bridge = bridge;
    this.rankPayload = rankPayload;
  }

  encode(text: string): number[] {
    if (!this.enableWasmBpe || !this.isReady()) {
      return encodeByteFallback(text);
    }
    try {
      return this.bridge!.encodeBpeFromRanks(this.rankPayload!, text);
    } catch {
      return encodeByteFallback(text);
    }
  }

  async encodeAsync(text: string): Promise<number[]> {
    await this.ready();
    if (!this.enableWasmBpe) {
      return encodeByteFallback(text);
    }
    try {
      return this.bridge!.encodeBpeFromRanks(this.rankPayload!, text);
    } catch {
      return encodeByteFallback(text);
    }
  }

  decode(tokens: readonly number[]): string {
    if (!this.enableWasmBpe || !this.isReady()) {
      return decodeByteFallback(tokens);
    }
    try {
      const bytes = this.bridge!.decodeBpeFromRanks(this.rankPayload!, tokens);
      return decoder.decode(bytes);
    } catch {
      return decodeByteFallback(tokens);
    }
  }

  async decodeAsync(tokens: readonly number[]): Promise<string> {
    await this.ready();
    if (!this.enableWasmBpe) {
      return decodeByteFallback(tokens);
    }
    try {
      const bytes = this.bridge!.decodeBpeFromRanks(this.rankPayload!, tokens);
      return decoder.decode(bytes);
    } catch {
      return decodeByteFallback(tokens);
    }
  }

  count(text: string): number {
    if (!this.enableWasmBpe || !this.isReady()) {
      return encodeByteFallback(text).length;
    }
    try {
      return this.bridge!.countBpeFromRanks(this.rankPayload!, text);
    } catch {
      return encodeByteFallback(text).length;
    }
  }

  async countAsync(text: string): Promise<number> {
    await this.ready();
    if (!this.enableWasmBpe) {
      return encodeByteFallback(text).length;
    }
    try {
      return this.bridge!.countBpeFromRanks(this.rankPayload!, text);
    } catch {
      return encodeByteFallback(text).length;
    }
  }
}
