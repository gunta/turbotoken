const rowsEl = document.getElementById("rows");
const logEl = document.getElementById("log");
const runBtn = document.getElementById("run");

const localRankUrl = "../fixtures/o200k_base.tiktoken";
const remoteRankUrl = "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken";
const turbotokenWasmUrl = "../../zig-out/bin/turbotoken.wasm";
const targetBytes = 1024 * 1024;

const encoder = new TextEncoder();
const sampleBytes = (() => {
  const chunk = encoder.encode("the quick brown fox jumps over the lazy dog ");
  const repeats = Math.ceil(targetBytes / chunk.length);
  const out = new Uint8Array(repeats * chunk.length);
  for (let i = 0; i < repeats; i += 1) {
    out.set(chunk, i * chunk.length);
  }
  return out.slice(0, targetBytes);
})();
const sampleText = new TextDecoder().decode(sampleBytes);

function setLog(text) {
  logEl.textContent = text;
}

function appendLog(text) {
  if (!logEl.textContent || logEl.textContent.trim().length === 0) {
    logEl.textContent = text;
    return;
  }
  logEl.textContent = `${logEl.textContent}\n${text}`;
}

function upsertRow(name, payload) {
  const id = `row-${name}`;
  let row = document.getElementById(id);
  if (!row) {
    row = document.createElement("tr");
    row.id = id;
    row.innerHTML = `
      <td>${name}</td>
      <td class="mono startup"></td>
      <td class="mono encode"></td>
      <td class="mono throughput"></td>
      <td class="status"></td>
    `;
    rowsEl.appendChild(row);
  }
  row.querySelector(".startup").textContent = payload.startupMs == null ? "-" : payload.startupMs.toFixed(2);
  row.querySelector(".encode").textContent = payload.encodeMs == null ? "-" : payload.encodeMs.toFixed(2);
  row.querySelector(".throughput").textContent =
    payload.mibPerSec == null ? "-" : payload.mibPerSec.toFixed(2);
  const statusEl = row.querySelector(".status");
  statusEl.textContent = payload.status;
  statusEl.className = `status ${payload.status === "ok" ? "ok" : "fail"}`;
}

function bytesToMiBPerSec(bytes, ms) {
  if (!Number.isFinite(ms) || ms <= 0) {
    return null;
  }
  return (bytes / (1024 * 1024)) / (ms / 1000);
}

function meanMs(fn, warmup = 1, runs = 3) {
  for (let i = 0; i < warmup; i += 1) {
    fn();
  }
  const start = performance.now();
  for (let i = 0; i < runs; i += 1) {
    fn();
  }
  return (performance.now() - start) / runs;
}

async function benchTurbotoken() {
  const wasmBytes = new Uint8Array(await (await fetch(turbotokenWasmUrl)).arrayBuffer());
  const rankBytes = await (async () => {
    const tryLoad = async (url) => {
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`HTTP ${response.status} for ${url}`);
      }
      return new Uint8Array(await response.arrayBuffer());
    };
    try {
      return await tryLoad(localRankUrl);
    } catch (localError) {
      try {
        return await tryLoad(remoteRankUrl);
      } catch (remoteError) {
        throw new Error(`failed to load rank payload (local: ${String(localError)}; remote: ${String(remoteError)})`);
      }
    }
  })();
  const startupBegin = performance.now();
  const { instance } = await WebAssembly.instantiate(wasmBytes, {});
  const startupInstanceMs = performance.now() - startupBegin;
  const exp = instance.exports;
  if (
    typeof exp.turbotoken_wasm_alloc !== "function" ||
    typeof exp.turbotoken_wasm_free !== "function" ||
    typeof exp.turbotoken_encode_bpe_from_ranks !== "function"
  ) {
    throw new Error("required turbotoken exports missing (need full turbotoken.wasm)");
  }

  const alloc = exp.turbotoken_wasm_alloc;
  const free = exp.turbotoken_wasm_free;
  const encodeBpe = exp.turbotoken_encode_bpe_from_ranks;
  const mem = () => new Uint8Array(exp.memory.buffer);

  const runEncode = (textBytes) => {
    const rankPtr = alloc(rankBytes.length);
    const textPtr = alloc(textBytes.length);
    const outBytes = textBytes.length * 4;
    const outPtr = alloc(outBytes);
    if (rankPtr === 0 || textPtr === 0 || outPtr === 0) {
      throw new Error("alloc failed");
    }
    try {
      mem().set(rankBytes, rankPtr);
      mem().set(textBytes, textPtr);
      const written = encodeBpe(rankPtr, rankBytes.length, textPtr, textBytes.length, outPtr, textBytes.length);
      if (written < 0) {
        throw new Error("turbotoken bpe encode failed");
      }
      return written;
    } finally {
      free(outPtr, outBytes);
      free(textPtr, textBytes.length);
      free(rankPtr, rankBytes.length);
    }
  };

  // include first "hello" encode in startup metric
  const helloBytes = encoder.encode("hello");
  runEncode(helloBytes);
  const startupMs = startupInstanceMs + meanMs(() => runEncode(helloBytes), 0, 1);
  const encodeMs = meanMs(() => runEncode(sampleBytes), 1, 3);
  return {
    startupMs,
    encodeMs,
    mibPerSec: bytesToMiBPerSec(sampleBytes.length, encodeMs),
  };
}

async function benchGptTokenizer() {
  const startupBegin = performance.now();
  const mod = await import("https://esm.sh/gpt-tokenizer@3.4.0");
  mod.encode("hello");
  const startupMs = performance.now() - startupBegin;
  const encodeMs = meanMs(() => mod.encode(sampleText), 1, 3);
  return {
    startupMs,
    encodeMs,
    mibPerSec: bytesToMiBPerSec(sampleBytes.length, encodeMs),
  };
}

async function benchJsTiktoken() {
  const startupBegin = performance.now();
  const [{ Tiktoken }, ranksModule] = await Promise.all([
    import("https://esm.sh/js-tiktoken@1.0.21/lite"),
    import("https://esm.sh/js-tiktoken@1.0.21/ranks/o200k_base"),
  ]);
  const enc = new Tiktoken(ranksModule.default);
  enc.encode("hello");
  const startupMs = performance.now() - startupBegin;
  const encodeMs = meanMs(() => enc.encode(sampleText), 1, 3);
  enc.free?.();
  return {
    startupMs,
    encodeMs,
    mibPerSec: bytesToMiBPerSec(sampleBytes.length, encodeMs),
  };
}

async function benchWasmTokenizer() {
  const startupBegin = performance.now();
  const mod = await import("https://esm.sh/wasm-tokenizer@latest");
  if (typeof mod.encode !== "function") {
    throw new Error("wasm-tokenizer encode() export not found");
  }
  mod.encode("hello");
  const startupMs = performance.now() - startupBegin;
  const encodeMs = meanMs(() => mod.encode(sampleText), 1, 3);
  return {
    startupMs,
    encodeMs,
    mibPerSec: bytesToMiBPerSec(sampleBytes.length, encodeMs),
  };
}

const runners = [
  { name: "turbotoken (WASM full BPE)", fn: benchTurbotoken },
  { name: "gpt-tokenizer", fn: benchGptTokenizer },
  { name: "js-tiktoken", fn: benchJsTiktoken },
  { name: "wasm-tokenizer", fn: benchWasmTokenizer },
];

async function runAll() {
  runBtn.disabled = true;
  rowsEl.innerHTML = "";
  setLog("running...");
  const failures = [];

  for (const runner of runners) {
    upsertRow(runner.name, {
      startupMs: null,
      encodeMs: null,
      mibPerSec: null,
      status: "running",
    });
    try {
      const result = await runner.fn();
      upsertRow(runner.name, {
        ...result,
        status: "ok",
      });
    } catch (error) {
      const detail = `${runner.name} failed: ${String(error)}`;
      upsertRow(runner.name, {
        startupMs: null,
        encodeMs: null,
        mibPerSec: null,
        status: "failed",
      });
      failures.push(detail);
      appendLog(detail);
    }
  }

  if (failures.length === 0) {
    setLog("done");
  } else {
    appendLog("done with failures");
  }
  runBtn.disabled = false;
}

runBtn.addEventListener("click", () => {
  void runAll();
});
