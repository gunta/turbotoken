import {
  type BackendMode,
  Encoding,
  type ChatMessage,
  type ChatOptions,
  type ChatTemplate,
  type ChatTemplateMode,
  type EncodingOptions,
} from "./encoding";
import { listEncodingNames, modelToEncoding } from "./registry";
import { clearWasmCache, loadWasm, type BpeMerge, type WasmLoadOptions, type WasmBridge } from "./wasm-loader";
import { clearNativeCache, loadNative, type NativeBridge, type NativeLoadOptions } from "./native-loader";

export { Encoding, listEncodingNames, loadWasm, clearWasmCache, loadNative, clearNativeCache };
export type {
  BackendMode,
  ChatMessage,
  ChatOptions,
  ChatTemplate,
  ChatTemplateMode,
  EncodingOptions,
  NativeLoadOptions,
  NativeBridge,
  WasmLoadOptions,
  WasmBridge,
  BpeMerge,
};

const textEncoder = new TextEncoder();

export function getEncoding(name: string, options: EncodingOptions = {}): Encoding {
  return new Encoding(name, options);
}

export async function getEncodingAsync(name: string, options: EncodingOptions = {}): Promise<Encoding> {
  return Encoding.create(name, options);
}

export function encodingForModel(model: string, options: EncodingOptions = {}): Encoding {
  return new Encoding(modelToEncoding(model), options);
}

export async function encodingForModelAsync(model: string, options: EncodingOptions = {}): Promise<Encoding> {
  return Encoding.create(modelToEncoding(model), options);
}

export interface TrainBpeFromChunkCountsInput {
  chunks: string | Uint8Array;
  chunkOffsets: readonly number[];
  chunkCounts: readonly number[];
  vocabSize: number;
  minFrequency?: number;
  wasm?: WasmLoadOptions;
}

export interface TrainBpeFromChunksInput {
  chunks: readonly (string | Uint8Array)[];
  chunkCounts?: readonly number[];
  vocabSize: number;
  minFrequency?: number;
  wasm?: WasmLoadOptions;
}

function toBytes(input: string | Uint8Array): Uint8Array {
  return typeof input === "string" ? textEncoder.encode(input) : input;
}

function flattenChunks(chunks: readonly (string | Uint8Array)[]): { packed: Uint8Array; offsets: number[] } {
  const chunkBytes = chunks.map((chunk) => toBytes(chunk));
  const offsets = new Array<number>(chunkBytes.length + 1);
  offsets[0] = 0;

  let totalLen = 0;
  for (let i = 0; i < chunkBytes.length; i += 1) {
    totalLen += chunkBytes[i].length;
    offsets[i + 1] = totalLen;
  }

  const packed = new Uint8Array(totalLen);
  let cursor = 0;
  for (const chunk of chunkBytes) {
    packed.set(chunk, cursor);
    cursor += chunk.length;
  }

  return { packed, offsets };
}

export async function trainBpeFromChunkCounts(input: TrainBpeFromChunkCountsInput): Promise<BpeMerge[]> {
  const chunks = toBytes(input.chunks);
  const minFrequency = input.minFrequency ?? 1;
  const bridge = await loadWasm(input.wasm ?? {});
  return bridge.trainBpeFromChunkCounts(chunks, input.chunkOffsets, input.chunkCounts, {
    vocabSize: input.vocabSize,
    minFrequency,
  });
}

export async function trainBpeFromChunks(input: TrainBpeFromChunksInput): Promise<BpeMerge[]> {
  const { packed, offsets } = flattenChunks(input.chunks);
  const counts = input.chunkCounts ?? new Array<number>(input.chunks.length).fill(1);
  if (counts.length !== input.chunks.length) {
    throw new Error("chunkCounts length must match chunks length");
  }

  return trainBpeFromChunkCounts({
    chunks: packed,
    chunkOffsets: offsets,
    chunkCounts: counts,
    vocabSize: input.vocabSize,
    minFrequency: input.minFrequency,
    wasm: input.wasm,
  });
}
