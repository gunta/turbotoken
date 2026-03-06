from __future__ import annotations

import pytest

import turbotoken.core as core_module
from turbotoken import get_encoding, list_encoding_names


@pytest.mark.parametrize(
    ("encoding", "expected"),
    [
        ("r50k_base", [31373, 995]),
        ("p50k_base", [31373, 995]),
        ("cl100k_base", [15339, 1917]),
        ("o200k_base", [24912, 2375]),
    ],
)
def test_encode_matches_known_hello_world_tokens(encoding: str, expected: list[int]) -> None:
    enc = get_encoding(encoding)
    assert enc.encode("hello world") == expected


@pytest.mark.parametrize(
    ("encoding", "text", "expected"),
    [
        ("o200k_base", "This is some text", [2500, 382, 1236, 2201]),
        ("o200k_base", "hello 👋 world 🌍", [24912, 61138, 233, 2375, 130321, 235]),
        ("cl100k_base", "This is some text", [2028, 374, 1063, 1495]),
        ("cl100k_base", "hello 👋 world 🌍", [15339, 62904, 233, 1917, 11410, 234, 235]),
    ],
)
def test_encode_matches_selected_gpt_tokenizer_reference_vectors(
    encoding: str,
    text: str,
    expected: list[int],
) -> None:
    enc = get_encoding(encoding)
    assert enc.encode(text) == expected


def test_roundtrip_utf8_text() -> None:
    enc = get_encoding("o200k_base")
    text = "emoji: 🚀✅"
    assert enc.decode(enc.encode(text)) == text


def test_list_encoding_names_contains_core_encodings() -> None:
    names = list_encoding_names()
    expected = {"cl100k_base", "o200k_base", "p50k_base", "r50k_base", "gpt2", "p50k_edit", "o200k_harmony"}
    assert expected.issubset(set(names))


def test_unknown_encoding_raises_value_error() -> None:
    with pytest.raises(ValueError):
        get_encoding("not_real")


def test_special_token_disallowed_by_default() -> None:
    enc = get_encoding("o200k_base")
    with pytest.raises(ValueError):
        enc.encode("x<|endoftext|>y")


def test_special_token_allowed_maps_to_special_id() -> None:
    enc = get_encoding("o200k_base")
    out = enc.encode("x<|endoftext|>y", allowed_special={"<|endoftext|>"})
    assert enc.eot_token in out


def test_count_with_allowed_special_counts_one_token_for_special_marker() -> None:
    enc = get_encoding("o200k_base")
    assert enc.count("x<|endoftext|>y", allowed_special={"<|endoftext|>"}) == 3


def test_count_tokens_alias_matches_count() -> None:
    enc = get_encoding("o200k_base")
    text = "Tokenizer count alias check."
    assert enc.count_tokens(text) == enc.count(text)


def test_is_within_token_limit_matches_count_semantics() -> None:
    enc = get_encoding("o200k_base")
    text = "hello world"
    token_count = enc.count(text)
    assert enc.is_within_token_limit(text, token_count) == token_count
    assert enc.is_within_token_limit(text, token_count - 1) is False


def test_is_within_token_limit_handles_special_tokens() -> None:
    enc = get_encoding("o200k_base")
    text = "x<|endoftext|>y"
    with pytest.raises(ValueError):
        enc.is_within_token_limit(text, 16)

    assert enc.is_within_token_limit(text, 3, allowed_special={"<|endoftext|>"}) == 3
    assert enc.is_within_token_limit(text, 2, allowed_special={"<|endoftext|>"}) is False


def test_encode_single_token_accepts_single_byte_and_special() -> None:
    enc = get_encoding("o200k_base")
    hello_token = enc.encode("hello")
    assert len(hello_token) == 1
    assert enc.encode_single_token("hello") == hello_token[0]
    assert enc.encode_single_token(b"a") == enc.encode_single_token("a")
    assert enc.encode_single_token("<|endoftext|>") == enc.eot_token


def test_encode_single_token_rejects_non_single_token_input() -> None:
    enc = get_encoding("o200k_base")
    with pytest.raises(KeyError):
        enc.encode_single_token("hello world")


def test_encode_generator_and_decode_generator_roundtrip() -> None:
    enc = get_encoding("o200k_base")
    text = "hello<|endoftext|>world"
    chunks = list(enc.encode_generator(text, allowed_special={"<|endoftext|>"}))
    flat = [token for chunk in chunks for token in chunk]
    assert flat == enc.encode(text, allowed_special={"<|endoftext|>"})

    decoded_chunks = list(enc.decode_generator(flat))
    assert "".join(decoded_chunks) == text


def test_chat_helpers_count_and_limit_are_consistent() -> None:
    enc = get_encoding("o200k_base")
    chat = [
        {"role": "system", "content": "You are concise."},
        {"role": "user", "content": "Hello tokenizer"},
        {"role": "assistant", "content": "Hi."},
    ]

    encoded = enc.encode_chat(chat)
    count = enc.count_chat(chat)
    assert count == len(encoded)
    assert enc.count_chat_tokens(chat) == count
    assert enc.is_chat_within_token_limit(chat, count) == count
    assert enc.is_chat_within_token_limit(chat, count - 1) is False


def test_chat_encode_generator_matches_chat_encode() -> None:
    enc = get_encoding("o200k_base")
    chat = [
        {"role": "user", "content": "one"},
        {"role": "assistant", "content": "two"},
    ]
    chunks = list(enc.encode_chat_generator(chat))
    flat = [token for chunk in chunks for token in chunk]
    assert flat == enc.encode_chat(chat)


def test_chat_template_modes_and_custom_template() -> None:
    enc = get_encoding("o200k_base")
    chat = [{"role": "user", "content": "hello"}]

    native_tokens = enc.encode_chat(chat, template="turbotoken_v1")
    compat_tokens = enc.encode_chat(chat, template="im_tokens")
    assert native_tokens != compat_tokens

    custom_tokens = enc.encode_chat(
        chat,
        template={
            "message_prefix": "<msg role='{role}'>",
            "message_suffix": "</msg>",
            "assistant_prefix": "<msg role='{role}'>",
        },
        prime_with_assistant_response="assistant",
    )
    assert len(custom_tokens) > 0


def test_native_file_helpers_count_and_limit_are_consistent(tmp_path) -> None:
    enc = get_encoding("o200k_base")
    sample = tmp_path / "sample.txt"
    sample.write_text("hello world", encoding="utf-8")

    tokens = enc.encode_file_native(sample)
    if tokens is None:
        pytest.skip("native file-path BPE bridge not available")

    count = enc.count_file_native(sample)
    if count is None:
        pytest.skip("native file-path BPE count bridge not available")
    assert count == len(tokens)

    assert enc.is_file_within_token_limit_native(sample, count) == count
    assert enc.is_file_within_token_limit_native(sample, count - 1) is False


def test_merge_cache_controls_preserve_results() -> None:
    enc = get_encoding("o200k_base")
    text = ("cache control check " * 32).strip()
    baseline = enc.encode(text)
    enc.set_merge_cache_size(0)
    assert enc.encode(text) == baseline
    enc.set_merge_cache_size(1024)
    enc.clear_merge_cache()
    assert enc.encode(text) == baseline


def test_native_ascii_pretokenizer_fast_path_matches_regex_fallback(monkeypatch: pytest.MonkeyPatch) -> None:
    enc = get_encoding("cl100k_base")
    text = ("hello world " * 256).strip()

    monkeypatch.setenv("TURBOTOKEN_NATIVE_PRETOKENIZER_ENABLE", "1")
    monkeypatch.delenv("TURBOTOKEN_NATIVE_PRETOKENIZER_DISABLE", raising=False)
    fast = enc.encode_ordinary(text)

    monkeypatch.setenv("TURBOTOKEN_NATIVE_PRETOKENIZER_DISABLE", "1")
    slow = enc.encode_ordinary(text)
    assert fast == slow


def test_o200k_native_ascii_pretokenizer_fast_path_matches_fallback(monkeypatch: pytest.MonkeyPatch) -> None:
    enc = get_encoding("o200k_base")
    text = ("Tokenizer matters, for coding agents.\n" * 64).strip()

    monkeypatch.setenv("TURBOTOKEN_NATIVE_O200K_PRETOKENIZER_ENABLE", "1")
    monkeypatch.delenv("TURBOTOKEN_NATIVE_O200K_PRETOKENIZER_DISABLE", raising=False)
    fast = enc.encode_ordinary(text)

    monkeypatch.setenv("TURBOTOKEN_NATIVE_O200K_PRETOKENIZER_DISABLE", "1")
    slow = enc.encode_ordinary(text)
    assert fast == slow
    assert enc.count(text) == len(fast)


def test_o200k_ascii_regex_fast_path_matches_regex_module_fallback(monkeypatch: pytest.MonkeyPatch) -> None:
    enc = get_encoding("o200k_base")
    text = ("A MIX of UPPER and lower CASE plus 123 numbers.\n" * 64).strip()

    # Isolate regex path by disabling native o200k pretokenizer.
    monkeypatch.setenv("TURBOTOKEN_NATIVE_O200K_PRETOKENIZER_DISABLE", "1")
    monkeypatch.delenv("TURBOTOKEN_ASCII_REGEX_FASTPATH_DISABLE", raising=False)
    fast = enc.encode_ordinary(text)

    monkeypatch.setenv("TURBOTOKEN_ASCII_REGEX_FASTPATH_DISABLE", "1")
    slow = enc.encode_ordinary(text)
    assert fast == slow


def test_o200k_native_full_ascii_path_matches_fallback(monkeypatch: pytest.MonkeyPatch) -> None:
    enc = get_encoding("o200k_base")
    text = ("Tokenizer speed matters for large ASCII corpora. " * 2048).strip()

    monkeypatch.setenv("TURBOTOKEN_NATIVE_O200K_FULL_ENABLE", "1")
    monkeypatch.delenv("TURBOTOKEN_NATIVE_O200K_FULL_DISABLE", raising=False)
    fast = enc.encode_ordinary(text)
    fast_count = enc.count(text)

    monkeypatch.setenv("TURBOTOKEN_NATIVE_O200K_FULL_DISABLE", "1")
    slow = enc.encode_ordinary(text)
    slow_count = enc.count(text)

    assert fast == slow
    assert fast_count == slow_count == len(slow)


def test_o200k_native_full_ascii_auto_path_activates_on_linux_x86(monkeypatch: pytest.MonkeyPatch) -> None:
    enc = get_encoding("o200k_base")
    text = ("Tokenizer speed matters for large ASCII corpora. " * 2048).strip()

    monkeypatch.setenv("TURBOTOKEN_NATIVE_O200K_FULL_DISABLE", "1")
    monkeypatch.setenv("TURBOTOKEN_NATIVE_RANGE_BATCH_DISABLE", "1")
    baseline_tokens = enc.encode(text)
    baseline_count = enc.count(text)

    monkeypatch.delenv("TURBOTOKEN_NATIVE_O200K_FULL_DISABLE", raising=False)
    monkeypatch.delenv("TURBOTOKEN_NATIVE_O200K_FULL_ENABLE", raising=False)
    monkeypatch.setattr(core_module.platform, "system", lambda: "Linux")
    monkeypatch.setattr(core_module.platform, "machine", lambda: "x86_64")

    calls = {"encode": 0, "count": 0}

    class Session:
        def encode_bpe_ascii_o200k(self, data: bytes) -> list[int]:
            assert data == text.encode("ascii")
            calls["encode"] += 1
            return baseline_tokens

        def count_bpe_ascii_o200k(self, data: bytes) -> int:
            assert data == text.encode("ascii")
            calls["count"] += 1
            return baseline_count

    monkeypatch.setattr(type(enc), "_native_rank_session", lambda self: Session())

    assert enc.encode(text) == baseline_tokens
    assert enc.count(text) == baseline_count
    assert calls == {"encode": 1, "count": 1}


def test_o200k_native_full_ascii_auto_path_respects_disable(monkeypatch: pytest.MonkeyPatch) -> None:
    enc = get_encoding("o200k_base")
    text = ("Tokenizer speed matters for large ASCII corpora. " * 2048).strip()

    monkeypatch.setenv("TURBOTOKEN_NATIVE_O200K_FULL_DISABLE", "1")
    monkeypatch.setenv("TURBOTOKEN_NATIVE_RANGE_BATCH_DISABLE", "1")
    baseline_tokens = enc.encode(text)
    baseline_count = enc.count(text)

    monkeypatch.setattr(core_module.platform, "system", lambda: "Linux")
    monkeypatch.setattr(core_module.platform, "machine", lambda: "x86_64")

    class Session:
        def encode_bpe_ascii_o200k(self, _: bytes) -> list[int]:
            raise AssertionError("native full path should stay disabled")

        def count_bpe_ascii_o200k(self, _: bytes) -> int:
            raise AssertionError("native full path should stay disabled")

    monkeypatch.setattr(type(enc), "_native_rank_session", lambda self: Session())

    assert enc.encode(text) == baseline_tokens
    assert enc.count(text) == baseline_count


def test_cl100k_native_full_ascii_path_matches_fallback(monkeypatch: pytest.MonkeyPatch) -> None:
    enc = get_encoding("cl100k_base")
    text = ("Tokenizer speed matters for large cl100k ASCII corpora. " * 2048).strip()

    monkeypatch.setenv("TURBOTOKEN_NATIVE_CL100K_FULL_ENABLE", "1")
    monkeypatch.delenv("TURBOTOKEN_NATIVE_CL100K_FULL_DISABLE", raising=False)
    fast = enc.encode_ordinary(text)
    fast_count = enc.count(text)

    monkeypatch.setenv("TURBOTOKEN_NATIVE_CL100K_FULL_DISABLE", "1")
    monkeypatch.delenv("TURBOTOKEN_NATIVE_CL100K_FULL_ENABLE", raising=False)
    slow = enc.encode_ordinary(text)
    slow_count = enc.count(text)

    assert fast == slow
    assert fast_count == slow_count == len(slow)


def test_native_range_batch_force_path_matches_fallback(monkeypatch: pytest.MonkeyPatch) -> None:
    enc = get_encoding("o200k_base")
    text = ("Tokenizer speed matters for range-batch routing.\n" * 256).strip()

    monkeypatch.delenv("TURBOTOKEN_NATIVE_RANGE_BATCH_DISABLE", raising=False)
    monkeypatch.setenv("TURBOTOKEN_NATIVE_RANGE_BATCH_ENABLE", "1")
    auto_tokens = enc.encode_ordinary(text)
    auto_count = enc.count(text)

    monkeypatch.setenv("TURBOTOKEN_NATIVE_RANGE_BATCH_DISABLE", "1")
    monkeypatch.delenv("TURBOTOKEN_NATIVE_RANGE_BATCH_ENABLE", raising=False)
    fallback_tokens = enc.encode_ordinary(text)
    fallback_count = enc.count(text)

    assert auto_tokens == fallback_tokens
    assert auto_count == fallback_count == len(fallback_tokens)


def test_native_range_batch_auto_path_activates_on_linux_x86(monkeypatch: pytest.MonkeyPatch) -> None:
    enc = get_encoding("o200k_base")
    text = ("Tokenizer speed matters for range-batch routing.\n" * 2048).strip()

    monkeypatch.setenv("TURBOTOKEN_NATIVE_O200K_FULL_DISABLE", "1")
    monkeypatch.setenv("TURBOTOKEN_NATIVE_RANGE_BATCH_DISABLE", "1")
    baseline_tokens = enc.encode(text)
    baseline_count = enc.count(text)

    data = text.encode("ascii")
    midpoint = len(data) // 2
    ranges = [(0, midpoint), (midpoint, len(data))]
    token_offsets = [0, len(baseline_tokens) // 2, len(baseline_tokens)]
    calls = {"encode": 0, "count": 0}

    monkeypatch.delenv("TURBOTOKEN_NATIVE_RANGE_BATCH_DISABLE", raising=False)
    monkeypatch.delenv("TURBOTOKEN_NATIVE_RANGE_BATCH_ENABLE", raising=False)
    monkeypatch.setattr(core_module.platform, "system", lambda: "Linux")
    monkeypatch.setattr(core_module.platform, "machine", lambda: "x86_64")
    monkeypatch.setattr(type(enc), "_ordinary_piece_ranges_bytes", lambda self, _: (data, ranges))

    class Session:
        def encode_bpe_ranges(
            self,
            batch_data: bytes,
            batch_ranges: list[tuple[int, int]],
        ) -> tuple[list[int], list[int]]:
            assert batch_data == data
            assert batch_ranges == ranges
            calls["encode"] += 1
            return baseline_tokens, token_offsets

        def count_bpe_ranges(self, batch_data: bytes, batch_ranges: list[tuple[int, int]]) -> int:
            assert batch_data == data
            assert batch_ranges == ranges
            calls["count"] += 1
            return baseline_count

    monkeypatch.setattr(type(enc), "_native_rank_session", lambda self: Session())

    assert enc.encode(text) == baseline_tokens
    assert enc.count(text) == baseline_count
    assert calls == {"encode": 1, "count": 1}


def test_o200k_native_auto_paths_stay_off_below_large_ascii_threshold(monkeypatch: pytest.MonkeyPatch) -> None:
    enc = get_encoding("o200k_base")
    text = ("Small ASCII payloads should stay on the wrapper fallback path. " * 8).strip()

    monkeypatch.setenv("TURBOTOKEN_NATIVE_O200K_FULL_DISABLE", "1")
    monkeypatch.setenv("TURBOTOKEN_NATIVE_RANGE_BATCH_DISABLE", "1")
    baseline_tokens = enc.encode(text)
    baseline_count = enc.count(text)

    monkeypatch.delenv("TURBOTOKEN_NATIVE_O200K_FULL_DISABLE", raising=False)
    monkeypatch.delenv("TURBOTOKEN_NATIVE_O200K_FULL_ENABLE", raising=False)
    monkeypatch.delenv("TURBOTOKEN_NATIVE_RANGE_BATCH_DISABLE", raising=False)
    monkeypatch.delenv("TURBOTOKEN_NATIVE_RANGE_BATCH_ENABLE", raising=False)
    monkeypatch.setattr(core_module.platform, "system", lambda: "Linux")
    monkeypatch.setattr(core_module.platform, "machine", lambda: "x86_64")

    class Session:
        def encode_bpe_ascii_o200k(self, _: bytes) -> list[int]:
            raise AssertionError("native full path should not auto-enable below the large-input threshold")

        def count_bpe_ascii_o200k(self, _: bytes) -> int:
            raise AssertionError("native full path should not auto-enable below the large-input threshold")

        def encode_bpe_ranges(
            self,
            _: bytes,
            __: list[tuple[int, int]],
        ) -> tuple[list[int], list[int]]:
            raise AssertionError("native range path should not auto-enable below the large-input threshold")

        def count_bpe_ranges(self, _: bytes, __: list[tuple[int, int]]) -> int:
            raise AssertionError("native range path should not auto-enable below the large-input threshold")

    monkeypatch.setattr(type(enc), "_native_rank_session", lambda self: Session())

    assert enc.encode(text) == baseline_tokens
    assert enc.count(text) == baseline_count


def test_decode_bytes_native_fast_path_matches_fallback(monkeypatch: pytest.MonkeyPatch) -> None:
    enc = get_encoding("o200k_base")
    text = ("decode path parity check for native fallback. " * 4096).strip()
    tokens = enc.encode(text)

    monkeypatch.setenv("TURBOTOKEN_NATIVE_DECODE_ENABLE", "1")
    monkeypatch.setenv("TURBOTOKEN_NATIVE_DECODE_MIN_TOKENS", "1")
    monkeypatch.delenv("TURBOTOKEN_NATIVE_DECODE_DISABLE", raising=False)
    fast = enc.decode_bytes(tokens)

    monkeypatch.setenv("TURBOTOKEN_NATIVE_DECODE_DISABLE", "1")
    slow = enc.decode_bytes(tokens)

    assert fast == slow == text.encode("utf-8")


def test_decode_bytes_unknown_token_keeps_value_error_semantics(monkeypatch: pytest.MonkeyPatch) -> None:
    enc = get_encoding("o200k_base")
    monkeypatch.setenv("TURBOTOKEN_NATIVE_DECODE_ENABLE", "1")
    monkeypatch.setenv("TURBOTOKEN_NATIVE_DECODE_MIN_TOKENS", "1")
    monkeypatch.delenv("TURBOTOKEN_NATIVE_DECODE_DISABLE", raising=False)
    with pytest.raises(ValueError):
        enc.decode_bytes([2_147_483_647])
