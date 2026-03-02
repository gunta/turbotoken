module TurboToken.Tests

open Xunit
open FsUnit.Xunit
open TurboToken.Registry
open TurboToken.Chat

[<Fact>]
let ``list encoding names returns 7`` () =
    let names = listEncodingNames ()
    names |> List.length |> should equal 7
    names |> should contain "cl100k_base"
    names |> should contain "o200k_base"
    names |> should contain "r50k_base"
    names |> should contain "p50k_base"
    names |> should contain "gpt2"
    names |> should contain "p50k_edit"
    names |> should contain "o200k_harmony"

[<Fact>]
let ``get encoding spec works`` () =
    match getEncodingSpec "cl100k_base" with
    | Ok spec ->
        spec.Name |> should equal "cl100k_base"
        spec.NVocab |> should equal 100277
        spec.SpecialTokens |> Map.find "<|endoftext|>" |> should equal 100257
    | Error e -> failwith e

[<Fact>]
let ``get encoding spec unknown returns error`` () =
    match getEncodingSpec "nonexistent" with
    | Ok _ -> failwith "Should have returned error"
    | Error e -> e |> should haveSubstring "Unknown encoding"

[<Fact>]
let ``model to encoding resolves exact`` () =
    modelToEncoding "gpt-4o" |> should equal (Ok "o200k_base")
    modelToEncoding "gpt-4" |> should equal (Ok "cl100k_base")
    modelToEncoding "gpt-3.5-turbo" |> should equal (Ok "cl100k_base")
    modelToEncoding "davinci" |> should equal (Ok "r50k_base")
    modelToEncoding "gpt2" |> should equal (Ok "gpt2")

[<Fact>]
let ``model to encoding resolves prefix`` () =
    modelToEncoding "gpt-4o-2024-01-01" |> should equal (Ok "o200k_base")
    modelToEncoding "gpt-4-turbo-preview" |> should equal (Ok "cl100k_base")
    modelToEncoding "o1-preview" |> should equal (Ok "o200k_base")

[<Fact>]
let ``model to encoding unknown returns error`` () =
    match modelToEncoding "totally-unknown-model" with
    | Ok _ -> failwith "Should have returned error"
    | Error e -> e |> should haveSubstring "Could not automatically map"

[<Fact>]
let ``chat template resolution turbotoken v1`` () =
    let t = resolveChatTemplate TurbotokenV1
    t.MessagePrefix |> should equal "<|im_start|>"
    t.MessageSuffix |> should equal "<|im_end|>\n"
    t.AssistantPrefix |> should equal (Some "<|im_start|>assistant\n")

[<Fact>]
let ``chat template resolution im tokens`` () =
    let t = resolveChatTemplate ImTokens
    t.MessagePrefix |> should equal ""
    t.MessageSuffix |> should equal ""
    t.AssistantPrefix |> should equal None

[<Fact>]
let ``format chat turbotoken v1`` () =
    let messages = [ { Role = "user"; Name = None; Content = "Hello" } ]
    let result = formatChat messages defaultChatOptions
    result |> should equal "<|im_start|>user\nHello<|im_end|>\n"

[<Fact>]
let ``format chat with name`` () =
    let messages = [ { Role = "user"; Name = Some "Alice"; Content = "Hi" } ]
    let result = formatChat messages defaultChatOptions
    result |> should equal "<|im_start|>user name=Alice\nHi<|im_end|>\n"

[<Fact>]
let ``format chat with assistant priming`` () =
    let messages = [ { Role = "user"; Name = None; Content = "Hello" } ]
    let options = { PrimeWithAssistantResponse = true; Template = TurbotokenV1 }
    let result = formatChat messages options
    result |> should equal "<|im_start|>user\nHello<|im_end|>\n<|im_start|>assistant\n"

[<Fact>]
let ``version returns non-empty`` () =
    let v = Api.version ()
    v |> should not' (be EmptyString)
