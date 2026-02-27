"""Apple Metal GPU backend hooks (experimental byte-path acceleration)."""

from __future__ import annotations

import atexit
import bisect
import hashlib
import json
import os
import platform
import shutil
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from threading import Lock
from typing import Any, Sequence

from ._native import get_native_bridge
from ._rank_files import parse_rank_file_bytes

try:
    from cffi import FFI
except ModuleNotFoundError:  # pragma: no cover - surfaced via bridge.error
    FFI = None  # type: ignore[assignment]


def _repo_root() -> Path:
    package_dir = Path(__file__).resolve().parent
    return package_dir.parents[1]


def _bridge_source_candidates() -> list[Path | None]:
    repo_root = _repo_root()
    package_dir = Path(__file__).resolve().parent
    return [
        Path(os.environ["TURBOTOKEN_METAL_BRIDGE_SOURCE"]).expanduser()
        if "TURBOTOKEN_METAL_BRIDGE_SOURCE" in os.environ
        else None,
        repo_root / "gpu" / "metal" / "metal_bridge.m",
        package_dir / "_gpu_metal" / "metal_bridge.m",
    ]


def _cache_dir() -> Path:
    env = os.environ.get("TURBOTOKEN_METAL_CACHE_DIR")
    if env:
        return Path(env).expanduser()
    return Path.home() / ".cache" / "turbotoken" / "metal"


def _bridge_output_path(source: Path) -> Path:
    digest = hashlib.sha256(source.read_bytes()).hexdigest()[:12]
    return _cache_dir() / f"libturbotoken_metal_bridge_{digest}.dylib"


def _resolve_bridge_source() -> Path | None:
    for candidate in _bridge_source_candidates():
        if candidate is None:
            continue
        if candidate.exists():
            return candidate
    return None


def _compile_command(source: Path, output: Path) -> list[str] | None:
    xcrun = shutil.which("xcrun")
    if xcrun is not None:
        prefix = [xcrun, "clang"]
    else:
        clang = shutil.which("clang")
        if clang is None:
            return None
        prefix = [clang]

    return [
        *prefix,
        "-fobjc-arc",
        "-O3",
        "-std=c11",
        "-dynamiclib",
        str(source),
        "-framework",
        "Foundation",
        "-framework",
        "Metal",
        "-o",
        str(output),
    ]


def _ensure_compiled_bridge(source: Path) -> tuple[Path | None, str | None]:
    override = os.environ.get("TURBOTOKEN_METAL_BRIDGE_LIB")
    if override:
        candidate = Path(override).expanduser()
        if candidate.exists():
            return candidate, None
        return None, f"TURBOTOKEN_METAL_BRIDGE_LIB does not exist: {candidate}"

    output = _bridge_output_path(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        return output, None

    command = _compile_command(source, output)
    if command is None:
        return None, "clang toolchain not found (need xcrun or clang)"

    try:
        proc = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as exc:
        return None, f"failed to launch clang for Metal bridge build: {exc}"

    if proc.returncode != 0:
        stderr = proc.stderr.strip()
        stdout = proc.stdout.strip()
        detail = stderr or stdout or f"exit code {proc.returncode}"
        return None, f"Metal bridge build failed: {detail}"

    if not output.exists():
        return None, "Metal bridge build reported success but output dylib is missing"
    return output, None


def _flatten_batch(batch: Sequence[bytes]) -> tuple[bytes, list[int]]:
    merged = bytearray()
    offsets = [0]
    for item in batch:
        if isinstance(item, memoryview):
            payload = item.tobytes()
        elif isinstance(item, (bytes, bytearray)):
            payload = item
        else:
            raise TypeError("batch items must be bytes-like")
        merged.extend(payload)
        offsets.append(len(merged))
    return bytes(merged), offsets


def _route_cache_path() -> Path:
    return _cache_dir() / "autoroute-v1.json"


def _load_route_cache() -> dict[str, Any] | None:
    path = _route_cache_path()
    if not path.exists():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(payload, dict):
        return None
    return payload


def _write_route_cache(payload: dict[str, Any]) -> None:
    path = _route_cache_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _bench_mean_ms(fn: Any, loops: int) -> float:
    start = time.perf_counter()
    for _ in range(loops):
        fn()
    elapsed_s = time.perf_counter() - start
    return (elapsed_s * 1000.0) / max(1, loops)


_rank_token_len_cache: dict[str, dict[int, int]] = {}
_metal_stitch_support_cache: dict[tuple[str, int, int, int], bool] = {}
_metal_bpe_rank_table_ready: dict[str, bool] = {}
_hybrid_pool: ThreadPoolExecutor | None = None
_hybrid_pool_lock = Lock()


def _env_int(name: str, default: int, *, minimum: int = 1) -> int:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        value = int(raw, 10)
    except ValueError:
        return default
    return max(minimum, value)


def _unpack_u32(ffi: Any, out: Any, written: int) -> list[int]:
    if written <= 0:
        return []
    try:
        return list(ffi.unpack(out, written))
    except AttributeError:
        return [int(out[idx]) for idx in range(written)]


def _shutdown_hybrid_pool() -> None:
    global _hybrid_pool
    with _hybrid_pool_lock:
        pool = _hybrid_pool
        _hybrid_pool = None
    if pool is not None:
        pool.shutdown(wait=False)


def _get_hybrid_pool() -> ThreadPoolExecutor:
    global _hybrid_pool
    with _hybrid_pool_lock:
        if _hybrid_pool is None:
            _hybrid_pool = ThreadPoolExecutor(
                max_workers=2,
                thread_name_prefix="turbotoken-hybrid",
            )
            atexit.register(_shutdown_hybrid_pool)
        return _hybrid_pool


def _rank_token_lens_from_payload(rank_payload: bytes) -> dict[int, int]:
    digest = hashlib.sha256(rank_payload).hexdigest()
    cached = _rank_token_len_cache.get(digest)
    if cached is not None:
        return cached

    mergeable = parse_rank_file_bytes(rank_payload)
    token_lens = {token_id: len(token_bytes) for token_bytes, token_id in mergeable.items()}
    _rank_token_len_cache[digest] = token_lens
    if len(_rank_token_len_cache) > 8:
        # Keep this tiny cache bounded; latest entries are enough for typical usage.
        oldest = next(iter(_rank_token_len_cache))
        del _rank_token_len_cache[oldest]
    return token_lens


def _fnv1a_pair(left: int, right: int) -> int:
    h = 2166136261
    h = ((h ^ left) * 16777619) & 0xFFFFFFFF
    h = ((h ^ right) * 16777619) & 0xFFFFFFFF
    return h


def _build_metal_pair_hash_table(
    rank_payload: bytes,
) -> tuple[list[int], list[int]] | None:
    mergeable = parse_rank_file_bytes(rank_payload)
    byte_tokens: list[int] = []
    for value in range(256):
        token = mergeable.get(bytes([value]))
        if token is None:
            return None
        byte_tokens.append(token)

    pair_to_merge: dict[tuple[int, int], tuple[int, int]] = {}
    for merged_bytes, merged_token in mergeable.items():
        if len(merged_bytes) < 2:
            continue
        for split in range(1, len(merged_bytes)):
            left_token = mergeable.get(merged_bytes[:split])
            right_token = mergeable.get(merged_bytes[split:])
            if left_token is None or right_token is None:
                continue
            key = (left_token, right_token)
            existing = pair_to_merge.get(key)
            if existing is None or merged_token < existing[0]:
                # merge_rank and merged_token are the same id in rank files.
                pair_to_merge[key] = (merged_token, merged_token)

    if not pair_to_merge:
        return None

    table_size = 1024
    while table_size < (len(pair_to_merge) * 2):
        table_size <<= 1

    empty = 0xFFFFFFFF
    entries: list[list[int]] = [[empty, empty, empty, empty] for _ in range(table_size)]
    mask = table_size - 1
    for (left_token, right_token), (merge_rank, merged_token) in pair_to_merge.items():
        slot = _fnv1a_pair(left_token, right_token) & mask
        for _ in range(64):
            row = entries[slot]
            if row[2] == empty:
                entries[slot] = [left_token, right_token, merge_rank, merged_token]
                break
            if row[0] == left_token and row[1] == right_token:
                if merge_rank < row[2]:
                    entries[slot] = [left_token, right_token, merge_rank, merged_token]
                break
            slot = (slot + 1) & mask
        else:
            return None

    flattened: list[int] = []
    for row in entries:
        flattened.extend(row)
    return flattened, byte_tokens


def _ensure_metal_bpe_rank_table(rank_payload: bytes) -> bool:
    digest = hashlib.sha256(rank_payload).hexdigest()
    if _metal_bpe_rank_table_ready.get(digest) is True:
        return True

    bridge = get_metal_bridge()
    if not bridge.available:
        return False

    built = _build_metal_pair_hash_table(rank_payload)
    if built is None:
        _metal_bpe_rank_table_ready[digest] = False
        return False
    table_entries, byte_tokens = built
    if not bridge.set_bpe_rank_table(table_entries):
        _metal_bpe_rank_table_ready[digest] = False
        return False
    if not bridge.set_bpe_byte_token_map(byte_tokens):
        _metal_bpe_rank_table_ready[digest] = False
        return False

    _metal_bpe_rank_table_ready[digest] = True
    if len(_metal_bpe_rank_table_ready) > 4:
        oldest = next(iter(_metal_bpe_rank_table_ready))
        del _metal_bpe_rank_table_ready[oldest]
    return True


@dataclass(slots=True)
class MetalBridge:
    _lib: Any | None = None
    _ffi: Any | None = None
    _error: str | None = None
    _library_path: Path | None = None
    _available: bool = False
    _loaded: bool = False

    def load(self) -> None:
        if self._loaded:
            return
        self._loaded = True

        if platform.system() != "Darwin":
            self._error = "Metal backend is only supported on macOS"
            return

        if FFI is None:
            self._error = "cffi is not installed"
            return

        source = _resolve_bridge_source()
        if source is None:
            self._error = "Metal bridge source not found (expected gpu/metal/metal_bridge.m)"
            return

        library_path, build_error = _ensure_compiled_bridge(source)
        if build_error is not None or library_path is None:
            self._error = build_error
            return

        ffi = FFI()
        ffi.cdef(
            """
            const char *turbotoken_metal_version(void);
            const char *turbotoken_metal_last_error(void);
            int turbotoken_metal_available(void);
            long turbotoken_metal_encode_utf8_bytes(
                const unsigned char *input,
                size_t input_len,
                uint32_t *out_tokens,
                size_t out_cap
            );
            long turbotoken_metal_encode_utf8_bytes_hybrid(
                const unsigned char *input,
                size_t input_len,
                size_t split_index,
                uint32_t *out_tokens,
                size_t out_cap
            );
            long turbotoken_metal_count_nonzero_segments(
                const unsigned char *input,
                size_t input_len,
                const uint32_t *offsets,
                size_t offsets_len,
                uint32_t *out_counts,
                size_t out_cap
            );
            long turbotoken_metal_count_nonzero_bytes(
                const unsigned char *input,
                size_t input_len
            );
            long turbotoken_metal_chunk_owner_flags(
                const uint32_t *token_starts,
                const uint32_t *source_chunks,
                size_t token_len,
                uint32_t chunk_bytes,
                uint32_t num_chunks,
                uint32_t *out_flags,
                size_t out_cap
            );
            long turbotoken_metal_bpe_set_rank_table(
                const uint32_t *entries_u32,
                size_t entry_u32_len
            );
            long turbotoken_metal_bpe_set_byte_token_map(
                const uint32_t *byte_tokens,
                size_t byte_tokens_len
            );
            long turbotoken_metal_bpe_encode_from_bytes(
                const unsigned char *input,
                size_t input_len,
                uint32_t *out_tokens,
                size_t out_cap
            );
            uint64_t turbotoken_metal_last_encode_cpu_ns(void);
            uint64_t turbotoken_metal_last_encode_gpu_ns(void);
            uint64_t turbotoken_metal_last_encode_bytes(void);
            uint64_t turbotoken_metal_last_encode_dispatch_threads(void);
            uint64_t turbotoken_metal_last_count_cpu_ns(void);
            uint64_t turbotoken_metal_last_count_gpu_ns(void);
            uint64_t turbotoken_metal_last_count_bytes(void);
            uint64_t turbotoken_metal_last_count_segments(void);
            uint64_t turbotoken_metal_last_count_lanes(void);
            uint64_t turbotoken_metal_last_stitch_cpu_ns(void);
            uint64_t turbotoken_metal_last_stitch_gpu_ns(void);
            uint64_t turbotoken_metal_last_stitch_tokens(void);
            uint64_t turbotoken_metal_last_stitch_chunk_bytes(void);
            uint64_t turbotoken_metal_last_stitch_num_chunks(void);
            uint64_t turbotoken_metal_last_bpe_cpu_ns(void);
            uint64_t turbotoken_metal_last_bpe_gpu_ns(void);
            uint64_t turbotoken_metal_last_bpe_rounds(void);
            uint64_t turbotoken_metal_last_bpe_input_bytes(void);
            uint64_t turbotoken_metal_last_bpe_output_tokens(void);
            uint64_t turbotoken_metal_last_memory_active_bytes(void);
            uint64_t turbotoken_metal_last_memory_working_set_bytes(void);
            uint64_t turbotoken_metal_last_memory_device_allocated_bytes(void);
            uint64_t turbotoken_metal_last_memory_device_recommended_working_set_bytes(void);
            """
        )

        try:
            lib = ffi.dlopen(str(library_path))
        except OSError as exc:
            self._error = f"failed to load Metal bridge dylib {library_path}: {exc}"
            return

        self._ffi = ffi
        self._lib = lib
        self._library_path = library_path

        is_available = int(lib.turbotoken_metal_available())
        if is_available == 0:
            raw = lib.turbotoken_metal_last_error()
            if raw == ffi.NULL:
                self._error = "Metal backend initialization failed"
            else:
                self._error = ffi.string(raw).decode("utf-8", errors="replace")
            return

        self._available = True
        self._error = None

    @property
    def available(self) -> bool:
        self.load()
        return self._available

    @property
    def error(self) -> str | None:
        self.load()
        return self._error

    @property
    def library_path(self) -> Path | None:
        self.load()
        return self._library_path

    def version(self) -> str | None:
        self.load()
        if not self._available or self._lib is None or self._ffi is None:
            return None

        raw = self._lib.turbotoken_metal_version()
        if raw == self._ffi.NULL:
            return None
        return self._ffi.string(raw).decode("utf-8", errors="replace")

    def encode_utf8_bytes(self, data: bytes) -> list[int] | None:
        self.load()
        if not self._available or self._lib is None or self._ffi is None:
            return None
        if not data:
            return []

        in_buf = self._ffi.from_buffer("const unsigned char[]", data)
        needed = int(self._lib.turbotoken_metal_encode_utf8_bytes(in_buf, len(data), self._ffi.NULL, 0))
        if needed < 0:
            return None
        if needed == 0:
            return []

        out = self._ffi.new("uint32_t[]", needed)
        written = int(self._lib.turbotoken_metal_encode_utf8_bytes(in_buf, len(data), out, needed))
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def encode_utf8_bytes_hybrid(self, data: bytes, split_index: int) -> list[int] | None:
        self.load()
        if not self._available or self._lib is None or self._ffi is None:
            return None
        if not data:
            return []
        if split_index <= 0 or split_index >= len(data):
            return None

        in_buf = self._ffi.from_buffer("const unsigned char[]", data)
        needed = int(
            self._lib.turbotoken_metal_encode_utf8_bytes_hybrid(
                in_buf,
                len(data),
                split_index,
                self._ffi.NULL,
                0,
            )
        )
        if needed < 0:
            return None
        if needed == 0:
            return []

        out = self._ffi.new("uint32_t[]", needed)
        written = int(
            self._lib.turbotoken_metal_encode_utf8_bytes_hybrid(
                in_buf,
                len(data),
                split_index,
                out,
                needed,
            )
        )
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def encode_utf8_bytes_batch(self, batch: Sequence[bytes]) -> list[list[int]] | None:
        self.load()
        if not self._available:
            return None
        if len(batch) == 0:
            return []

        merged, offsets = _flatten_batch(batch)
        flat_tokens = self.encode_utf8_bytes(merged)
        if flat_tokens is None:
            return None

        out: list[list[int]] = []
        for idx in range(len(batch)):
            start = offsets[idx]
            end = offsets[idx + 1]
            out.append(flat_tokens[start:end])
        return out

    def count_nonzero_bytes(self, data: bytes) -> int | None:
        self.load()
        if not self._available or self._lib is None or self._ffi is None:
            return None
        if not data:
            return 0

        in_buf = self._ffi.from_buffer("const unsigned char[]", data)
        count = int(self._lib.turbotoken_metal_count_nonzero_bytes(in_buf, len(data)))
        if count < 0:
            return None
        return count

    def count_nonzero_bytes_batch(self, batch: Sequence[bytes]) -> list[int] | None:
        self.load()
        if not self._available or self._lib is None or self._ffi is None:
            return None
        if len(batch) == 0:
            return []

        merged, offsets = _flatten_batch(batch)
        merged_buf = self._ffi.from_buffer("const unsigned char[]", merged)
        offsets_buf = self._ffi.new("uint32_t[]", offsets)

        needed = int(
            self._lib.turbotoken_metal_count_nonzero_segments(
                merged_buf,
                len(merged),
                offsets_buf,
                len(offsets),
                self._ffi.NULL,
                0,
            )
        )
        if needed < 0:
            return None
        if needed == 0:
            return []

        out = self._ffi.new("uint32_t[]", needed)
        written = int(
            self._lib.turbotoken_metal_count_nonzero_segments(
                merged_buf,
                len(merged),
                offsets_buf,
                len(offsets),
                out,
                needed,
            )
        )
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def chunk_owner_flags(
        self,
        token_starts: Sequence[int],
        source_chunks: Sequence[int],
        *,
        chunk_bytes: int,
        num_chunks: int,
    ) -> list[int] | None:
        self.load()
        if not self._available or self._lib is None or self._ffi is None:
            return None
        if len(token_starts) != len(source_chunks):
            return None
        if chunk_bytes <= 0 or num_chunks <= 0:
            return None
        if len(token_starts) == 0:
            return []

        try:
            starts_buf = self._ffi.new("uint32_t[]", list(token_starts))
            chunks_buf = self._ffi.new("uint32_t[]", list(source_chunks))
        except (OverflowError, TypeError):
            return None

        needed = int(
            self._lib.turbotoken_metal_chunk_owner_flags(
                starts_buf,
                chunks_buf,
                len(token_starts),
                chunk_bytes,
                num_chunks,
                self._ffi.NULL,
                0,
            )
        )
        if needed < 0:
            return None
        if needed == 0:
            return []

        out = self._ffi.new("uint32_t[]", needed)
        written = int(
            self._lib.turbotoken_metal_chunk_owner_flags(
                starts_buf,
                chunks_buf,
                len(token_starts),
                chunk_bytes,
                num_chunks,
                out,
                needed,
            )
        )
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def set_bpe_rank_table(self, entries_u32: Sequence[int]) -> bool:
        self.load()
        if not self._available or self._lib is None or self._ffi is None:
            return False
        if len(entries_u32) == 0:
            return False
        try:
            table_buf = self._ffi.new("uint32_t[]", list(entries_u32))
            written = int(
                self._lib.turbotoken_metal_bpe_set_rank_table(
                    table_buf,
                    len(entries_u32),
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return False
        return written > 0

    def set_bpe_byte_token_map(self, byte_tokens: Sequence[int]) -> bool:
        self.load()
        if not self._available or self._lib is None or self._ffi is None:
            return False
        if len(byte_tokens) != 256:
            return False
        try:
            byte_buf = self._ffi.new("uint32_t[]", list(byte_tokens))
            written = int(
                self._lib.turbotoken_metal_bpe_set_byte_token_map(
                    byte_buf,
                    len(byte_tokens),
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return False
        return written == 256

    def encode_bpe_from_bytes(self, data: bytes) -> list[int] | None:
        self.load()
        if not self._available or self._lib is None or self._ffi is None:
            return None
        if not data:
            return []

        in_buf = self._ffi.from_buffer("const unsigned char[]", data)
        needed = int(
            self._lib.turbotoken_metal_bpe_encode_from_bytes(
                in_buf,
                len(data),
                self._ffi.NULL,
                0,
            )
        )
        if needed < 0:
            return None
        if needed == 0:
            return []

        out = self._ffi.new("uint32_t[]", needed)
        written = int(
            self._lib.turbotoken_metal_bpe_encode_from_bytes(
                in_buf,
                len(data),
                out,
                needed,
            )
        )
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def last_profile(self) -> dict[str, int] | None:
        self.load()
        if not self._available or self._lib is None:
            return None

        try:
            return {
                "encode_cpu_ns": int(self._lib.turbotoken_metal_last_encode_cpu_ns()),
                "encode_gpu_ns": int(self._lib.turbotoken_metal_last_encode_gpu_ns()),
                "encode_bytes": int(self._lib.turbotoken_metal_last_encode_bytes()),
                "encode_dispatch_threads": int(self._lib.turbotoken_metal_last_encode_dispatch_threads()),
                "count_cpu_ns": int(self._lib.turbotoken_metal_last_count_cpu_ns()),
                "count_gpu_ns": int(self._lib.turbotoken_metal_last_count_gpu_ns()),
                "count_bytes": int(self._lib.turbotoken_metal_last_count_bytes()),
                "count_segments": int(self._lib.turbotoken_metal_last_count_segments()),
                "count_lanes": int(self._lib.turbotoken_metal_last_count_lanes()),
                "stitch_cpu_ns": int(self._lib.turbotoken_metal_last_stitch_cpu_ns()),
                "stitch_gpu_ns": int(self._lib.turbotoken_metal_last_stitch_gpu_ns()),
                "stitch_tokens": int(self._lib.turbotoken_metal_last_stitch_tokens()),
                "stitch_chunk_bytes": int(self._lib.turbotoken_metal_last_stitch_chunk_bytes()),
                "stitch_num_chunks": int(self._lib.turbotoken_metal_last_stitch_num_chunks()),
                "bpe_cpu_ns": int(self._lib.turbotoken_metal_last_bpe_cpu_ns()),
                "bpe_gpu_ns": int(self._lib.turbotoken_metal_last_bpe_gpu_ns()),
                "bpe_rounds": int(self._lib.turbotoken_metal_last_bpe_rounds()),
                "bpe_input_bytes": int(self._lib.turbotoken_metal_last_bpe_input_bytes()),
                "bpe_output_tokens": int(self._lib.turbotoken_metal_last_bpe_output_tokens()),
                "memory_active_bytes": int(self._lib.turbotoken_metal_last_memory_active_bytes()),
                "memory_working_set_bytes": int(self._lib.turbotoken_metal_last_memory_working_set_bytes()),
                "memory_device_allocated_bytes": int(self._lib.turbotoken_metal_last_memory_device_allocated_bytes()),
                "memory_device_recommended_working_set_bytes": int(
                    self._lib.turbotoken_metal_last_memory_device_recommended_working_set_bytes(),
                ),
            }
        except (AttributeError, TypeError):
            return None


@lru_cache(maxsize=1)
def get_metal_bridge() -> MetalBridge:
    return MetalBridge()


def backend_info() -> dict[str, Any]:
    bridge = get_metal_bridge()
    profile = bridge.last_profile()
    route_cache = _load_route_cache()
    return {
        "available": bridge.available,
        "version": bridge.version(),
        "error": bridge.error,
        "library_path": str(bridge.library_path) if bridge.library_path is not None else None,
        "last_profile": profile,
        "autoroute": route_cache,
        "note": "Experimental Metal backend focuses on large-piece BPE crossover workloads. Small/medium pieces stay on CPU/native by default unless forced. BPE chunked stitch remains experimental with exactness guards; last_profile includes per-op GPU memory telemetry fields.",
    }


def available() -> bool:
    return get_metal_bridge().available


def encode_utf8_bytes(data: bytes) -> list[int] | None:
    return get_metal_bridge().encode_utf8_bytes(data)


def encode_utf8_bytes_hybrid(
    data: bytes,
    *,
    split_ratio: float = 0.5,
    min_bytes: int = 1_048_576,
) -> list[int] | None:
    """Experimental split execution: native CPU + Metal GPU in parallel.

    This only applies to the UTF-8 byte-path (u8 -> u32 identity mapping), so
    concatenating split results is exact.
    """

    if not data:
        return []

    bridge = get_metal_bridge()
    native = get_native_bridge()
    if not bridge.available or not native.available:
        return None
    if len(data) < max(2, min_bytes):
        return None

    bounded_ratio = min(0.9, max(0.1, split_ratio))
    split = int(len(data) * bounded_ratio)
    split = min(len(data) - 1, max(1, split))
    bridge_result = bridge.encode_utf8_bytes_hybrid(data, split)
    if bridge_result is not None:
        return bridge_result
    if native._ffi is None or native._lib is None or bridge._ffi is None or bridge._lib is None:
        return None

    payload_view = memoryview(data)
    left_view = payload_view[:split]
    right_view = payload_view[split:]
    left_len = len(left_view)
    right_len = len(right_view)

    nffi = native._ffi
    nlib = native._lib
    gffi = bridge._ffi
    glib = bridge._lib

    left_in = nffi.from_buffer("const char[]", left_view)
    right_in = gffi.from_buffer("const unsigned char[]", right_view)
    left_out = nffi.new("uint32_t[]", left_len)
    right_out = gffi.new("uint32_t[]", right_len)

    pool = _get_hybrid_pool()
    left_future = pool.submit(
        nlib.turbotoken_encode_utf8_bytes,
        left_in,
        left_len,
        left_out,
        left_len,
    )
    right_future = pool.submit(
        glib.turbotoken_metal_encode_utf8_bytes,
        right_in,
        right_len,
        right_out,
        right_len,
    )

    written_left = int(left_future.result())
    written_right = int(right_future.result())
    if written_left < 0 or written_right < 0:
        return None

    left_tokens = _unpack_u32(nffi, left_out, written_left)
    left_tokens.extend(_unpack_u32(gffi, right_out, written_right))
    return left_tokens


def encode_utf8_bytes_batch(batch: Sequence[bytes]) -> list[list[int]] | None:
    return get_metal_bridge().encode_utf8_bytes_batch(batch)


def count_nonzero_bytes(data: bytes) -> int | None:
    return get_metal_bridge().count_nonzero_bytes(data)


def count_nonzero_bytes_batch(batch: Sequence[bytes]) -> list[int] | None:
    return get_metal_bridge().count_nonzero_bytes_batch(batch)


def profile_last() -> dict[str, int] | None:
    return get_metal_bridge().last_profile()


def calibrate_autoroute(*, force: bool = False) -> dict[str, Any]:
    existing = _load_route_cache()
    if existing is not None and not force and int(existing.get("version", 0)) >= 5:
        return existing

    bridge = get_metal_bridge()
    native = get_native_bridge()

    payload: dict[str, Any] = {
        "version": 5,
        "generated_at": time.time(),
        "encode_use_metal_min_bytes": 1 << 60,
        "count_batch_use_metal_min_total_bytes": 1 << 60,
        "bpe_use_metal_min_piece_bytes": 1 << 60,
        "encode_rows": [],
        "count_rows": [],
        "bpe_rows": [],
    }

    if not bridge.available:
        payload["reason"] = bridge.error or "metal unavailable"
        _write_route_cache(payload)
        return payload

    # Encode crossover: compare Metal and native byte encode on increasing payload sizes.
    encode_sizes = [4_096, 16_384, 65_536, 262_144, 1_048_576]
    sample = bytes(((idx % 251) + 1) for idx in range(max(encode_sizes)))
    first_metal_win: int | None = None
    for size in encode_sizes:
        loops = max(8, min(256, (16 * 1_048_576) // size))
        chunk = sample[:size]
        metal_ms = _bench_mean_ms(lambda: bridge.encode_utf8_bytes(chunk), loops)

        native_ms: float | None = None
        if native.available:
            native_ms = _bench_mean_ms(lambda: native.encode_utf8_bytes(chunk), loops)
            if native_ms > 0 and metal_ms < native_ms * 0.95 and first_metal_win is None:
                first_metal_win = size

        payload["encode_rows"].append(
            {
                "bytes": size,
                "loops": loops,
                "metal_mean_ms": metal_ms,
                "native_mean_ms": native_ms,
            }
        )

    if first_metal_win is not None:
        payload["encode_use_metal_min_bytes"] = first_metal_win
    elif native.available:
        payload["encode_use_metal_min_bytes"] = 1 << 60
    else:
        payload["encode_use_metal_min_bytes"] = 0

    # Count crossover: compare Metal batch counter with Python baseline on total bytes.
    count_batches = [256, 1024, 4096, 8192]
    segment = b"a" * 1024
    first_count_win: int | None = None
    for batch_size in count_batches:
        loops = max(8, min(256, (16 * 8192) // batch_size))
        payloads = [segment] * batch_size
        total_bytes = batch_size * len(segment)
        metal_ms = _bench_mean_ms(lambda: bridge.count_nonzero_bytes_batch(payloads), loops)
        python_ms = _bench_mean_ms(
            lambda: [len(item) - item.count(0) for item in payloads],
            loops,
        )
        if python_ms > 0 and metal_ms < python_ms * 0.9 and first_count_win is None:
            first_count_win = total_bytes

        payload["count_rows"].append(
            {
                "batch": batch_size,
                "segment_bytes": len(segment),
                "total_bytes": total_bytes,
                "loops": loops,
                "metal_mean_ms": metal_ms,
                "python_mean_ms": python_ms,
            }
        )

    if first_count_win is not None:
        payload["count_batch_use_metal_min_total_bytes"] = first_count_win

    # BPE crossover: compare exact native baseline with experimental metal stitch path.
    try:
        from .core import get_encoding
    except Exception as exc:  # pragma: no cover - defensive import guard
        payload["bpe_reason"] = f"failed to import core encoding API: {exc}"
        _write_route_cache(payload)
        return payload

    try:
        enc = get_encoding("o200k_base")
        enc.load_mergeable_ranks()
        rank_payload = enc._rank_payload_cache
        if not rank_payload:
            rank_payload = enc._ensure_rank_payload()
    except Exception as exc:
        payload["bpe_reason"] = f"failed to load o200k_base ranks: {exc}"
        _write_route_cache(payload)
        return payload

    if not rank_payload:
        payload["bpe_reason"] = "o200k_base rank payload unavailable"
        _write_route_cache(payload)
        return payload

    bpe_sizes = [65_536, 262_144, 1_048_576]
    first_bpe_win: int | None = None
    for size in bpe_sizes:
        loops = max(2, min(8, (2 * 1_048_576) // size))
        piece = b"a" * size
        text = "a" * size

        baseline_tokens: list[int] | None = None
        baseline_backend = "native"
        if native.available:
            baseline_tokens = native.encode_bpe_from_ranks(rank_payload, piece)
        if baseline_tokens is None:
            baseline_backend = "python"
            baseline_tokens = enc.encode(text)

        metal_tokens = encode_bpe_chunked_stitched(
            rank_payload,
            piece,
            chunk_bytes=4096,
            overlap_bytes=512,
            strict_verify=False,
            prefer_metal_stitch=True,
        )
        metal_matches = metal_tokens == baseline_tokens if baseline_tokens is not None else False

        if baseline_backend == "native":
            baseline_ms = _bench_mean_ms(
                lambda: native.encode_bpe_from_ranks(rank_payload, piece),
                loops,
            )
        else:
            baseline_ms = _bench_mean_ms(lambda: enc.encode(text), loops)

        metal_ms = _bench_mean_ms(
            lambda: encode_bpe_chunked_stitched(
                rank_payload,
                piece,
                chunk_bytes=4096,
                overlap_bytes=512,
                strict_verify=False,
                prefer_metal_stitch=True,
            ),
            loops,
        )

        if (
            metal_matches
            and baseline_ms > 0
            and metal_ms < baseline_ms * 0.95
            and first_bpe_win is None
        ):
            first_bpe_win = size

        payload["bpe_rows"].append(
            {
                "bytes": size,
                "loops": loops,
                "baseline_backend": baseline_backend,
                "baseline_mean_ms": baseline_ms,
                "metal_mean_ms": metal_ms,
                "metal_matches_baseline": metal_matches,
                "baseline_tokens_len": len(baseline_tokens) if baseline_tokens is not None else None,
                "metal_tokens_len": len(metal_tokens) if metal_tokens is not None else None,
            }
        )

    if first_bpe_win is not None:
        payload["bpe_use_metal_min_piece_bytes"] = first_bpe_win

    _write_route_cache(payload)
    return payload


def _get_route_thresholds() -> tuple[int, int, int]:
    if os.environ.get("TURBOTOKEN_METAL_AUTOROUTE_DISABLE", "").strip().lower() in {"1", "true", "yes"}:
        return 1 << 60, 1 << 60, 1 << 60

    cached = _load_route_cache()
    if cached is None or int(cached.get("version", 0)) < 5:
        cached = calibrate_autoroute(force=True)

    encode_threshold = int(cached.get("encode_use_metal_min_bytes", 1 << 60))
    count_threshold = int(cached.get("count_batch_use_metal_min_total_bytes", 1 << 60))
    bpe_threshold = int(cached.get("bpe_use_metal_min_piece_bytes", 1 << 60))

    # Default policy keeps Metal routes focused on large crossover workloads.
    encode_floor = _env_int("TURBOTOKEN_METAL_ENCODE_MIN_BYTES", 1 << 60, minimum=1)
    count_floor = _env_int("TURBOTOKEN_METAL_COUNT_MIN_TOTAL_BYTES", 1 << 60, minimum=1)
    bpe_floor = _env_int("TURBOTOKEN_METAL_BPE_MIN_BYTES", 1_048_576, minimum=1)

    encode_threshold = max(encode_threshold, encode_floor)
    count_threshold = max(count_threshold, count_floor)
    bpe_threshold = max(bpe_threshold, bpe_floor)
    return encode_threshold, count_threshold, bpe_threshold


def encode_utf8_bytes_auto(data: bytes) -> tuple[list[int] | None, str]:
    bridge = get_metal_bridge()
    native = get_native_bridge()
    encode_threshold, _, _ = _get_route_thresholds()

    if not data:
        return [], "none"

    hybrid_enabled = os.environ.get("TURBOTOKEN_METAL_HYBRID_ENABLE", "").strip().lower() in {
        "1",
        "true",
        "yes",
    }
    if hybrid_enabled:
        split_ratio_raw = os.environ.get("TURBOTOKEN_METAL_HYBRID_SPLIT", "").strip()
        min_bytes_raw = os.environ.get("TURBOTOKEN_METAL_HYBRID_MIN_BYTES", "").strip()
        try:
            split_ratio = float(split_ratio_raw) if split_ratio_raw else 0.5
        except ValueError:
            split_ratio = 0.5
        try:
            min_bytes = int(min_bytes_raw) if min_bytes_raw else 1_048_576
        except ValueError:
            min_bytes = 1_048_576
        hybrid = encode_utf8_bytes_hybrid(
            data,
            split_ratio=split_ratio,
            min_bytes=max(2, min_bytes),
        )
        if hybrid is not None:
            return hybrid, "hybrid"

    if bridge.available and len(data) >= encode_threshold:
        out = bridge.encode_utf8_bytes(data)
        if out is not None:
            return out, "metal"

    if native.available:
        out = native.encode_utf8_bytes(data)
        if out is not None:
            return out, "native"

    if bridge.available:
        return bridge.encode_utf8_bytes(data), "metal-fallback"

    return None, "unavailable"


def count_nonzero_bytes_batch_auto(batch: Sequence[bytes]) -> tuple[list[int] | None, str]:
    bridge = get_metal_bridge()
    _, count_threshold, _ = _get_route_thresholds()

    if len(batch) == 0:
        return [], "none"

    total_bytes = 0
    for item in batch:
        total_bytes += len(item)

    if bridge.available and total_bytes >= count_threshold:
        out = bridge.count_nonzero_bytes_batch(batch)
        if out is not None:
            return out, "metal"

    # CPU fallback baseline in pure Python for environments without native count symbol.
    cpu = [len(item) - item.count(0) for item in batch]
    return cpu, "python"


def bpe_route_backend(piece_len_bytes: int) -> str:
    if piece_len_bytes <= 0:
        return "none"
    if os.environ.get("TURBOTOKEN_METAL_FORCE_ALL_PIECES", "").strip().lower() in {"1", "true", "yes"}:
        return "metal"
    if os.environ.get("TURBOTOKEN_METAL_AUTOROUTE_DISABLE", "").strip().lower() in {"1", "true", "yes"}:
        return "native"

    bridge = get_metal_bridge()
    if not bridge.available:
        return "native"

    _, _, bpe_threshold = _get_route_thresholds()
    if piece_len_bytes >= bpe_threshold:
        return "metal"
    return "native"


def _stitch_chunk_tokens(
    *,
    stitched: list[int],
    chunk_idx: int,
    num_chunks: int,
    chunk_bytes: int,
    ext_start: int,
    ext_end: int,
    tokens: Sequence[int],
    token_lens: dict[int, int],
) -> bool:
    cursor = 0
    ext_len = ext_end - ext_start
    for token in tokens:
        token_len = token_lens.get(token)
        if token_len is None:
            return False
        next_cursor = cursor + token_len
        if next_cursor > ext_len:
            return False

        global_start = ext_start + cursor
        owner = min(global_start // chunk_bytes, num_chunks - 1)
        if owner == chunk_idx:
            stitched.append(token)
        cursor = next_cursor

    return cursor == ext_len


def _encode_bpe_chunked_stitched_scalar(
    bridge: Any,
    rank_payload: bytes,
    data: bytes,
    *,
    chunk_bytes: int,
    overlap_bytes: int,
    num_chunks: int,
    token_lens: dict[int, int],
) -> list[int] | None:
    stitched: list[int] = []
    for chunk_idx in range(num_chunks):
        start = chunk_idx * chunk_bytes
        end = min(len(data), start + chunk_bytes)
        ext_start = max(0, start - overlap_bytes)
        ext_end = min(len(data), end + overlap_bytes)

        ext_tokens = bridge.encode_bpe_from_ranks(rank_payload, data[ext_start:ext_end])
        if ext_tokens is None:
            return None
        if not _stitch_chunk_tokens(
            stitched=stitched,
            chunk_idx=chunk_idx,
            num_chunks=num_chunks,
            chunk_bytes=chunk_bytes,
            ext_start=ext_start,
            ext_end=ext_end,
            tokens=ext_tokens,
            token_lens=token_lens,
        ):
            return None

    return stitched


def _encode_bpe_chunked_stitched_metal(
    rank_payload: bytes,
    data: bytes,
    *,
    chunk_bytes: int,
    overlap_bytes: int,
) -> list[int] | None:
    native_bridge = get_native_bridge()
    metal_bridge = get_metal_bridge()
    if not native_bridge.available or not metal_bridge.available:
        return None

    token_lens = _rank_token_lens_from_payload(rank_payload)
    full_piece_max_bytes = int(
        os.environ.get("TURBOTOKEN_METAL_BPE_FULL_MAX_BYTES", "16384")
    )
    if len(data) <= full_piece_max_bytes and _ensure_metal_bpe_rank_table(rank_payload):
        gpu_tokens = metal_bridge.encode_bpe_from_bytes(data)
        if gpu_tokens is not None:
            total_bytes = _token_total_bytes(gpu_tokens, token_lens)
            if total_bytes == len(data):
                return gpu_tokens

    num_chunks = (len(data) + chunk_bytes - 1) // chunk_bytes
    chunk_ranges: list[tuple[int, int]] = []
    for chunk_idx in range(num_chunks):
        start = chunk_idx * chunk_bytes
        end = min(len(data), start + chunk_bytes)
        ext_start = max(0, start - overlap_bytes)
        ext_end = min(len(data), end + overlap_bytes)
        chunk_ranges.append((ext_start, ext_end))

    ext_bytes_per_chunk = max(1, chunk_bytes + (2 * overlap_bytes))
    chunks_per_batch = max(1, min(512, (8 * 1024 * 1024) // ext_bytes_per_chunk))

    stitched: list[int] = []
    for batch_start in range(0, num_chunks, chunks_per_batch):
        batch_end = min(num_chunks, batch_start + chunks_per_batch)
        window_ranges = chunk_ranges[batch_start:batch_end]
        batch = native_bridge.encode_bpe_ranges_from_ranks(rank_payload, data, window_ranges)
        if batch is None:
            return None

        flat_tokens, token_offsets = batch
        if len(token_offsets) != len(window_ranges) + 1:
            return None

        window_starts = [start for start, _ in window_ranges]
        window_ends = [end for _, end in window_ranges]
        layout = native_bridge.bpe_ranges_token_layout_from_ranks(
            rank_payload,
            input_len=len(data),
            starts=window_starts,
            ends=window_ends,
            tokens=flat_tokens,
            token_offsets=token_offsets,
            source_chunk_base=batch_start,
            chunk_bytes=chunk_bytes,
            num_chunks=num_chunks,
        )

        if layout is None:
            token_starts_global = []
            source_chunks = []
            for window_idx, (ext_start, ext_end) in enumerate(window_ranges):
                token_start = token_offsets[window_idx]
                token_end = token_offsets[window_idx + 1]
                if token_start < 0 or token_end < token_start or token_end > len(flat_tokens):
                    return None

                cursor = 0
                ext_len = ext_end - ext_start
                chunk_idx = batch_start + window_idx
                for token_idx in range(token_start, token_end):
                    token = flat_tokens[token_idx]
                    token_len = token_lens.get(token)
                    if token_len is None:
                        return None
                    next_cursor = cursor + token_len
                    if next_cursor > ext_len:
                        return None
                    token_starts_global.append(ext_start + cursor)
                    source_chunks.append(chunk_idx)
                    cursor = next_cursor
                if cursor != ext_len:
                    return None
        else:
            token_starts_global, source_chunks = layout

        if len(token_starts_global) != len(flat_tokens):
            return None

        flags = metal_bridge.chunk_owner_flags(
            token_starts_global,
            source_chunks,
            chunk_bytes=chunk_bytes,
            num_chunks=num_chunks,
        )
        if flags is None or len(flags) != len(flat_tokens):
            return None

        filtered = native_bridge.filter_tokens_by_keep_flags(flat_tokens, flags)
        if filtered is not None:
            stitched.extend(filtered)
        else:
            for token, keep in zip(flat_tokens, flags):
                if keep != 0:
                    stitched.append(token)

    total = _token_total_bytes(stitched, token_lens)
    if total is None or total != len(data):
        return None

    return stitched


def _compute_token_layout(
    tokens: Sequence[int],
    token_lens: dict[int, int],
) -> tuple[list[int], list[int], int] | None:
    starts: list[int] = []
    ends: list[int] = []
    cursor = 0
    for token in tokens:
        token_len = token_lens.get(token)
        if token_len is None:
            return None
        starts.append(cursor)
        cursor += token_len
        ends.append(cursor)
    return starts, ends, cursor


def _token_total_bytes(tokens: Sequence[int], token_lens: dict[int, int]) -> int | None:
    total = 0
    for token in tokens:
        token_len = token_lens.get(token)
        if token_len is None:
            return None
        total += token_len
    return total


def _normalize_ranges(
    ranges: Sequence[tuple[int, int]],
    *,
    data_len: int,
) -> list[tuple[int, int]] | None:
    normalized: list[tuple[int, int]] = []
    for item in ranges:
        if len(item) != 2:
            return None
        start = int(item[0])
        end = int(item[1])
        if start < 0 or end < start or end > data_len:
            return None
        normalized.append((start, end))
    return normalized


def _encode_bpe_ranges_exact_pieces(
    bridge: Any,
    rank_payload: bytes,
    data: bytes,
    ranges: Sequence[tuple[int, int]],
) -> list[list[int]] | None:
    if not ranges:
        return []

    batch = bridge.encode_bpe_ranges_from_ranks(rank_payload, data, list(ranges))
    if batch is not None:
        flat_tokens, token_offsets = batch
        if len(token_offsets) == len(ranges) + 1:
            pieces: list[list[int]] = []
            for idx in range(len(ranges)):
                token_start = token_offsets[idx]
                token_end = token_offsets[idx + 1]
                if token_start < 0 or token_end < token_start or token_end > len(flat_tokens):
                    return None
                pieces.append(flat_tokens[token_start:token_end])
            return pieces

    pieces_fallback: list[list[int]] = []
    for start, end in ranges:
        tokens = bridge.encode_bpe_from_ranks(rank_payload, data[start:end])
        if tokens is None:
            return None
        pieces_fallback.append(tokens)
    return pieces_fallback


def _flatten_token_pieces(pieces: Sequence[Sequence[int]]) -> tuple[list[int], list[int]]:
    flat_tokens: list[int] = []
    token_offsets = [0]
    for piece in pieces:
        if piece:
            flat_tokens.extend(piece)
        token_offsets.append(len(flat_tokens))
    return flat_tokens, token_offsets


def _encode_bpe_chunked_stitched_metal_many(
    rank_payload: bytes,
    data: bytes,
    *,
    ranges: Sequence[tuple[int, int]],
    chunk_bytes: int,
    overlap_bytes: int,
) -> list[list[int]] | None:
    native_bridge = get_native_bridge()
    metal_bridge = get_metal_bridge()
    if not native_bridge.available or not metal_bridge.available:
        return None
    if not ranges:
        return []

    token_lens = _rank_token_lens_from_payload(rank_payload)
    full_piece_max_bytes = int(os.environ.get("TURBOTOKEN_METAL_BPE_FULL_MAX_BYTES", "16384"))
    full_piece_gpu_ready = _ensure_metal_bpe_rank_table(rank_payload)

    per_piece: list[list[int] | None] = [None] * len(ranges)
    long_piece_indices: list[int] = []
    long_piece_ranges: list[tuple[int, int]] = []
    long_piece_num_chunks: list[int] = []

    for piece_idx, (piece_start, piece_end) in enumerate(ranges):
        piece_len = piece_end - piece_start
        piece_bytes = data[piece_start:piece_end]

        if piece_len <= full_piece_max_bytes and full_piece_gpu_ready:
            gpu_tokens = metal_bridge.encode_bpe_from_bytes(piece_bytes)
            if gpu_tokens is not None:
                gpu_total = _token_total_bytes(gpu_tokens, token_lens)
                if gpu_total == piece_len:
                    per_piece[piece_idx] = gpu_tokens
                    continue

        num_chunks = (piece_len + chunk_bytes - 1) // chunk_bytes
        if num_chunks <= 1:
            exact = native_bridge.encode_bpe_from_ranks(rank_payload, piece_bytes)
            if exact is None:
                return None
            per_piece[piece_idx] = exact
            continue

        long_piece_indices.append(piece_idx)
        long_piece_ranges.append((piece_start, piece_end))
        long_piece_num_chunks.append(num_chunks)

    if not long_piece_indices:
        if any(piece_tokens is None for piece_tokens in per_piece):
            return None
        return [piece_tokens or [] for piece_tokens in per_piece]

    window_piece_indices: list[int] = []
    window_piece_starts: list[int] = []
    window_ext_starts: list[int] = []
    window_ext_ends: list[int] = []
    window_chunk_indices: list[int] = []
    window_num_chunks: list[int] = []

    for idx, (piece_start, piece_end) in enumerate(long_piece_ranges):
        piece_idx = long_piece_indices[idx]
        num_chunks = long_piece_num_chunks[idx]
        for local_chunk_idx in range(num_chunks):
            chunk_start = piece_start + (local_chunk_idx * chunk_bytes)
            chunk_end = min(piece_end, chunk_start + chunk_bytes)
            ext_start = max(piece_start, chunk_start - overlap_bytes)
            ext_end = min(piece_end, chunk_end + overlap_bytes)
            window_piece_indices.append(piece_idx)
            window_piece_starts.append(piece_start)
            window_ext_starts.append(ext_start)
            window_ext_ends.append(ext_end)
            window_chunk_indices.append(local_chunk_idx)
            window_num_chunks.append(num_chunks)

    ext_bytes_per_chunk = max(1, chunk_bytes + (2 * overlap_bytes))
    chunks_per_batch = max(1, min(512, (8 * 1024 * 1024) // ext_bytes_per_chunk))

    piece_flat_tokens: dict[int, list[int]] = {piece_idx: [] for piece_idx in long_piece_indices}
    piece_token_starts: dict[int, list[int]] = {piece_idx: [] for piece_idx in long_piece_indices}
    piece_source_chunks: dict[int, list[int]] = {piece_idx: [] for piece_idx in long_piece_indices}

    for batch_start in range(0, len(window_ext_starts), chunks_per_batch):
        batch_end = min(len(window_ext_starts), batch_start + chunks_per_batch)
        window_ranges = [
            (window_ext_starts[window_idx], window_ext_ends[window_idx]) for window_idx in range(batch_start, batch_end)
        ]
        batch = native_bridge.encode_bpe_ranges_from_ranks(rank_payload, data, window_ranges)
        if batch is None:
            return None

        flat_tokens, token_offsets = batch
        if len(token_offsets) != len(window_ranges) + 1:
            return None

        for local_window_idx in range(len(window_ranges)):
            token_start = token_offsets[local_window_idx]
            token_end = token_offsets[local_window_idx + 1]
            if token_start < 0 or token_end < token_start or token_end > len(flat_tokens):
                return None

            window_idx = batch_start + local_window_idx
            piece_idx = window_piece_indices[window_idx]
            piece_start = window_piece_starts[window_idx]
            ext_start = window_ext_starts[window_idx]
            ext_end = window_ext_ends[window_idx]
            local_chunk_idx = window_chunk_indices[window_idx]
            num_chunks = window_num_chunks[window_idx]
            if local_chunk_idx < 0 or local_chunk_idx >= num_chunks:
                return None

            cursor = 0
            ext_len = ext_end - ext_start
            for token in flat_tokens[token_start:token_end]:
                token_len = token_lens.get(token)
                if token_len is None:
                    return None
                next_cursor = cursor + token_len
                if next_cursor > ext_len:
                    return None
                token_start_local = (ext_start + cursor) - piece_start
                piece_token_starts[piece_idx].append(token_start_local)
                piece_source_chunks[piece_idx].append(local_chunk_idx)
                piece_flat_tokens[piece_idx].append(token)
                cursor = next_cursor
            if cursor != ext_len:
                return None

    for idx, piece_idx in enumerate(long_piece_indices):
        num_chunks = long_piece_num_chunks[idx]
        token_starts = piece_token_starts[piece_idx]
        source_chunks = piece_source_chunks[piece_idx]
        tokens = piece_flat_tokens[piece_idx]
        flags = metal_bridge.chunk_owner_flags(
            token_starts,
            source_chunks,
            chunk_bytes=chunk_bytes,
            num_chunks=num_chunks,
        )
        if flags is None or len(flags) != len(tokens):
            return None

        filtered = native_bridge.filter_tokens_by_keep_flags(tokens, flags)
        if filtered is not None:
            kept = filtered
        else:
            kept = [token for token, keep in zip(tokens, flags) if keep != 0]

        piece_start, piece_end = long_piece_ranges[idx]
        kept_total = _token_total_bytes(kept, token_lens)
        if kept_total is None or kept_total != (piece_end - piece_start):
            return None
        per_piece[piece_idx] = kept

    if any(piece_tokens is None for piece_tokens in per_piece):
        return None
    return [piece_tokens or [] for piece_tokens in per_piece]


def _repair_chunk_boundaries(
    rank_payload: bytes,
    data: bytes,
    tokens: Sequence[int],
    *,
    chunk_bytes: int,
    overlap_bytes: int,
    max_passes: int = 3,
) -> list[int] | None:
    if not tokens:
        return []

    native_bridge = get_native_bridge()
    if not native_bridge.available:
        return list(tokens)

    token_lens = _rank_token_lens_from_payload(rank_payload)
    repaired = list(tokens)
    num_chunks = (len(data) + chunk_bytes - 1) // chunk_bytes
    if num_chunks <= 1:
        return repaired

    repair_window = max(64, overlap_bytes)
    for _ in range(max_passes):
        layout = _compute_token_layout(repaired, token_lens)
        if layout is None:
            return None
        starts, ends, total = layout
        if total != len(data):
            return None

        changes: list[tuple[int, int, list[int]]] = []
        last_end_idx = -1
        for chunk_idx in range(1, num_chunks):
            boundary = chunk_idx * chunk_bytes
            window_start = max(0, boundary - repair_window)
            window_end = min(len(data), boundary + repair_window)

            start_idx = bisect.bisect_right(ends, window_start)
            end_idx = bisect.bisect_left(starts, window_end)
            if start_idx >= end_idx:
                continue
            if start_idx < last_end_idx:
                continue

            replace_start = starts[start_idx]
            replace_end = ends[end_idx - 1]
            if replace_end <= replace_start:
                continue

            segment = data[replace_start:replace_end]
            exact = native_bridge.encode_bpe_from_ranks(rank_payload, segment)
            if exact is None:
                return None
            if exact != repaired[start_idx:end_idx]:
                changes.append((start_idx, end_idx, exact))
                last_end_idx = end_idx

        if not changes:
            if repair_window >= chunk_bytes:
                break
            repair_window = min(chunk_bytes, repair_window * 2)
            continue

        for start_idx, end_idx, exact in reversed(changes):
            repaired[start_idx:end_idx] = exact

    return repaired


def encode_bpe_chunked_stitched(
    rank_payload: bytes,
    data: bytes,
    *,
    chunk_bytes: int = 16_384,
    overlap_bytes: int = 512,
    strict_verify: bool = True,
    prefer_metal_stitch: bool = False,
) -> list[int] | None:
    """Experimental chunked BPE path with overlap stitching.

    This is a prototype for chunk-parallel BPE merge/stitch workflows.
    With `prefer_metal_stitch=True`, token owner selection runs in a Metal
    stitch kernel; otherwise the native chunk-owner export is preferred.
    Python/range stitching remains as a fallback when symbols are unavailable.
    """

    if chunk_bytes <= 0:
        raise ValueError("chunk_bytes must be > 0")
    if overlap_bytes <= 0:
        raise ValueError("overlap_bytes must be > 0")
    if not data:
        return []

    bridge = get_native_bridge()
    if not bridge.available:
        return None

    if len(data) <= chunk_bytes:
        return bridge.encode_bpe_from_ranks(rank_payload, data)

    stitched: list[int] | None = None
    used_metal_result = False
    stitch_cache_key = (hashlib.sha256(rank_payload).hexdigest()[:16], chunk_bytes, overlap_bytes, len(data))
    stitch_cache_state = _metal_stitch_support_cache.get(stitch_cache_key)
    force_repair = os.environ.get("TURBOTOKEN_METAL_STITCH_ALWAYS_REPAIR", "").strip().lower() in {
        "1",
        "true",
        "yes",
    }
    if prefer_metal_stitch:
        if stitch_cache_state is False:
            exact = bridge.encode_bpe_from_ranks(rank_payload, data)
            if exact is not None:
                stitched = exact
        else:
            stitched = _encode_bpe_chunked_stitched_metal(
                rank_payload,
                data,
                chunk_bytes=chunk_bytes,
                overlap_bytes=overlap_bytes,
            )
            if stitched is None:
                _metal_stitch_support_cache[stitch_cache_key] = False
            else:
                used_metal_result = True

    if stitched is None:
        stitched = bridge.encode_bpe_chunked_stitched_from_ranks(
            rank_payload,
            data,
            chunk_bytes=chunk_bytes,
            overlap_bytes=overlap_bytes,
        )
    if stitched is None:
        token_lens = _rank_token_lens_from_payload(rank_payload)
        num_chunks = (len(data) + chunk_bytes - 1) // chunk_bytes
        stitched = []
        chunk_ranges: list[tuple[int, int]] = []
        for chunk_idx in range(num_chunks):
            start = chunk_idx * chunk_bytes
            end = min(len(data), start + chunk_bytes)
            ext_start = max(0, start - overlap_bytes)
            ext_end = min(len(data), end + overlap_bytes)
            chunk_ranges.append((ext_start, ext_end))

        # Keep each batch around ~8 MiB of duplicated overlap windows to cap memory.
        ext_bytes_per_chunk = max(1, chunk_bytes + (2 * overlap_bytes))
        chunks_per_batch = max(1, min(512, (8 * 1024 * 1024) // ext_bytes_per_chunk))

        for batch_start in range(0, num_chunks, chunks_per_batch):
            batch_end = min(num_chunks, batch_start + chunks_per_batch)
            window_ranges = chunk_ranges[batch_start:batch_end]
            batch = bridge.encode_bpe_ranges_from_ranks(rank_payload, data, window_ranges)
            if batch is None:
                scalar = _encode_bpe_chunked_stitched_scalar(
                    bridge,
                    rank_payload,
                    data,
                    chunk_bytes=chunk_bytes,
                    overlap_bytes=overlap_bytes,
                    num_chunks=num_chunks,
                    token_lens=token_lens,
                )
                if scalar is None:
                    return None
                stitched = scalar
                break

            flat_tokens, token_offsets = batch
            window_chunks = len(window_ranges)
            if len(token_offsets) != window_chunks + 1:
                return None

            for window_idx in range(window_chunks):
                chunk_idx = batch_start + window_idx
                ext_start, ext_end = chunk_ranges[chunk_idx]
                token_start = token_offsets[window_idx]
                token_end = token_offsets[window_idx + 1]
                if token_start < 0 or token_end < token_start or token_end > len(flat_tokens):
                    return None
                if not _stitch_chunk_tokens(
                    stitched=stitched,
                    chunk_idx=chunk_idx,
                    num_chunks=num_chunks,
                    chunk_bytes=chunk_bytes,
                    ext_start=ext_start,
                    ext_end=ext_end,
                    tokens=flat_tokens[token_start:token_end],
                    token_lens=token_lens,
                ):
                    return None

    if prefer_metal_stitch and used_metal_result and stitched is not None:
        should_repair = force_repair or strict_verify or stitch_cache_state is not True
        if not should_repair:
            repaired = stitched
        else:
            repaired = _repair_chunk_boundaries(
                rank_payload,
                data,
                stitched,
                chunk_bytes=chunk_bytes,
                overlap_bytes=overlap_bytes,
            )
        if repaired is not None:
            stitched = repaired
        else:
            stitched = None
            _metal_stitch_support_cache[stitch_cache_key] = False
            used_metal_result = False

    if stitched is not None:
        token_lens = _rank_token_lens_from_payload(rank_payload)
        total = _token_total_bytes(stitched, token_lens)
        if total is None or total != len(data):
            exact = bridge.encode_bpe_from_ranks(rank_payload, data)
            if exact is None:
                return None
            stitched = exact
            used_metal_result = False
    else:
        exact = bridge.encode_bpe_from_ranks(rank_payload, data)
        if exact is None:
            return None
        stitched = exact
        used_metal_result = False

    if prefer_metal_stitch and stitch_cache_state is None:
        exact_probe = bridge.encode_bpe_from_ranks(rank_payload, data)
        if exact_probe is None:
            return None
        if not used_metal_result:
            _metal_stitch_support_cache[stitch_cache_key] = False
            stitched = exact_probe
        elif stitched != exact_probe:
            _metal_stitch_support_cache[stitch_cache_key] = False
            stitched = exact_probe
        else:
            _metal_stitch_support_cache[stitch_cache_key] = True

    if strict_verify:
        full_tokens = bridge.encode_bpe_from_ranks(rank_payload, data)
        if full_tokens is None:
            return None
        if stitched != full_tokens:
            return full_tokens

    return stitched


def encode_bpe_chunked_stitched_many(
    rank_payload: bytes,
    data: bytes,
    ranges: Sequence[tuple[int, int]],
    *,
    chunk_bytes: int = 16_384,
    overlap_bytes: int = 512,
    strict_verify: bool = True,
    prefer_metal_stitch: bool = False,
) -> tuple[list[int], list[int]] | None:
    if chunk_bytes <= 0:
        raise ValueError("chunk_bytes must be > 0")
    if overlap_bytes <= 0:
        raise ValueError("overlap_bytes must be > 0")

    normalized = _normalize_ranges(ranges, data_len=len(data))
    if normalized is None:
        return None
    if not normalized:
        return [], [0]

    bridge = get_native_bridge()
    if not bridge.available:
        return None

    if len(normalized) == 1:
        start, end = normalized[0]
        tokens = encode_bpe_chunked_stitched(
            rank_payload,
            data[start:end],
            chunk_bytes=chunk_bytes,
            overlap_bytes=overlap_bytes,
            strict_verify=strict_verify,
            prefer_metal_stitch=prefer_metal_stitch,
        )
        if tokens is None:
            return None
        return tokens, [0, len(tokens)]

    pieces: list[list[int]] | None = None
    if prefer_metal_stitch:
        pieces = _encode_bpe_chunked_stitched_metal_many(
            rank_payload,
            data,
            ranges=normalized,
            chunk_bytes=chunk_bytes,
            overlap_bytes=overlap_bytes,
        )

    if pieces is None:
        pieces = _encode_bpe_ranges_exact_pieces(bridge, rank_payload, data, normalized)
        if pieces is None:
            return None
    elif strict_verify:
        exact = _encode_bpe_ranges_exact_pieces(bridge, rank_payload, data, normalized)
        if exact is None:
            return None
        if len(exact) != len(pieces):
            return None
        for idx in range(len(pieces)):
            if pieces[idx] != exact[idx]:
                pieces[idx] = exact[idx]

    return _flatten_token_pieces(pieces)
