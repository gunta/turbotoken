#!/usr/bin/env bun
import { existsSync } from "node:fs";
import { runBench, type BenchCommand } from "./_bench";
import { ensureFixtures } from "./_fixtures";
import { pythonExecutable, resolvePath, runShell, section } from "./_lib";

ensureFixtures();
const python = process.env.TURBOTOKEN_BENCH_PYTHON?.trim() || pythonExecutable();
const fastMode = ["1", "true", "yes", "on"].includes(
  (process.env.TURBOTOKEN_BENCH_COMPETITORS_FAST ?? process.env.TURBOTOKEN_BENCH_FAST ?? "").trim().toLowerCase(),
);
if (fastMode) {
  section("Competitors benchmark fast mode enabled");
}

const fullTextFixtures = [
  { id: "1kb", path: "bench/fixtures/english-1kb.txt", bytes: 1_024 },
  { id: "10kb", path: "bench/fixtures/english-10kb.txt", bytes: 10_240 },
  { id: "100kb", path: "bench/fixtures/english-100kb.txt", bytes: 102_400 },
  { id: "1mb", path: "bench/fixtures/english-1mb.txt", bytes: 1_048_576 },
] as const;
const ciRequiredFixture = fullTextFixtures[3];
const textFixtures = fastMode
  ? [fullTextFixtures[0], fullTextFixtures[2]]
  : fullTextFixtures;

const decodeTokenSizes = fastMode ? [1_000, 10_000] : [1_000, 10_000, 128_000];
const decodeFixturePath = "bench/fixtures/english-1mb.tokens.json";

function hasPythonModule(name: string): boolean {
  const result = runShell(
    `${python} -c "import importlib.util,sys;sys.exit(0 if importlib.util.find_spec('${name}') else 1)"`,
    { allowFailure: true },
  );
  return result.code === 0;
}

function hasBunModule(name: string): boolean {
  const result = runShell(
    `bun -e "import('${name}').then(()=>process.exit(0)).catch(()=>process.exit(1))"`,
    { allowFailure: true },
  );
  return result.code === 0;
}

const availability = {
  tiktoken: hasPythonModule("tiktoken"),
  rs_bpe: hasPythonModule("rs_bpe"),
  token_dagger: hasPythonModule("token_dagger") || hasPythonModule("tokendagger"),
  gpt_tokenizer: hasBunModule("gpt-tokenizer"),
  tokenizers: hasPythonModule("tokenizers"),
};

const metalProbe = runShell(
  `${python} -c "import sys;sys.path.insert(0,'python');from turbotoken import _gpu;raise SystemExit(0 if _gpu.backend_info().get('available') else 1)"`,
  { allowFailure: true },
);
const metalAvailable = metalProbe.code === 0;

if (availability.tokenizers) {
  console.warn(
    "python tokenizers package is installed, but o200k_base is not directly exposed via a stable built-in API; skipping tokenizers rows for this benchmark matrix.",
  );
}

function ensureDecodeFixture() {
  const absPath = resolvePath(decodeFixturePath);
  if (existsSync(absPath)) {
    return;
  }

  section(`Generating decode fixture: ${decodeFixturePath}`);
  runShell(
    `${python} -c "import importlib.util,json,pathlib,sys;text=pathlib.Path('bench/fixtures/english-1mb.txt').read_text()\nif importlib.util.find_spec('tiktoken'):\n import tiktoken;enc=tiktoken.get_encoding('o200k_base')\nelse:\n sys.path.insert(0,'python');from turbotoken import get_encoding;enc=get_encoding('o200k_base')\ntokens=enc.encode(text);pathlib.Path('${decodeFixturePath}').write_text(json.dumps(tokens),encoding='utf-8')"`,
  );
}

function decodeFixtureTokenCount(): number {
  const result = runShell(
    `${python} -c "import json,pathlib;tokens=json.loads(pathlib.Path('${decodeFixturePath}').read_text(encoding='utf-8'));print(len(tokens))"`,
  );
  return Number.parseInt(result.stdout.trim(), 10);
}

function encodeCommandForTurbotoken(
  path: string,
  { nativeO200kFull = false }: { nativeO200kFull?: boolean } = {},
): string {
  const envPrefix = nativeO200kFull ? "TURBOTOKEN_NATIVE_O200K_FULL_ENABLE=1 " : "";
  return `${envPrefix}${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;text=pathlib.Path('${path}').read_text();get_encoding('o200k_base').encode(text)"`;
}

function encodeCommandForTurbotokenMetal(path: string): string {
  return `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;text=pathlib.Path('${path}').read_text();get_encoding('o200k_base').encode_gpu([text],device='metal',strict_verify=False)[0]"`;
}

function encodeCommandForTiktoken(path: string): string {
  return `${python} -c "import pathlib,tiktoken;text=pathlib.Path('${path}').read_text();tiktoken.get_encoding('o200k_base').encode(text)"`;
}

function encodeCommandForRsBpe(path: string): string {
  return `${python} -c "import pathlib;from rs_bpe.bpe import openai;text=pathlib.Path('${path}').read_text();openai.o200k_base().encode(text)"`;
}

function encodeCommandForTokenDagger(path: string): string {
  return `${python} -c "import importlib.util,pathlib;text=pathlib.Path('${path}').read_text()\nif importlib.util.find_spec('token_dagger'):\n import token_dagger as td\n enc=td.get_encoding('o200k_base')\nelse:\n import tiktoken,tokendagger as td\n base=tiktoken.get_encoding('o200k_base')\n enc=td.Encoding('o200k_base',pat_str=base._pat_str,mergeable_ranks=base._mergeable_ranks,special_tokens=base._special_tokens)\nenc.encode(text)"`;
}

function encodeCommandForGptTokenizer(path: string): string {
  return `bun -e "import { encode } from 'gpt-tokenizer'; import { readFileSync } from 'node:fs'; const text = readFileSync('${path}', 'utf8'); encode(text);"`;
}

function decodeCommandForTurbotoken(tokens: number): string {
  return `${python} -c "import json,pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;vals=json.loads(pathlib.Path('${decodeFixturePath}').read_text(encoding='utf-8'))[:${tokens}];get_encoding('o200k_base').decode(vals)"`;
}

function decodeCommandForTiktoken(tokens: number): string {
  return `${python} -c "import json,pathlib,tiktoken;vals=json.loads(pathlib.Path('${decodeFixturePath}').read_text(encoding='utf-8'))[:${tokens}];tiktoken.get_encoding('o200k_base').decode(vals)"`;
}

function decodeCommandForRsBpe(tokens: number): string {
  return `${python} -c "import json,pathlib;from rs_bpe.bpe import openai;vals=json.loads(pathlib.Path('${decodeFixturePath}').read_text(encoding='utf-8'))[:${tokens}];openai.o200k_base().decode(vals)"`;
}

function decodeCommandForTokenDagger(tokens: number): string {
  return `${python} -c "import importlib.util,json,pathlib;vals=json.loads(pathlib.Path('${decodeFixturePath}').read_text(encoding='utf-8'))[:${tokens}]\nif importlib.util.find_spec('token_dagger'):\n import token_dagger as td\n enc=td.get_encoding('o200k_base')\nelse:\n import tiktoken,tokendagger as td\n base=tiktoken.get_encoding('o200k_base')\n enc=td.Encoding('o200k_base',pat_str=base._pat_str,mergeable_ranks=base._mergeable_ranks,special_tokens=base._special_tokens)\nenc.decode(vals)"`;
}

function decodeCommandForGptTokenizer(tokens: number): string {
  return `bun -e "import { decode } from 'gpt-tokenizer'; import { readFileSync } from 'node:fs'; const vals = JSON.parse(readFileSync('${decodeFixturePath}', 'utf8')).slice(0, ${tokens}); decode(vals);"`;
}

function countCommandForTurbotoken(path: string): string {
  return `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;text=pathlib.Path('${path}').read_text();get_encoding('o200k_base').count(text)"`;
}

function countCommandForTiktoken(path: string): string {
  return `${python} -c "import pathlib,tiktoken;text=pathlib.Path('${path}').read_text();len(tiktoken.get_encoding('o200k_base').encode(text))"`;
}

function countCommandForRsBpe(path: string): string {
  return `${python} -c "import pathlib;from rs_bpe.bpe import openai;text=pathlib.Path('${path}').read_text();openai.o200k_base().count(text)"`;
}

function countCommandForTokenDagger(path: string): string {
  return `${python} -c "import importlib.util,pathlib;text=pathlib.Path('${path}').read_text()\nif importlib.util.find_spec('token_dagger'):\n import token_dagger as td\n enc=td.get_encoding('o200k_base')\nelse:\n import tiktoken,tokendagger as td\n base=tiktoken.get_encoding('o200k_base')\n enc=td.Encoding('o200k_base',pat_str=base._pat_str,mergeable_ranks=base._mergeable_ranks,special_tokens=base._special_tokens)\nlen(enc.encode(text))"`;
}

function countCommandForGptTokenizer(path: string): string {
  return `bun -e "import { countTokens } from 'gpt-tokenizer'; import { readFileSync } from 'node:fs'; const text = readFileSync('${path}', 'utf8'); countTokens(text);"`;
}

const encodeCommands: BenchCommand[] = [];
for (const fixture of textFixtures) {
  encodeCommands.push({
    name: `python-encode-${fixture.id}-turbotoken`,
    command: encodeCommandForTurbotoken(fixture.path, {
      nativeO200kFull: fixture.id === "1mb",
    }),
  });
  if (metalAvailable) {
    encodeCommands.push({
      name: `python-encode-${fixture.id}-turbotoken-metal`,
      command: encodeCommandForTurbotokenMetal(fixture.path),
    });
  }
  if (availability.tiktoken) {
    encodeCommands.push({
      name: `python-encode-${fixture.id}-tiktoken`,
      command: encodeCommandForTiktoken(fixture.path),
    });
  }
  if (availability.rs_bpe) {
    encodeCommands.push({
      name: `python-encode-${fixture.id}-rs-bpe`,
      command: encodeCommandForRsBpe(fixture.path),
    });
  }
  if (availability.token_dagger) {
    encodeCommands.push({
      name: `python-encode-${fixture.id}-token-dagger`,
      command: encodeCommandForTokenDagger(fixture.path),
    });
  }
  if (availability.gpt_tokenizer) {
    encodeCommands.push({
      name: `js-encode-${fixture.id}-gpt-tokenizer`,
      command: encodeCommandForGptTokenizer(fixture.path),
    });
  }
}
if (fastMode) {
  // Keep CI governance metrics available in fast mode without re-enabling the full matrix.
  encodeCommands.push({
    name: `python-encode-${ciRequiredFixture.id}-turbotoken`,
    command: encodeCommandForTurbotoken(ciRequiredFixture.path, { nativeO200kFull: true }),
  });
}

ensureDecodeFixture();
const tokenCount = decodeFixtureTokenCount();
const decodeCommands: BenchCommand[] = [];
for (const size of decodeTokenSizes) {
  if (tokenCount < size) {
    console.warn(
      `decode fixture has ${tokenCount.toLocaleString()} tokens; skipping ${size.toLocaleString()} token decode row.`,
    );
    continue;
  }
  decodeCommands.push({
    name: `python-decode-${size}-tok-turbotoken`,
    command: decodeCommandForTurbotoken(size),
  });
  if (availability.tiktoken) {
    decodeCommands.push({
      name: `python-decode-${size}-tok-tiktoken`,
      command: decodeCommandForTiktoken(size),
    });
  }
  if (availability.rs_bpe) {
    decodeCommands.push({
      name: `python-decode-${size}-tok-rs-bpe`,
      command: decodeCommandForRsBpe(size),
    });
  }
  if (availability.token_dagger) {
    decodeCommands.push({
      name: `python-decode-${size}-tok-token-dagger`,
      command: decodeCommandForTokenDagger(size),
    });
  }
  if (availability.gpt_tokenizer) {
    decodeCommands.push({
      name: `js-decode-${size}-tok-gpt-tokenizer`,
      command: decodeCommandForGptTokenizer(size),
    });
  }
}

const countFixtures = fastMode
  ? [
    textFixtures[0], // 1kb
    textFixtures[textFixtures.length - 1], // 100kb in fast mode
  ]
  : [
    textFixtures[0], // 1kb
    textFixtures[2], // 100kb
    textFixtures[3], // 1mb
  ];
const countCommands: BenchCommand[] = [];
for (const fixture of countFixtures) {
  countCommands.push({
    name: `python-count-${fixture.id}-turbotoken`,
    command: countCommandForTurbotoken(fixture.path),
  });
  if (availability.tiktoken) {
    countCommands.push({
      name: `python-count-${fixture.id}-tiktoken-via-len-encode`,
      command: countCommandForTiktoken(fixture.path),
    });
  }
  if (availability.rs_bpe) {
    countCommands.push({
      name: `python-count-${fixture.id}-rs-bpe`,
      command: countCommandForRsBpe(fixture.path),
    });
  }
  if (availability.token_dagger) {
    countCommands.push({
      name: `python-count-${fixture.id}-token-dagger-via-len-encode`,
      command: countCommandForTokenDagger(fixture.path),
    });
  }
  if (availability.gpt_tokenizer) {
    countCommands.push({
      name: `js-count-${fixture.id}-gpt-tokenizer`,
      command: countCommandForGptTokenizer(fixture.path),
    });
  }
}
if (fastMode) {
  // Keep CI governance metrics available in fast mode without re-enabling the full matrix.
  countCommands.push({
    name: `python-count-${ciRequiredFixture.id}-turbotoken`,
    command: countCommandForTurbotoken(ciRequiredFixture.path),
  });
}

const encodeFixtureMetadata = fastMode ? [...textFixtures, ciRequiredFixture] : textFixtures;
const countFixtureMetadata = fastMode ? [...countFixtures, ciRequiredFixture] : countFixtures;

let failures = 0;
if (encodeCommands.length > 0) {
  failures += runBench({
    name: "bench-competitors-python-encode",
    commands: encodeCommands,
    metadata: {
      operation: "encode",
      encoding: "o200k_base",
      fixtures: encodeFixtureMetadata,
      availability,
      metalAvailable,
      fastMode,
      note: "Competitor matrix uses Python package APIs on o200k_base where available and Bun JS API rows for gpt-tokenizer; this repository remains in scaffold/early implementation stage.",
    },
  });
}

if (decodeCommands.length > 0) {
  failures += runBench({
    name: "bench-competitors-python-decode",
    commands: decodeCommands,
    metadata: {
      operation: "decode",
      encoding: "o200k_base",
      decodeFixture: decodeFixturePath,
      decodeTokenSizes,
      decodeFixtureTokenCount: tokenCount,
      availability,
      fastMode,
      note: "Decode rows use first-N tokens from a 1MB fixture tokenized with o200k_base.",
    },
  });
}

if (countCommands.length > 0) {
  failures += runBench({
    name: "bench-competitors-python-count",
    commands: countCommands,
    metadata: {
      operation: "count",
      encoding: "o200k_base",
      fixtures: countFixtureMetadata,
      availability,
      fastMode,
      note: "tiktoken and token-dagger count rows use len(encode(text)) to keep API behavior comparable.",
    },
  });
}

process.exit(failures === 0 ? 0 : 1);
