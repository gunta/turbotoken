export interface EncodingSpec {
  name: string;
  rankFileUrl: string;
}

const ENCODING_SPECS: Record<string, EncodingSpec> = {
  o200k_base: {
    name: "o200k_base",
    rankFileUrl: "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
  },
  o200k_harmony: {
    name: "o200k_harmony",
    rankFileUrl: "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
  },
  cl100k_base: {
    name: "cl100k_base",
    rankFileUrl: "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
  },
  p50k_base: {
    name: "p50k_base",
    rankFileUrl: "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
  },
  p50k_edit: {
    name: "p50k_edit",
    rankFileUrl: "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
  },
  r50k_base: {
    name: "r50k_base",
    rankFileUrl: "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
  },
  gpt2: {
    name: "gpt2",
    rankFileUrl: "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
  },
};

const MODEL_TO_ENCODING: Record<string, string> = {
  o1: "o200k_base",
  o3: "o200k_base",
  "o4-mini": "o200k_base",
  "gpt-5": "o200k_base",
  "gpt-4.1": "o200k_base",
  "gpt-4o": "o200k_base",
  "gpt-4o-mini": "o200k_base",
  "gpt-4.1-mini": "o200k_base",
  "gpt-4.1-nano": "o200k_base",
  "gpt-oss-120b": "o200k_harmony",
  "gpt-4": "cl100k_base",
  "gpt-3.5-turbo": "cl100k_base",
  "gpt-35-turbo": "cl100k_base",
  davinci: "r50k_base",
  curie: "r50k_base",
  babbage: "r50k_base",
  ada: "r50k_base",
  gpt2: "gpt2",
  "gpt-2": "r50k_base",
};

const MODEL_PREFIX_TO_ENCODING: Array<[string, string]> = [
  ["o1-", "o200k_base"],
  ["o3-", "o200k_base"],
  ["o4-mini-", "o200k_base"],
  ["gpt-5-", "o200k_base"],
  ["gpt-4.5-", "o200k_base"],
  ["gpt-4.1-", "o200k_base"],
  ["chatgpt-4o-", "o200k_base"],
  ["gpt-4o-", "o200k_base"],
  ["gpt-oss-", "o200k_harmony"],
  ["gpt-4-", "cl100k_base"],
  ["gpt-3.5-turbo-", "cl100k_base"],
  ["gpt-35-turbo-", "cl100k_base"],
  ["ft:gpt-4o", "o200k_base"],
  ["ft:gpt-4", "cl100k_base"],
  ["ft:gpt-3.5-turbo", "cl100k_base"],
  ["ft:davinci-002", "cl100k_base"],
  ["ft:babbage-002", "cl100k_base"],
];

export function listEncodingNames(): string[] {
  return Object.keys(ENCODING_SPECS).sort();
}

export function getEncodingSpec(name: string): EncodingSpec {
  const spec = ENCODING_SPECS[name];
  if (spec !== undefined) {
    return spec;
  }
  const supported = listEncodingNames().join(", ");
  throw new Error(`Unknown encoding ${JSON.stringify(name)}. Supported encodings: ${supported}`);
}

export function modelToEncoding(model: string): string {
  const direct = MODEL_TO_ENCODING[model];
  if (direct !== undefined) {
    return direct;
  }
  for (const [prefix, encoding] of MODEL_PREFIX_TO_ENCODING) {
    if (model.startsWith(prefix)) {
      return encoding;
    }
  }
  throw new Error(
    `Could not automatically map ${JSON.stringify(model)} to an encoding. Use getEncoding(name) explicitly.`,
  );
}
