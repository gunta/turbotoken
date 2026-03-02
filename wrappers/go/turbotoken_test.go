package turbotoken

import (
	"sort"
	"testing"
)

func TestGetEncoding(t *testing.T) {
	for _, name := range ListEncodingNames() {
		enc, err := GetEncoding(name)
		if err != nil {
			t.Fatalf("GetEncoding(%q) error: %v", name, err)
		}
		if enc.Name() != name {
			t.Errorf("GetEncoding(%q).Name() = %q", name, enc.Name())
		}
		if enc.NVocab() <= 0 {
			t.Errorf("GetEncoding(%q).NVocab() = %d, want > 0", name, enc.NVocab())
		}
	}
}

func TestGetEncodingInvalid(t *testing.T) {
	_, err := GetEncoding("nonexistent_encoding")
	if err == nil {
		t.Fatal("GetEncoding(nonexistent) should return error")
	}
}

func TestGetEncodingForModel(t *testing.T) {
	tests := []struct {
		model    string
		encoding string
	}{
		{"gpt-4o", "o200k_base"},
		{"gpt-4", "cl100k_base"},
		{"gpt-3.5-turbo", "cl100k_base"},
		{"text-davinci-003", "p50k_base"},
		{"davinci", "r50k_base"},
		{"gpt-4o-2024-05-13", "o200k_base"},     // prefix match
		{"gpt-3.5-turbo-0125", "cl100k_base"},    // prefix match
		{"ft:gpt-4o:myorg", "o200k_base"},         // fine-tune prefix
	}
	for _, tt := range tests {
		name, err := ModelToEncodingName(tt.model)
		if err != nil {
			t.Fatalf("ModelToEncodingName(%q) error: %v", tt.model, err)
		}
		if name != tt.encoding {
			t.Errorf("ModelToEncodingName(%q) = %q, want %q", tt.model, name, tt.encoding)
		}
	}
}

func TestGetEncodingForModelInvalid(t *testing.T) {
	_, err := ModelToEncodingName("nonexistent-model-xyz")
	if err == nil {
		t.Fatal("ModelToEncodingName(nonexistent) should return error")
	}
}

func TestListEncodingNames(t *testing.T) {
	names := ListEncodingNames()
	if len(names) != 7 {
		t.Fatalf("ListEncodingNames() returned %d names, want 7", len(names))
	}
	// Verify sorted.
	if !sort.StringsAreSorted(names) {
		t.Error("ListEncodingNames() is not sorted")
	}
	// Verify expected encodings are present.
	expected := []string{"cl100k_base", "gpt2", "o200k_base", "o200k_harmony", "p50k_base", "p50k_edit", "r50k_base"}
	for i, name := range expected {
		if names[i] != name {
			t.Errorf("ListEncodingNames()[%d] = %q, want %q", i, names[i], name)
		}
	}
}

func TestEncodeDecodeRoundTrip(t *testing.T) {
	enc, err := GetEncoding("cl100k_base")
	if err != nil {
		t.Fatalf("GetEncoding error: %v", err)
	}

	texts := []string{
		"hello world",
		"The quick brown fox jumps over the lazy dog.",
		"",
		"日本語テスト",
		"hello\nworld\ttab",
		"a",
	}

	for _, text := range texts {
		tokens, err := enc.Encode(text)
		if err != nil {
			t.Fatalf("Encode(%q) error: %v", text, err)
		}

		decoded, err := enc.Decode(tokens)
		if err != nil {
			t.Fatalf("Decode error for %q: %v", text, err)
		}

		if decoded != text {
			t.Errorf("round-trip failed: Encode+Decode(%q) = %q", text, decoded)
		}
	}
}

func TestCount(t *testing.T) {
	enc, err := GetEncoding("cl100k_base")
	if err != nil {
		t.Fatalf("GetEncoding error: %v", err)
	}

	text := "hello world"
	tokens, err := enc.Encode(text)
	if err != nil {
		t.Fatalf("Encode error: %v", err)
	}

	count, err := enc.Count(text)
	if err != nil {
		t.Fatalf("Count error: %v", err)
	}

	if count != len(tokens) {
		t.Errorf("Count(%q) = %d, but Encode returned %d tokens", text, count, len(tokens))
	}

	// Test CountTokens alias.
	count2, err := enc.CountTokens(text)
	if err != nil {
		t.Fatalf("CountTokens error: %v", err)
	}
	if count2 != count {
		t.Errorf("CountTokens(%q) = %d, Count returned %d", text, count2, count)
	}
}

func TestIsWithinTokenLimit(t *testing.T) {
	enc, err := GetEncoding("cl100k_base")
	if err != nil {
		t.Fatalf("GetEncoding error: %v", err)
	}

	text := "hello world"
	count, err := enc.Count(text)
	if err != nil {
		t.Fatalf("Count error: %v", err)
	}

	// Within limit.
	n, ok, err := enc.IsWithinTokenLimit(text, count+10)
	if err != nil {
		t.Fatalf("IsWithinTokenLimit error: %v", err)
	}
	if !ok {
		t.Error("IsWithinTokenLimit should return true for sufficient limit")
	}
	if n != count {
		t.Errorf("IsWithinTokenLimit count = %d, want %d", n, count)
	}

	// Exceeds limit.
	_, ok, err = enc.IsWithinTokenLimit(text, 0)
	if err != nil {
		t.Fatalf("IsWithinTokenLimit error: %v", err)
	}
	if ok {
		t.Error("IsWithinTokenLimit should return false for limit 0")
	}
}

func TestChatTemplate(t *testing.T) {
	// Test TurbotokenV1 template.
	tmpl := ResolveChatTemplate(TurbotokenV1)
	if tmpl.MessagePrefix != "[[role:{role}]]\n" {
		t.Errorf("TurbotokenV1 MessagePrefix = %q", tmpl.MessagePrefix)
	}

	// Test ImTokens template.
	tmpl = ResolveChatTemplate(ImTokens)
	if tmpl.MessagePrefix != "<|im_start|>{role}\n" {
		t.Errorf("ImTokens MessagePrefix = %q", tmpl.MessagePrefix)
	}
}

func TestFormatChatRole(t *testing.T) {
	result := formatChatRole("[[role:{role}]]\n", "assistant")
	if result != "[[role:assistant]]\n" {
		t.Errorf("formatChatRole = %q", result)
	}
}

func TestEncodingSpecFields(t *testing.T) {
	spec, err := GetEncodingSpec("cl100k_base")
	if err != nil {
		t.Fatalf("GetEncodingSpec error: %v", err)
	}
	if spec.NVocab != 100277 {
		t.Errorf("cl100k_base NVocab = %d, want 100277", spec.NVocab)
	}
	eot, ok := spec.SpecialTokens[EndOfText]
	if !ok || eot != 100257 {
		t.Errorf("cl100k_base EndOfText = %d, ok=%v", eot, ok)
	}
}
