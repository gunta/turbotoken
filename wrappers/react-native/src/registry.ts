export interface EncodingSpec {
  name: string;
  rankFileUrl: string;
  patStr: string;
  specialTokens: Record<string, number>;
  explicitNVocab: number;
}

const ENDOFTEXT = "<|endoftext|>";
const FIM_PREFIX = "<|fim_prefix|>";
const FIM_MIDDLE = "<|fim_middle|>";
const FIM_SUFFIX = "<|fim_suffix|>";
const ENDOFPROMPT = "<|endofprompt|>";

const R50K_PAT_STR =
  "'(?:[sdmt]|ll|ve|re)| ?\\p{L}++| ?\\p{N}++| ?[^\\s\\p{L}\\p{N}]++|\\s++$|\\s+(?!\\S)|\\s";

const CL100K_PAT_STR =
  "'(?i:[sdmt]|ll|ve|re)|[^\\r\\n\\p{L}\\p{N}]?+\\p{L}++|\\p{N}{1,3}+| ?[^\\s\\p{L}\\p{N}]++[\\r\\n]*+|\\s++$|\\s*[\\r\\n]|\\s+(?!\\S)|\\s";

const O200K_PAT_STR = [
  "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]*[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
  "[^\\r\\n\\p{L}\\p{N}]?[\\p{Lu}\\p{Lt}\\p{Lm}\\p{Lo}\\p{M}]+[\\p{Ll}\\p{Lm}\\p{Lo}\\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
  "\\p{N}{1,3}",
  " ?[^\\s\\p{L}\\p{N}]+[\\r\\n/]*",
  "\\s*[\\r\\n]+",
  "\\s+(?!\\S)",
  "\\s+",
].join("|");

const ENCODING_SPECS: Record<string, EncodingSpec> = {
  o200k_base: {
    name: "o200k_base",
    rankFileUrl:
      "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
    patStr: O200K_PAT_STR,
    specialTokens: { [ENDOFTEXT]: 199999, [ENDOFPROMPT]: 200018 },
    explicitNVocab: 200019,
  },
  cl100k_base: {
    name: "cl100k_base",
    rankFileUrl:
      "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
    patStr: CL100K_PAT_STR,
    specialTokens: {
      [ENDOFTEXT]: 100257,
      [FIM_PREFIX]: 100258,
      [FIM_MIDDLE]: 100259,
      [FIM_SUFFIX]: 100260,
      [ENDOFPROMPT]: 100276,
    },
    explicitNVocab: 100277,
  },
  p50k_base: {
    name: "p50k_base",
    rankFileUrl:
      "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
    patStr: R50K_PAT_STR,
    specialTokens: { [ENDOFTEXT]: 50256 },
    explicitNVocab: 50281,
  },
  r50k_base: {
    name: "r50k_base",
    rankFileUrl:
      "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
    patStr: R50K_PAT_STR,
    specialTokens: { [ENDOFTEXT]: 50256 },
    explicitNVocab: 50257,
  },
  gpt2: {
    name: "gpt2",
    rankFileUrl:
      "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
    patStr: R50K_PAT_STR,
    specialTokens: { [ENDOFTEXT]: 50256 },
    explicitNVocab: 50257,
  },
  p50k_edit: {
    name: "p50k_edit",
    rankFileUrl:
      "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
    patStr: R50K_PAT_STR,
    specialTokens: { [ENDOFTEXT]: 50256 },
    explicitNVocab: 50281,
  },
  o200k_harmony: {
    name: "o200k_harmony",
    rankFileUrl:
      "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
    patStr: O200K_PAT_STR,
    specialTokens: { [ENDOFTEXT]: 199999, [ENDOFPROMPT]: 200018 },
    explicitNVocab: 200019,
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
  "gpt-3.5": "cl100k_base",
  "gpt-35-turbo": "cl100k_base",
  "davinci-002": "cl100k_base",
  "babbage-002": "cl100k_base",
  "text-embedding-ada-002": "cl100k_base",
  "text-embedding-3-small": "cl100k_base",
  "text-embedding-3-large": "cl100k_base",
  "text-davinci-003": "p50k_base",
  "text-davinci-002": "p50k_base",
  "text-davinci-001": "r50k_base",
  "text-curie-001": "r50k_base",
  "text-babbage-001": "r50k_base",
  "text-ada-001": "r50k_base",
  davinci: "r50k_base",
  curie: "r50k_base",
  babbage: "r50k_base",
  ada: "r50k_base",
  "code-davinci-002": "p50k_base",
  "code-davinci-001": "p50k_base",
  "code-cushman-002": "p50k_base",
  "code-cushman-001": "p50k_base",
  "davinci-codex": "p50k_base",
  "cushman-codex": "p50k_base",
  "text-davinci-edit-001": "p50k_edit",
  "code-davinci-edit-001": "p50k_edit",
  "text-similarity-davinci-001": "r50k_base",
  "text-similarity-curie-001": "r50k_base",
  "text-similarity-babbage-001": "r50k_base",
  "text-similarity-ada-001": "r50k_base",
  "text-search-davinci-doc-001": "r50k_base",
  "text-search-curie-doc-001": "r50k_base",
  "text-search-babbage-doc-001": "r50k_base",
  "text-search-ada-doc-001": "r50k_base",
  "code-search-babbage-code-001": "r50k_base",
  "code-search-ada-code-001": "r50k_base",
  gpt2: "gpt2",
  "gpt-2": "r50k_base",
};

const MODEL_PREFIX_TO_ENCODING: [string, string][] = [
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

export function getEncodingSpec(name: string): EncodingSpec {
  const spec = ENCODING_SPECS[name];
  if (!spec) {
    const supported = listEncodingNames().join(", ");
    throw new Error(
      `Unknown encoding '${name}'. Supported encodings: ${supported}`
    );
  }
  return spec;
}

export function modelToEncoding(model: string): string {
  const direct = MODEL_TO_ENCODING[model];
  if (direct) {
    return direct;
  }
  for (const [prefix, encoding] of MODEL_PREFIX_TO_ENCODING) {
    if (model.startsWith(prefix)) {
      return encoding;
    }
  }
  throw new Error(
    `Could not automatically map '${model}' to an encoding. ` +
      "Use getEncoding(name) to select one explicitly."
  );
}

export function listEncodingNames(): string[] {
  return Object.keys(ENCODING_SPECS).sort();
}
