from turbotoken.registry import get_encoding_spec, model_to_encoding, list_encoding_names
from turbotoken.chat import resolve_chat_template, format_chat, ChatMessage, ChatOptions
from testing import assert_equal, assert_true


fn test_registry() raises:
    print("test_registry...")
    var names = list_encoding_names()
    assert_equal(len(names), 7)

    var spec = get_encoding_spec("cl100k_base")
    assert_equal(spec.name, "cl100k_base")
    assert_equal(spec.n_vocab, 100277)

    var spec2 = get_encoding_spec("o200k_base")
    assert_equal(spec2.name, "o200k_base")
    assert_equal(spec2.n_vocab, 200019)

    print("  PASS")


fn test_model_mapping() raises:
    print("test_model_mapping...")
    assert_equal(model_to_encoding("gpt-4o"), "o200k_base")
    assert_equal(model_to_encoding("gpt-4"), "cl100k_base")
    assert_equal(model_to_encoding("gpt-3.5-turbo"), "cl100k_base")
    assert_equal(model_to_encoding("davinci"), "r50k_base")
    assert_equal(model_to_encoding("gpt2"), "gpt2")

    # Prefix matches
    assert_equal(model_to_encoding("gpt-4o-2024-01-01"), "o200k_base")
    assert_equal(model_to_encoding("gpt-4-turbo-preview"), "cl100k_base")
    assert_equal(model_to_encoding("o1-preview"), "o200k_base")
    print("  PASS")


fn test_chat_template() raises:
    print("test_chat_template...")
    var t1 = resolve_chat_template("turbotoken_v1")
    assert_equal(t1.message_prefix, "<|im_start|>")
    assert_equal(t1.message_suffix, "<|im_end|>\n")

    var t2 = resolve_chat_template("im_tokens")
    assert_equal(t2.message_prefix, "")
    assert_equal(t2.message_suffix, "")

    # Test format_chat
    var messages = List[ChatMessage]()
    messages.append(ChatMessage(role="user", content="Hello"))
    var result = format_chat(messages, ChatOptions(template_mode="turbotoken_v1"))
    assert_equal(result, "<|im_start|>user\nHello<|im_end|>\n")

    # Test with assistant priming
    var result2 = format_chat(
        messages,
        ChatOptions(prime_with_assistant_response=True, template_mode="turbotoken_v1"),
    )
    assert_equal(result2, "<|im_start|>user\nHello<|im_end|>\n<|im_start|>assistant\n")

    print("  PASS")


fn main() raises:
    test_registry()
    test_model_mapping()
    test_chat_template()
    print("All tests passed!")
