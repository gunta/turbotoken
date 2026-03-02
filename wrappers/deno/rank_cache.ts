import { getEncodingSpec } from "./registry.ts";

export function cacheDir(): string {
  const xdgCache = Deno.env.get("XDG_CACHE_HOME");
  const base = xdgCache || `${Deno.env.get("HOME")}/.cache`;
  return `${base}/turbotoken`;
}

export async function ensureRankFile(name: string): Promise<string> {
  const spec = getEncodingSpec(name);
  const url = new URL(spec.rankFileUrl);
  const fileName = url.pathname.split("/").pop()!;
  const dir = cacheDir();
  const localPath = `${dir}/${fileName}`;

  try {
    await Deno.stat(localPath);
    return localPath;
  } catch {
    // File doesn't exist, download it
  }

  await Deno.mkdir(dir, { recursive: true });

  const response = await fetch(spec.rankFileUrl);
  if (!response.ok) {
    throw new Error(
      `Failed to download rank file for ${name}: ${response.statusText}`,
    );
  }

  const data = new Uint8Array(await response.arrayBuffer());
  const tempPath = `${localPath}.tmp`;
  await Deno.writeFile(tempPath, data);
  await Deno.rename(tempPath, localPath);

  return localPath;
}

export async function readRankFile(name: string): Promise<Uint8Array> {
  const filePath = await ensureRankFile(name);
  return await Deno.readFile(filePath);
}
