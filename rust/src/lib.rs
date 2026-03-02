//! turbotoken — the fastest BPE tokenizer on every platform (Rust binding).
//!
//! Drop-in replacement for tiktoken with identical output, powered by
//! Zig + hand-written assembly under the hood.
//!
//! # Quick start
//!
//! ```no_run
//! let enc = turbotoken::get_encoding("o200k_base").unwrap();
//! let tokens = enc.encode("hello world").unwrap();
//! let text = enc.decode(&tokens).unwrap();
//! assert_eq!(text, "hello world");
//! ```

pub mod chat;
pub mod error;
pub mod ffi;
pub mod rank_cache;
pub mod registry;

use std::ffi::CStr;
use std::path::Path;
use std::ptr;

pub use chat::{ChatMessage, ChatTemplate, ChatTemplateMode};
pub use error::TurbotokenError;
pub use registry::EncodingSpec;

/// A loaded BPE encoding, ready to encode/decode text.
///
/// `Encoding` is `Send + Sync` — it can be shared across threads.
pub struct Encoding {
    rank_payload: Vec<u8>,
    spec: &'static EncodingSpec,
}

// The rank_payload is immutable after construction and the FFI calls are thread-safe.
unsafe impl Send for Encoding {}
unsafe impl Sync for Encoding {}

/// Options for chat encoding operations.
#[derive(Debug, Clone, Default)]
pub struct ChatOptions {
    /// Chat template mode. Defaults to `TurbotokenV1` if `None`.
    pub template_mode: Option<ChatTemplateMode>,
    /// Whether to append the assistant prefix at the end.
    pub add_assistant_prefix: bool,
}

// ── Two-pass helper ──────────────────────────────────────────────────────

/// Call a native FFI function that uses the two-pass pattern:
/// - Pass 1: call with NULL output to get the required size
/// - Pass 2: allocate and call again to fill the buffer
///
/// The closure receives `(out_ptr, out_cap)` and returns the isize result.
fn call_two_pass<T: Default + Clone>(
    f: impl Fn(*mut T, usize) -> isize,
) -> Result<Vec<T>, TurbotokenError> {
    // Pass 1: query size
    let n = f(ptr::null_mut(), 0);
    if n < 0 {
        return Err(TurbotokenError::NativeError(n));
    }
    let n = n as usize;
    if n == 0 {
        return Ok(Vec::new());
    }

    // Pass 2: fill buffer
    let mut buf = vec![T::default(); n];
    let written = f(buf.as_mut_ptr(), n);
    if written < 0 {
        return Err(TurbotokenError::NativeError(written));
    }
    buf.truncate(written as usize);
    Ok(buf)
}

impl Encoding {
    /// Return the encoding name (e.g. "o200k_base").
    pub fn name(&self) -> &str {
        self.spec.name
    }

    /// Return the encoding spec.
    pub fn spec(&self) -> &EncodingSpec {
        self.spec
    }

    /// Encode text into BPE token IDs.
    pub fn encode(&self, text: &str) -> Result<Vec<u32>, TurbotokenError> {
        let text_bytes = text.as_bytes();
        call_two_pass(|out, cap| unsafe {
            ffi::turbotoken_encode_bpe_from_ranks(
                self.rank_payload.as_ptr(),
                self.rank_payload.len(),
                text_bytes.as_ptr(),
                text_bytes.len(),
                out,
                cap,
            )
        })
    }

    /// Decode BPE token IDs back to a UTF-8 string.
    pub fn decode(&self, tokens: &[u32]) -> Result<String, TurbotokenError> {
        let bytes: Vec<u8> = call_two_pass(|out, cap| unsafe {
            ffi::turbotoken_decode_bpe_from_ranks(
                self.rank_payload.as_ptr(),
                self.rank_payload.len(),
                tokens.as_ptr(),
                tokens.len(),
                out,
                cap,
            )
        })?;
        String::from_utf8(bytes)
            .map_err(|e| TurbotokenError::NativeError(-(e.utf8_error().valid_up_to() as isize)))
    }

    /// Count BPE tokens without materializing the token array.
    pub fn count(&self, text: &str) -> Result<usize, TurbotokenError> {
        let text_bytes = text.as_bytes();
        let n = unsafe {
            ffi::turbotoken_count_bpe_from_ranks(
                self.rank_payload.as_ptr(),
                self.rank_payload.len(),
                text_bytes.as_ptr(),
                text_bytes.len(),
            )
        };
        if n < 0 {
            return Err(TurbotokenError::NativeError(n));
        }
        Ok(n as usize)
    }

    /// Alias for [`count`](Self::count).
    pub fn count_tokens(&self, text: &str) -> Result<usize, TurbotokenError> {
        self.count(text)
    }

    /// Check if text is within a token limit.
    ///
    /// Returns `Some(count)` if within limit, `None` if the limit is exceeded.
    pub fn is_within_token_limit(
        &self,
        text: &str,
        limit: usize,
    ) -> Result<Option<usize>, TurbotokenError> {
        let text_bytes = text.as_bytes();
        let result = unsafe {
            ffi::turbotoken_is_within_token_limit_bpe_from_ranks(
                self.rank_payload.as_ptr(),
                self.rank_payload.len(),
                text_bytes.as_ptr(),
                text_bytes.len(),
                limit,
            )
        };
        match result {
            -1 => Err(TurbotokenError::NativeError(-1)),
            -2 => Ok(None), // limit exceeded
            n if n >= 0 => Ok(Some(n as usize)),
            other => Err(TurbotokenError::NativeError(other)),
        }
    }

    /// Encode chat messages into BPE token IDs.
    pub fn encode_chat(
        &self,
        messages: &[ChatMessage],
        options: &ChatOptions,
    ) -> Result<Vec<u32>, TurbotokenError> {
        let formatted = format_chat_messages(messages, options);
        self.encode(&formatted)
    }

    /// Count tokens for chat messages.
    pub fn count_chat(
        &self,
        messages: &[ChatMessage],
        options: &ChatOptions,
    ) -> Result<usize, TurbotokenError> {
        let formatted = format_chat_messages(messages, options);
        self.count(&formatted)
    }

    /// Check if chat messages are within a token limit.
    pub fn is_chat_within_token_limit(
        &self,
        messages: &[ChatMessage],
        limit: usize,
        options: &ChatOptions,
    ) -> Result<Option<usize>, TurbotokenError> {
        let formatted = format_chat_messages(messages, options);
        self.is_within_token_limit(&formatted, limit)
    }

    /// Encode a file's contents into BPE token IDs.
    pub fn encode_file_path(&self, path: &Path) -> Result<Vec<u32>, TurbotokenError> {
        let path_str = path.to_str().ok_or_else(|| {
            TurbotokenError::IoError(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "path is not valid UTF-8",
            ))
        })?;
        let path_bytes = path_str.as_bytes();
        call_two_pass(|out, cap| unsafe {
            ffi::turbotoken_encode_bpe_file_from_ranks(
                self.rank_payload.as_ptr(),
                self.rank_payload.len(),
                path_bytes.as_ptr(),
                path_bytes.len(),
                out,
                cap,
            )
        })
    }

    /// Count BPE tokens in a file.
    pub fn count_file_path(&self, path: &Path) -> Result<usize, TurbotokenError> {
        let path_str = path.to_str().ok_or_else(|| {
            TurbotokenError::IoError(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "path is not valid UTF-8",
            ))
        })?;
        let path_bytes = path_str.as_bytes();
        let n = unsafe {
            ffi::turbotoken_count_bpe_file_from_ranks(
                self.rank_payload.as_ptr(),
                self.rank_payload.len(),
                path_bytes.as_ptr(),
                path_bytes.len(),
            )
        };
        if n < 0 {
            return Err(TurbotokenError::NativeError(n));
        }
        Ok(n as usize)
    }

    /// Check if a file's content is within a token limit.
    pub fn is_file_path_within_token_limit(
        &self,
        path: &Path,
        limit: usize,
    ) -> Result<Option<usize>, TurbotokenError> {
        let path_str = path.to_str().ok_or_else(|| {
            TurbotokenError::IoError(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "path is not valid UTF-8",
            ))
        })?;
        let path_bytes = path_str.as_bytes();
        let result = unsafe {
            ffi::turbotoken_is_within_token_limit_bpe_file_from_ranks(
                self.rank_payload.as_ptr(),
                self.rank_payload.len(),
                path_bytes.as_ptr(),
                path_bytes.len(),
                limit,
            )
        };
        match result {
            -1 => Err(TurbotokenError::NativeError(-1)),
            -2 => Ok(None),
            n if n >= 0 => Ok(Some(n as usize)),
            other => Err(TurbotokenError::NativeError(other)),
        }
    }
}

// ── Chat formatting helper ───────────────────────────────────────────────

fn format_chat_messages(messages: &[ChatMessage], options: &ChatOptions) -> String {
    let mode = options
        .template_mode
        .unwrap_or(ChatTemplateMode::TurbotokenV1);
    let template = chat::resolve_chat_template(mode);
    let mut out = String::new();

    for msg in messages {
        out.push_str(&chat::format_chat_role(&template.message_prefix, &msg.role));
        if let Some(ref name) = msg.name {
            out.push_str(name);
            out.push('\n');
        }
        out.push_str(&msg.content);
        out.push_str(&chat::format_chat_role(&template.message_suffix, &msg.role));
    }

    if options.add_assistant_prefix {
        if let Some(ref prefix) = template.assistant_prefix {
            out.push_str(&chat::format_chat_role(prefix, "assistant"));
        }
    }

    out
}

// ── Public constructors ──────────────────────────────────────────────────

/// Load an encoding by name (e.g. "o200k_base", "cl100k_base").
///
/// Downloads the rank file on first use and caches it locally.
pub fn get_encoding(name: &str) -> Result<Encoding, TurbotokenError> {
    let spec = registry::get_encoding_spec(name)?;
    let rank_payload = rank_cache::read_rank_file(name)?;
    Ok(Encoding {
        rank_payload,
        spec,
    })
}

/// Load the encoding for a given model name (e.g. "gpt-4o", "gpt-3.5-turbo").
pub fn get_encoding_for_model(model: &str) -> Result<Encoding, TurbotokenError> {
    let enc_name = registry::model_to_encoding(model)?;
    get_encoding(&enc_name)
}

/// Return a sorted list of all supported encoding names.
pub fn list_encoding_names() -> Vec<&'static str> {
    registry::list_encoding_names()
}

/// Return the native library version string.
pub fn version() -> &'static str {
    unsafe {
        let ptr = ffi::turbotoken_version();
        if ptr.is_null() {
            return "unknown";
        }
        CStr::from_ptr(ptr).to_str().unwrap_or("unknown")
    }
}
