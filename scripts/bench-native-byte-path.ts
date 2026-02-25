#!/usr/bin/env bun
import { runBench } from "./_bench";
import { ensureFixtures } from "./_fixtures";
import { pythonExecutable } from "./_lib";

ensureFixtures();
const python = pythonExecutable();
const iterations = 128;

process.exit(
  runBench({
    name: "bench-native-byte-path",
    commands: [
      {
        name: "turbotoken-native-encode-utf8-bytes-1mb-neon",
        command:
          `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;bridge=get_native_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;data=pathlib.Path('bench/fixtures/english-1mb.txt').read_bytes();out=ffi.new('uint32_t[]',len(data));iters=${iterations};written=0\nfor _ in range(iters):\n written=int(lib.turbotoken_encode_utf8_bytes(data,len(data),out,len(data)))\nassert written==len(data)"`,
      },
      {
        name: "turbotoken-native-encode-utf8-bytes-1mb-scalar",
        command:
          `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;bridge=get_native_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;data=pathlib.Path('bench/fixtures/english-1mb.txt').read_bytes();out=ffi.new('uint32_t[]',len(data));iters=${iterations};written=0\nfor _ in range(iters):\n written=int(lib.turbotoken_encode_utf8_bytes_scalar(data,len(data),out,len(data)))\nassert written==len(data)"`,
      },
      {
        name: "turbotoken-native-decode-utf8-bytes-1mb-neon",
        command:
          `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;bridge=get_native_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;raw=pathlib.Path('bench/fixtures/english-1mb.u32le.bin').read_bytes();token_len=len(raw)//4;tokens=ffi.new('uint32_t[]',token_len);ffi.memmove(tokens,raw,len(raw));out=ffi.new('unsigned char[]',token_len);iters=${iterations};written=0\nfor _ in range(iters):\n written=int(lib.turbotoken_decode_utf8_bytes(tokens,token_len,out,token_len))\nassert written==token_len"`,
      },
      {
        name: "turbotoken-native-decode-utf8-bytes-1mb-scalar",
        command:
          `${python} -c "import pathlib,sys;sys.path.insert(0,'python');from turbotoken._native import get_native_bridge;bridge=get_native_bridge();assert bridge.available,bridge.error;ffi=bridge._ffi;lib=bridge._lib;assert ffi is not None and lib is not None;raw=pathlib.Path('bench/fixtures/english-1mb.u32le.bin').read_bytes();token_len=len(raw)//4;tokens=ffi.new('uint32_t[]',token_len);ffi.memmove(tokens,raw,len(raw));out=ffi.new('unsigned char[]',token_len);iters=${iterations};written=0\nfor _ in range(iters):\n written=int(lib.turbotoken_decode_utf8_bytes_scalar(tokens,token_len,out,token_len))\nassert written==token_len"`,
      },
    ],
    metadata: {
      fixture: "bench/fixtures/english-1mb.txt",
      decodeFixture: "bench/fixtures/english-1mb.u32le.bin",
      iterationsPerSample: iterations,
      note: "native C ABI utf8 byte encode/decode path comparing ARM64 NEON vs explicit scalar exports",
    },
  }),
);
