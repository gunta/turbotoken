from collections import List, Optional
from memory import UnsafePointer
from .ffi import (
    ffi_encode_bpe,
    ffi_decode_bpe,
    ffi_count_bpe,
    ffi_is_within_token_limit,
    ffi_encode_bpe_file,
    ffi_count_bpe_file,
    ffi_is_within_token_limit_file,
)
from .registry import EncodingSpec
from .chat import ChatMessage, ChatOptions, format_chat


struct Encoding:
    var name: String
    var rank_payload: List[UInt8]
    var _spec: EncodingSpec

    fn __init__(out self, name: String, spec: EncodingSpec, rank_payload: List[UInt8]):
        self.name = name
        self._spec = spec
        self.rank_payload = rank_payload

    fn encode(self, text: String) raises -> List[UInt32]:
        var text_bytes = text.as_bytes()
        var rank_ptr = self.rank_payload.unsafe_ptr()
        var text_ptr = text_bytes.unsafe_ptr()

        # Size query pass
        var size = ffi_encode_bpe(
            rank_ptr,
            len(self.rank_payload),
            text_ptr,
            len(text_bytes),
            UnsafePointer[UInt32](),
            0,
        )
        if size < 0:
            raise Error("encode returned error code " + str(size))
        if size == 0:
            return List[UInt32]()

        # Fill pass
        var out = List[UInt32](capacity=size)
        out.resize(size, 0)
        var written = ffi_encode_bpe(
            rank_ptr,
            len(self.rank_payload),
            text_ptr,
            len(text_bytes),
            out.unsafe_ptr(),
            size,
        )
        if written < 0:
            raise Error("encode fill returned error code " + str(written))
        if written < size:
            out.resize(written, 0)
        return out

    fn decode(self, tokens: List[UInt32]) raises -> String:
        var rank_ptr = self.rank_payload.unsafe_ptr()
        var tok_ptr = tokens.unsafe_ptr()

        # Size query pass
        var size = ffi_decode_bpe(
            rank_ptr,
            len(self.rank_payload),
            tok_ptr,
            len(tokens),
            UnsafePointer[UInt8](),
            0,
        )
        if size < 0:
            raise Error("decode returned error code " + str(size))
        if size == 0:
            return ""

        # Fill pass
        var out = List[UInt8](capacity=size)
        out.resize(size, 0)
        var written = ffi_decode_bpe(
            rank_ptr,
            len(self.rank_payload),
            tok_ptr,
            len(tokens),
            out.unsafe_ptr(),
            size,
        )
        if written < 0:
            raise Error("decode fill returned error code " + str(written))
        if written < size:
            out.resize(written, 0)
        return String(out)

    fn count(self, text: String) raises -> Int:
        var text_bytes = text.as_bytes()
        var result = ffi_count_bpe(
            self.rank_payload.unsafe_ptr(),
            len(self.rank_payload),
            text_bytes.unsafe_ptr(),
            len(text_bytes),
        )
        if result < 0:
            raise Error("count returned error code " + str(result))
        return result

    fn count_tokens(self, text: String) raises -> Int:
        return self.count(text)

    fn is_within_token_limit(self, text: String, limit: Int) raises -> Optional[Int]:
        var text_bytes = text.as_bytes()
        var result = ffi_is_within_token_limit(
            self.rank_payload.unsafe_ptr(),
            len(self.rank_payload),
            text_bytes.unsafe_ptr(),
            len(text_bytes),
            limit,
        )
        if result == -2:
            return None
        if result < 0:
            raise Error("is_within_token_limit returned error code " + str(result))
        return result

    fn encode_chat(
        self, messages: List[ChatMessage], options: ChatOptions = ChatOptions()
    ) raises -> List[UInt32]:
        var text = format_chat(messages, options)
        return self.encode(text)

    fn count_chat(
        self, messages: List[ChatMessage], options: ChatOptions = ChatOptions()
    ) raises -> Int:
        var text = format_chat(messages, options)
        return self.count(text)

    fn encode_file_path(self, path: String) raises -> List[UInt32]:
        var path_bytes = path.as_bytes()
        var rank_ptr = self.rank_payload.unsafe_ptr()
        var path_ptr = path_bytes.unsafe_ptr()

        # Size query
        var size = ffi_encode_bpe_file(
            rank_ptr,
            len(self.rank_payload),
            path_ptr,
            len(path_bytes),
            UnsafePointer[UInt32](),
            0,
        )
        if size < 0:
            raise Error("encode_file_path returned error code " + str(size))
        if size == 0:
            return List[UInt32]()

        # Fill
        var out = List[UInt32](capacity=size)
        out.resize(size, 0)
        var written = ffi_encode_bpe_file(
            rank_ptr,
            len(self.rank_payload),
            path_ptr,
            len(path_bytes),
            out.unsafe_ptr(),
            size,
        )
        if written < 0:
            raise Error("encode_file_path fill returned error code " + str(written))
        if written < size:
            out.resize(written, 0)
        return out

    fn count_file_path(self, path: String) raises -> Int:
        var path_bytes = path.as_bytes()
        var result = ffi_count_bpe_file(
            self.rank_payload.unsafe_ptr(),
            len(self.rank_payload),
            path_bytes.unsafe_ptr(),
            len(path_bytes),
        )
        if result < 0:
            raise Error("count_file_path returned error code " + str(result))
        return result
