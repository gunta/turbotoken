#!/usr/bin/env bun
import { runBench, type BenchCommand } from "./_bench";
import { ensureFixtures } from "./_fixtures";
import { pythonExecutable, runShell } from "./_lib";

ensureFixtures();

const python = process.env.TURBOTOKEN_BENCH_PYTHON?.trim() || pythonExecutable();
const chatFixturePath = "bench/fixtures/chat-sample.json";
const tokenLimit = 4096;

function hasBunModule(name: string): boolean {
  const result = runShell(
    `bun -e "import('${name}').then(()=>process.exit(0)).catch(()=>process.exit(1))"`,
    { allowFailure: true },
  );
  return result.code === 0;
}

const availability = {
  gpt_tokenizer: hasBunModule("gpt-tokenizer"),
};

const commands: BenchCommand[] = [
  {
    name: "python-chat-encode-turbotoken",
    command: `${python} -c "import json,pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;messages=json.loads(pathlib.Path('${chatFixturePath}').read_text(encoding='utf-8'));get_encoding('o200k_base').encode_chat(messages, template='im_tokens')"`,
  },
  {
    name: "python-chat-count-turbotoken",
    command: `${python} -c "import json,pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;messages=json.loads(pathlib.Path('${chatFixturePath}').read_text(encoding='utf-8'));get_encoding('o200k_base').count_chat(messages, template='im_tokens')"`,
  },
  {
    name: "python-chat-limit-turbotoken",
    command: `${python} -c "import json,pathlib,sys;sys.path.insert(0,'python');from turbotoken import get_encoding;messages=json.loads(pathlib.Path('${chatFixturePath}').read_text(encoding='utf-8'));get_encoding('o200k_base').is_chat_within_token_limit(messages, ${tokenLimit}, template='im_tokens')"`,
  },
];

if (availability.gpt_tokenizer) {
  commands.push(
    {
      name: "js-chat-encode-gpt-tokenizer",
      command: `bun -e "import { encodeChat } from 'gpt-tokenizer/model/gpt-4o'; import { readFileSync } from 'node:fs'; const messages = JSON.parse(readFileSync('${chatFixturePath}', 'utf8')); encodeChat(messages);"`,
    },
    {
      name: "js-chat-count-gpt-tokenizer",
      command: `bun -e "import { countTokens } from 'gpt-tokenizer/model/gpt-4o'; import { readFileSync } from 'node:fs'; const messages = JSON.parse(readFileSync('${chatFixturePath}', 'utf8')); countTokens(messages);"`,
    },
    {
      name: "js-chat-limit-gpt-tokenizer",
      command: `bun -e "import { isWithinTokenLimit } from 'gpt-tokenizer/model/gpt-4o'; import { readFileSync } from 'node:fs'; const messages = JSON.parse(readFileSync('${chatFixturePath}', 'utf8')); isWithinTokenLimit(messages, ${tokenLimit});"`,
    },
  );
}

const failures = runBench({
  name: "bench-chat-helpers",
  commands,
  metadata: {
    operation: "chat-helpers",
    encoding: "o200k_base",
    fixture: chatFixturePath,
    tokenLimit,
    turbotokenTemplate: "im_tokens",
    gptTokenizerModelModule: "gpt-4o",
    availability,
    note: "Chat helper benchmark (encode/count/is-within-limit). turbotoken rows use template='im_tokens' for compatibility-style framing. Repository remains scaffold/optimization-stage.",
  },
});

process.exit(failures === 0 ? 0 : 1);
