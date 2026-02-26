from __future__ import annotations

import pytest

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
