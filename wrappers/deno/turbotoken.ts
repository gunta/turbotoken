import { lib, readCString } from "./ffi.ts";
import { Encoding } from "./encoding.ts";
import {
  getEncodingSpec,
  listEncodingNames as listNames,
  modelToEncoding,
} from "./registry.ts";
import { readRankFile } from "./rank_cache.ts";

export async function getEncoding(name: string): Promise<Encoding> {
  const spec = getEncodingSpec(name);
  const rankData = await readRankFile(spec.name);
  return new Encoding(spec.name, spec, rankData);
}

export async function getEncodingForModel(model: string): Promise<Encoding> {
  const encodingName = modelToEncoding(model);
  return await getEncoding(encodingName);
}

export function listEncodingNames(): string[] {
  return listNames();
}

export function version(): string {
  const ptr = lib.symbols.turbotoken_version();
  if (!ptr) return "unknown";
  return readCString(ptr);
}
