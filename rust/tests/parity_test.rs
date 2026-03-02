//! Parity tests using shared/test-vectors.json.
//!
//! These tests verify that the Rust binding produces identical results
//! to all other language bindings.

use std::collections::HashMap;
use turbotoken::{get_encoding, get_encoding_for_model, TurbotokenError};

/// Parsed test vector structures.
#[derive(Debug)]
struct TestVector {
    text: String,
    #[allow(dead_code)]
    description: String,
    expected_count: Option<usize>,
}

#[derive(Debug)]
struct EncodingTestSuite {
    #[allow(dead_code)]
    n_vocab: usize,
    tests: Vec<TestVector>,
}

/// Minimal JSON parser for the test vectors file (avoids serde dependency).
fn parse_test_vectors() -> (
    HashMap<String, EncodingTestSuite>,
    Vec<String>,
    HashMap<String, String>,
) {
    let json_str =
        std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/../shared/test-vectors.json"))
            .expect("failed to read shared/test-vectors.json");

    // Use a simple approach: parse the JSON manually for the fields we need.
    // This avoids pulling in serde_json as a dev-dependency.
    let val: JsonValue = parse_json(&json_str);

    let encodings_obj = val.get("encodings").expect("missing 'encodings'");
    let mut encoding_suites = HashMap::new();

    for (enc_name, enc_val) in encodings_obj.as_object() {
        let n_vocab = enc_val.get("n_vocab").unwrap().as_usize();
        let tests_arr = enc_val.get("tests").unwrap().as_array();
        let mut tests = Vec::new();
        for t in tests_arr {
            let text = t.get("text").unwrap().as_str().to_string();
            let description = t.get("description").unwrap().as_str().to_string();
            let expected_count = t.get("expected_count").map(|v| v.as_usize());
            tests.push(TestVector {
                text,
                description,
                expected_count,
            });
        }
        encoding_suites.insert(
            enc_name.clone(),
            EncodingTestSuite { n_vocab, tests },
        );
    }

    let round_trip_arr = val.get("round_trip_texts").unwrap().as_array();
    let round_trip_texts: Vec<String> = round_trip_arr.iter().map(|v| v.as_str().to_string()).collect();

    let model_map_obj = val.get("model_to_encoding").unwrap().as_object();
    let mut model_map = HashMap::new();
    for (k, v) in model_map_obj {
        model_map.insert(k.clone(), v.as_str().to_string());
    }

    (encoding_suites, round_trip_texts, model_map)
}

// ── Tests ────────────────────────────────────────────────────────────────

#[test]
fn test_round_trip_all_encodings() -> Result<(), TurbotokenError> {
    let (suites, _, _) = parse_test_vectors();

    for (enc_name, suite) in &suites {
        let enc = get_encoding(enc_name)?;

        for tv in &suite.tests {
            let tokens = enc.encode(&tv.text)?;

            if let Some(expected) = tv.expected_count {
                assert_eq!(
                    tokens.len(),
                    expected,
                    "{enc_name}: encode({:?}) expected {expected} tokens, got {}",
                    tv.text,
                    tokens.len()
                );
            }

            // Round-trip
            if !tv.text.is_empty() {
                let decoded = enc.decode(&tokens)?;
                assert_eq!(
                    decoded, tv.text,
                    "{enc_name}: round-trip failed for {:?}",
                    tv.text
                );
            }

            // count() must match encode().len()
            let count = enc.count(&tv.text)?;
            assert_eq!(
                count,
                tokens.len(),
                "{enc_name}: count({:?}) = {count}, but encode().len() = {}",
                tv.text,
                tokens.len()
            );
        }
    }
    Ok(())
}

#[test]
fn test_round_trip_texts() -> Result<(), TurbotokenError> {
    let (_, round_trip_texts, _) = parse_test_vectors();
    let enc = get_encoding("o200k_base")?;

    for text in &round_trip_texts {
        let tokens = enc.encode(text)?;
        let decoded = enc.decode(&tokens)?;
        assert_eq!(&decoded, text, "round-trip failed for: {text:?}");
    }
    Ok(())
}

#[test]
fn test_model_to_encoding_mapping() -> Result<(), TurbotokenError> {
    let (_, _, model_map) = parse_test_vectors();

    for (model, expected_enc) in &model_map {
        let enc = get_encoding_for_model(model)?;
        assert_eq!(
            enc.name(),
            expected_enc,
            "model {model:?} should use encoding {expected_enc:?}, got {:?}",
            enc.name()
        );
    }
    Ok(())
}

// ── Minimal JSON parser (no serde dependency) ────────────────────────────

#[derive(Debug, Clone)]
enum JsonValue {
    Null,
    Bool(bool),
    Number(f64),
    Str(String),
    Array(Vec<JsonValue>),
    Object(Vec<(String, JsonValue)>),
}

impl JsonValue {
    fn get(&self, key: &str) -> Option<&JsonValue> {
        match self {
            JsonValue::Object(pairs) => pairs.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    fn as_object(&self) -> &[(String, JsonValue)] {
        match self {
            JsonValue::Object(pairs) => pairs,
            _ => panic!("expected object"),
        }
    }

    fn as_array(&self) -> &[JsonValue] {
        match self {
            JsonValue::Array(arr) => arr,
            _ => panic!("expected array"),
        }
    }

    fn as_str(&self) -> &str {
        match self {
            JsonValue::Str(s) => s,
            _ => panic!("expected string"),
        }
    }

    fn as_usize(&self) -> usize {
        match self {
            JsonValue::Number(n) => *n as usize,
            _ => panic!("expected number"),
        }
    }
}

struct JsonParser<'a> {
    input: &'a [u8],
    pos: usize,
}

impl<'a> JsonParser<'a> {
    fn new(input: &'a str) -> Self {
        Self {
            input: input.as_bytes(),
            pos: 0,
        }
    }

    fn skip_ws(&mut self) {
        while self.pos < self.input.len()
            && matches!(self.input[self.pos], b' ' | b'\t' | b'\n' | b'\r')
        {
            self.pos += 1;
        }
    }

    fn peek(&mut self) -> u8 {
        self.skip_ws();
        self.input[self.pos]
    }

    fn consume(&mut self, expected: u8) {
        self.skip_ws();
        assert_eq!(self.input[self.pos], expected);
        self.pos += 1;
    }

    fn parse_value(&mut self) -> JsonValue {
        self.skip_ws();
        match self.input[self.pos] {
            b'"' => JsonValue::Str(self.parse_string()),
            b'{' => self.parse_object(),
            b'[' => self.parse_array(),
            b't' => {
                self.pos += 4;
                JsonValue::Bool(true)
            }
            b'f' => {
                self.pos += 5;
                JsonValue::Bool(false)
            }
            b'n' => {
                self.pos += 4;
                JsonValue::Null
            }
            _ => self.parse_number(),
        }
    }

    fn parse_string(&mut self) -> String {
        self.consume(b'"');
        let mut s = String::new();
        loop {
            let ch = self.input[self.pos];
            self.pos += 1;
            match ch {
                b'"' => return s,
                b'\\' => {
                    let esc = self.input[self.pos];
                    self.pos += 1;
                    match esc {
                        b'"' => s.push('"'),
                        b'\\' => s.push('\\'),
                        b'/' => s.push('/'),
                        b'n' => s.push('\n'),
                        b'r' => s.push('\r'),
                        b't' => s.push('\t'),
                        b'u' => {
                            let hex: String = (0..4)
                                .map(|_| {
                                    let c = self.input[self.pos] as char;
                                    self.pos += 1;
                                    c
                                })
                                .collect();
                            let cp = u32::from_str_radix(&hex, 16).unwrap();
                            // Handle surrogate pairs
                            if (0xD800..=0xDBFF).contains(&cp) {
                                // High surrogate — expect \uXXXX low surrogate
                                if self.pos + 5 < self.input.len()
                                    && self.input[self.pos] == b'\\'
                                    && self.input[self.pos + 1] == b'u'
                                {
                                    self.pos += 2;
                                    let hex2: String = (0..4)
                                        .map(|_| {
                                            let c = self.input[self.pos] as char;
                                            self.pos += 1;
                                            c
                                        })
                                        .collect();
                                    let low = u32::from_str_radix(&hex2, 16).unwrap();
                                    let full =
                                        0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                                    if let Some(c) = char::from_u32(full) {
                                        s.push(c);
                                    }
                                }
                            } else if let Some(c) = char::from_u32(cp) {
                                s.push(c);
                            }
                        }
                        _ => {
                            s.push('\\');
                            s.push(esc as char);
                        }
                    }
                }
                _ => s.push(ch as char),
            }
        }
    }

    fn parse_number(&mut self) -> JsonValue {
        let start = self.pos;
        if self.input[self.pos] == b'-' {
            self.pos += 1;
        }
        while self.pos < self.input.len() && self.input[self.pos].is_ascii_digit() {
            self.pos += 1;
        }
        if self.pos < self.input.len() && self.input[self.pos] == b'.' {
            self.pos += 1;
            while self.pos < self.input.len() && self.input[self.pos].is_ascii_digit() {
                self.pos += 1;
            }
        }
        if self.pos < self.input.len() && (self.input[self.pos] == b'e' || self.input[self.pos] == b'E') {
            self.pos += 1;
            if self.pos < self.input.len() && (self.input[self.pos] == b'+' || self.input[self.pos] == b'-') {
                self.pos += 1;
            }
            while self.pos < self.input.len() && self.input[self.pos].is_ascii_digit() {
                self.pos += 1;
            }
        }
        let s = std::str::from_utf8(&self.input[start..self.pos]).unwrap();
        JsonValue::Number(s.parse().unwrap())
    }

    fn parse_object(&mut self) -> JsonValue {
        self.consume(b'{');
        let mut pairs = Vec::new();
        if self.peek() != b'}' {
            loop {
                let key = self.parse_string();
                self.consume(b':');
                let val = self.parse_value();
                pairs.push((key, val));
                if self.peek() == b',' {
                    self.consume(b',');
                } else {
                    break;
                }
            }
        }
        self.consume(b'}');
        JsonValue::Object(pairs)
    }

    fn parse_array(&mut self) -> JsonValue {
        self.consume(b'[');
        let mut items = Vec::new();
        if self.peek() != b']' {
            loop {
                items.push(self.parse_value());
                if self.peek() == b',' {
                    self.consume(b',');
                } else {
                    break;
                }
            }
        }
        self.consume(b']');
        JsonValue::Array(items)
    }
}

fn parse_json(input: &str) -> JsonValue {
    let mut parser = JsonParser::new(input);
    parser.parse_value()
}
