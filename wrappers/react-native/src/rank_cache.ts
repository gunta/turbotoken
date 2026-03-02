import { Platform } from "react-native";

let cacheDir: string | null = null;

function getCacheDir(): string {
  if (cacheDir !== null) return cacheDir;
  if (Platform.OS === "ios") {
    cacheDir = "";
  } else {
    cacheDir = "";
  }
  return cacheDir;
}

async function fileExists(path: string): Promise<boolean> {
  try {
    const RNFS = require("react-native-fs");
    return await RNFS.exists(path);
  } catch {
    return false;
  }
}

async function readFileBase64(path: string): Promise<string> {
  const RNFS = require("react-native-fs");
  return RNFS.readFile(path, "base64");
}

async function writeFileBase64(path: string, data: string): Promise<void> {
  const RNFS = require("react-native-fs");
  return RNFS.writeFile(path, data, "base64");
}

function resolveRnfsCacheDir(): string {
  try {
    const RNFS = require("react-native-fs");
    return RNFS.CachesDirectoryPath;
  } catch {
    return "/tmp";
  }
}

function encodingCachePath(encodingName: string): string {
  const dir = getCacheDir() || resolveRnfsCacheDir();
  return `${dir}/turbotoken_${encodingName}.tiktoken`;
}

export async function fetchRankBase64(
  encodingName: string,
  url: string
): Promise<string> {
  const cachePath = encodingCachePath(encodingName);

  if (await fileExists(cachePath)) {
    return readFileBase64(cachePath);
  }

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(
      `Failed to fetch rank file from ${url}: HTTP ${response.status}`
    );
  }

  const arrayBuffer = await response.arrayBuffer();
  const bytes = new Uint8Array(arrayBuffer);
  const base64 = uint8ArrayToBase64(bytes);

  try {
    await writeFileBase64(cachePath, base64);
  } catch {
    // Cache write failure is non-fatal
  }

  return base64;
}

function uint8ArrayToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]!);
  }
  return globalThis.btoa(binary);
}

const rankBase64Cache = new Map<string, Promise<string>>();

export function cachedFetchRankBase64(
  encodingName: string,
  url: string
): Promise<string> {
  const key = encodingName;
  const existing = rankBase64Cache.get(key);
  if (existing) return existing;
  const promise = fetchRankBase64(encodingName, url);
  rankBase64Cache.set(key, promise);
  return promise;
}

export function clearRankCache(): void {
  rankBase64Cache.clear();
}
