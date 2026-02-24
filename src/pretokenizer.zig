pub fn estimateTokenBound(text: []const u8) usize {
    // Placeholder heuristic until SIMD pre-tokenizer is implemented.
    return if (text.len == 0) 0 else (text.len + 3) / 4;
}
