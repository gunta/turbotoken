local turbotoken = require("turbotoken")
local registry = require("turbotoken.registry")

describe("turbotoken", function()
    describe("encode/decode round trip", function()
        it("should encode and decode back to the original text", function()
            local enc = turbotoken.get_encoding("cl100k_base")
            local text = "hello world"
            local tokens = enc:encode(text)

            assert.is_table(tokens)
            assert.is_true(#tokens > 0)

            local decoded = enc:decode(tokens)
            assert.are.equal(text, decoded)
        end)

        it("should handle empty string", function()
            local enc = turbotoken.get_encoding("cl100k_base")
            local tokens = enc:encode("")
            assert.is_table(tokens)
            assert.are.equal(0, #tokens)

            local decoded = enc:decode(tokens)
            assert.are.equal("", decoded)
        end)

        it("should handle unicode text", function()
            local enc = turbotoken.get_encoding("cl100k_base")
            local text = "Hello, world! \xF0\x9F\x8C\x8D"
            local tokens = enc:encode(text)
            local decoded = enc:decode(tokens)
            assert.are.equal(text, decoded)
        end)
    end)

    describe("count", function()
        it("should count tokens correctly", function()
            local enc = turbotoken.get_encoding("cl100k_base")
            local text = "hello world"
            local count = enc:count(text)

            assert.is_number(count)
            assert.is_true(count > 0)
            assert.are.equal(#enc:encode(text), count)
        end)

        it("count_tokens should be an alias for count", function()
            local enc = turbotoken.get_encoding("cl100k_base")
            local text = "hello world"
            assert.are.equal(enc:count(text), enc:count_tokens(text))
        end)
    end)

    describe("get_encoding", function()
        it("should return an encoding with correct metadata", function()
            local enc = turbotoken.get_encoding("o200k_base")
            assert.are.equal("o200k_base", enc:name())
            assert.are.equal(200019, enc:n_vocab())
        end)

        it("should error on unknown encoding", function()
            assert.has_error(function()
                turbotoken.get_encoding("nonexistent_encoding")
            end)
        end)
    end)

    describe("get_encoding_for_model", function()
        it("should resolve model to correct encoding", function()
            local enc = turbotoken.get_encoding_for_model("gpt-4o")
            assert.are.equal("o200k_base", enc:name())
        end)

        it("should error on unknown model", function()
            assert.has_error(function()
                turbotoken.get_encoding_for_model("totally-unknown-model")
            end)
        end)
    end)

    describe("list_encoding_names", function()
        it("should return a sorted list of encoding names", function()
            local names = turbotoken.list_encoding_names()
            assert.is_table(names)
            assert.is_true(#names >= 7)

            -- Check some known encodings are present
            local has_cl100k = false
            local has_o200k = false
            for _, name in ipairs(names) do
                if name == "cl100k_base" then has_cl100k = true end
                if name == "o200k_base" then has_o200k = true end
            end
            assert.is_true(has_cl100k)
            assert.is_true(has_o200k)
        end)
    end)

    describe("registry", function()
        it("should resolve model to encoding via exact match", function()
            assert.are.equal("o200k_base", registry.model_to_encoding("gpt-4o"))
            assert.are.equal("cl100k_base", registry.model_to_encoding("gpt-4"))
            assert.are.equal("r50k_base", registry.model_to_encoding("davinci"))
        end)

        it("should resolve model to encoding via prefix match", function()
            assert.are.equal("o200k_base", registry.model_to_encoding("gpt-4o-2024-01-01"))
            assert.are.equal("cl100k_base", registry.model_to_encoding("gpt-4-turbo-preview"))
        end)

        it("should error on unknown model", function()
            assert.has_error(function()
                registry.model_to_encoding("totally-unknown-model")
            end)
        end)
    end)

    describe("is_within_token_limit", function()
        it("should return count when within limit", function()
            local enc = turbotoken.get_encoding("cl100k_base")
            local result = enc:is_within_token_limit("hello world", 1000)
            assert.is_number(result)
            assert.is_true(result > 0)
        end)

        it("should return nil when limit exceeded", function()
            local enc = turbotoken.get_encoding("cl100k_base")
            local result = enc:is_within_token_limit("hello world", 0)
            assert.is_nil(result)
        end)
    end)
end)
