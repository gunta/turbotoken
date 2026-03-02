//! Basic encode / decode / count tests using o200k_base.
//!
//! These tests require the native libturbotoken to be linked.
//! Build with: TURBOTOKEN_NATIVE_LIB=../zig-out/lib cargo test

use turbotoken::{get_encoding, list_encoding_names, TurbotokenError};

#[test]
fn test_encode_hello_world() -> Result<(), TurbotokenError> {
    let enc = get_encoding("o200k_base")?;
    let tokens = enc.encode("hello world")?;
    assert!(!tokens.is_empty(), "encoding 'hello world' should produce tokens");
    Ok(())
}

#[test]
fn test_decode_round_trip() -> Result<(), TurbotokenError> {
    let enc = get_encoding("o200k_base")?;
    let text = "hello world";
    let tokens = enc.encode(text)?;
    let decoded = enc.decode(&tokens)?;
    assert_eq!(decoded, text, "decode(encode(text)) must equal text");
    Ok(())
}

#[test]
fn test_count_matches_encode_len() -> Result<(), TurbotokenError> {
    let enc = get_encoding("o200k_base")?;
    let text = "The quick brown fox jumps over the lazy dog";
    let tokens = enc.encode(text)?;
    let count = enc.count(text)?;
    assert_eq!(count, tokens.len(), "count() must match encode().len()");
    Ok(())
}

#[test]
fn test_count_tokens_alias() -> Result<(), TurbotokenError> {
    let enc = get_encoding("o200k_base")?;
    let text = "hello";
    assert_eq!(enc.count(text)?, enc.count_tokens(text)?);
    Ok(())
}

#[test]
fn test_empty_string() -> Result<(), TurbotokenError> {
    let enc = get_encoding("o200k_base")?;
    let tokens = enc.encode("")?;
    assert!(tokens.is_empty(), "empty string should produce zero tokens");
    assert_eq!(enc.count("")?, 0);
    Ok(())
}

#[test]
fn test_is_within_token_limit() -> Result<(), TurbotokenError> {
    let enc = get_encoding("o200k_base")?;
    let text = "hello world";
    let count = enc.count(text)?;

    // Within limit
    let result = enc.is_within_token_limit(text, count + 10)?;
    assert!(result.is_some());
    assert_eq!(result.unwrap(), count);

    // At exact limit
    let result = enc.is_within_token_limit(text, count)?;
    assert!(result.is_some());

    // Below limit
    if count > 0 {
        let result = enc.is_within_token_limit(text, 0)?;
        assert!(result.is_none(), "should exceed limit of 0");
    }

    Ok(())
}

#[test]
fn test_list_encoding_names() {
    let names = list_encoding_names();
    assert!(names.contains(&"o200k_base"));
    assert!(names.contains(&"cl100k_base"));
    assert!(names.contains(&"p50k_base"));
    assert!(names.contains(&"r50k_base"));
    assert!(names.contains(&"gpt2"));
    assert!(names.contains(&"p50k_edit"));
    assert!(names.contains(&"o200k_harmony"));
    assert_eq!(names.len(), 7);
}

#[test]
fn test_encoding_name_accessor() -> Result<(), TurbotokenError> {
    let enc = get_encoding("cl100k_base")?;
    assert_eq!(enc.name(), "cl100k_base");
    Ok(())
}

#[test]
fn test_unicode_round_trip() -> Result<(), TurbotokenError> {
    let enc = get_encoding("o200k_base")?;
    for text in &[
        "hello world",
        "The quick brown fox jumps over the lazy dog",
        "\u{1f389}\u{1f680}\u{1f4bb}", // emoji
        "\u{65e5}\u{672c}\u{8a9e}\u{30c6}\u{30b9}\u{30c8}", // CJK
        "def hello():\n    print('world')\n",
        "   ",
        "a",
    ] {
        let tokens = enc.encode(text)?;
        let decoded = enc.decode(&tokens)?;
        assert_eq!(&decoded, text, "round-trip failed for: {text:?}");
    }
    Ok(())
}
