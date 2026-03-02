using Test
using TurboToken

@testset "TurboToken" begin

    @testset "Registry" begin
        @testset "list_encoding_names returns 7 encodings" begin
            names = list_encoding_names()
            @test length(names) == 7
            @test "cl100k_base" in names
            @test "o200k_base" in names
            @test "r50k_base" in names
            @test "p50k_base" in names
            @test "p50k_edit" in names
            @test "gpt2" in names
            @test "o200k_harmony" in names
            @test issorted(names)
        end

        @testset "get_encoding_spec works" begin
            spec = TurboToken.get_encoding_spec("cl100k_base")
            @test spec.name == "cl100k_base"
            @test spec.n_vocab == 100277
            @test haskey(spec.special_tokens, "<|endoftext|>")
            @test spec.special_tokens["<|endoftext|>"] == 100257
        end

        @testset "get_encoding_spec unknown throws" begin
            @test_throws TurboToken.UnknownEncodingError TurboToken.get_encoding_spec("nonexistent")
        end

        @testset "model_to_encoding resolves exact" begin
            @test TurboToken.model_to_encoding("gpt-4") == "cl100k_base"
            @test TurboToken.model_to_encoding("gpt-4o") == "o200k_base"
            @test TurboToken.model_to_encoding("o1") == "o200k_base"
            @test TurboToken.model_to_encoding("gpt2") == "gpt2"
        end

        @testset "model_to_encoding resolves prefix" begin
            @test TurboToken.model_to_encoding("gpt-4o-2024-01-01") == "o200k_base"
            @test TurboToken.model_to_encoding("gpt-4-turbo-preview") == "cl100k_base"
            @test TurboToken.model_to_encoding("o1-preview") == "o200k_base"
        end

        @testset "model_to_encoding unknown throws" begin
            @test_throws ErrorException TurboToken.model_to_encoding("nonexistent-model")
        end
    end

    @testset "Chat" begin
        @testset "ChatMessage construction" begin
            msg = TurboToken.ChatMessage("user", "hello")
            @test msg.role == "user"
            @test msg.content == "hello"
            @test msg.name === nothing
        end

        @testset "ChatMessage with name" begin
            msg = TurboToken.ChatMessage("user", "Alice", "hello")
            @test msg.name == "Alice"
        end

        @testset "resolve_chat_template" begin
            template = TurboToken.resolve_chat_template(TurboToken.turbotoken_v1)
            @test template.message_prefix == "<|im_start|>"
            @test template.message_suffix == "<|im_end|>\n"
            @test template.assistant_prefix == "<|im_start|>assistant\n"
        end

        @testset "format_chat_messages" begin
            msgs = [
                TurboToken.ChatMessage("user", "hello"),
                TurboToken.ChatMessage("assistant", "hi there"),
            ]
            text = TurboToken.format_chat_messages(msgs)
            @test contains(text, "user")
            @test contains(text, "hello")
            @test contains(text, "assistant")
            @test contains(text, "hi there")
        end
    end

    @testset "Encoding (native lib)" begin
        native_available = try
            TurboToken.ffi_version()
            true
        catch
            false
        end

        if native_available
            @testset "encode/decode round trip" begin
                enc = get_encoding("cl100k_base")
                text = "hello world"
                tokens = encode(enc, text)
                @test length(tokens) > 0
                decoded = decode(enc, tokens)
                @test decoded == text
            end

            @testset "count_tokens" begin
                enc = get_encoding("cl100k_base")
                text = "hello world"
                n = count(enc, text)
                tokens = encode(enc, text)
                @test n == length(tokens)
            end

            @testset "is_within_token_limit" begin
                enc = get_encoding("cl100k_base")
                text = "hello"
                result = is_within_token_limit(enc, text, 1000)
                @test result !== nothing
                @test result > 0
            end

            @testset "version" begin
                v = version()
                @test isa(v, String)
                @test !isempty(v)
            end
        else
            @info "Native library not available, skipping encode/decode tests"
        end
    end

end
