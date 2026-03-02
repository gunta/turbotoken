module TurboToken.Registry

type EncodingSpec =
    { Name: string
      RankFileUrl: string
      PatStr: string
      SpecialTokens: Map<string, int>
      NVocab: int }

let private endOfText = "<|endoftext|>"
let private fimPrefix = "<|fim_prefix|>"
let private fimMiddle = "<|fim_middle|>"
let private fimSuffix = "<|fim_suffix|>"
let private endOfPrompt = "<|endofprompt|>"

let private r50kPatStr =
    @"'(?:[sdmt]|ll|ve|re)| ?\p{L}++| ?\p{N}++| ?[^\s\p{L}\p{N}]++|\s++$|\s+(?!\S)|\s"

let private cl100kPatStr =
    @"'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}++|\p{N}{1,3}+| ?[^\s\p{L}\p{N}]++[\r\n]*+|\s++$|\s*[\r\n]|\s+(?!\S)|\s"

let private o200kPatStr =
    System.String.Join("|", [|
        @"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?"
        @"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?"
        @"\p{N}{1,3}"
        @" ?[^\s\p{L}\p{N}]+[\r\n/]*"
        @"\s*[\r\n]+"
        @"\s+(?!\S)"
        @"\s+"
    |])

let private encodingSpecs : Map<string, EncodingSpec> =
    Map.ofList [
        "o200k_base",
            { Name = "o200k_base"
              RankFileUrl = "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken"
              PatStr = o200kPatStr
              SpecialTokens = Map.ofList [ endOfText, 199999; endOfPrompt, 200018 ]
              NVocab = 200019 }
        "cl100k_base",
            { Name = "cl100k_base"
              RankFileUrl = "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken"
              PatStr = cl100kPatStr
              SpecialTokens = Map.ofList [ endOfText, 100257; fimPrefix, 100258; fimMiddle, 100259; fimSuffix, 100260; endOfPrompt, 100276 ]
              NVocab = 100277 }
        "p50k_base",
            { Name = "p50k_base"
              RankFileUrl = "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken"
              PatStr = r50kPatStr
              SpecialTokens = Map.ofList [ endOfText, 50256 ]
              NVocab = 50281 }
        "r50k_base",
            { Name = "r50k_base"
              RankFileUrl = "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken"
              PatStr = r50kPatStr
              SpecialTokens = Map.ofList [ endOfText, 50256 ]
              NVocab = 50257 }
        "gpt2",
            { Name = "gpt2"
              RankFileUrl = "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken"
              PatStr = r50kPatStr
              SpecialTokens = Map.ofList [ endOfText, 50256 ]
              NVocab = 50257 }
        "p50k_edit",
            { Name = "p50k_edit"
              RankFileUrl = "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken"
              PatStr = r50kPatStr
              SpecialTokens = Map.ofList [ endOfText, 50256 ]
              NVocab = 50281 }
        "o200k_harmony",
            { Name = "o200k_harmony"
              RankFileUrl = "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken"
              PatStr = o200kPatStr
              SpecialTokens = Map.ofList [ endOfText, 199999; endOfPrompt, 200018 ]
              NVocab = 200019 }
    ]

let private modelToEncodingMap : Map<string, string> =
    Map.ofList [
        "o1", "o200k_base"
        "o3", "o200k_base"
        "o4-mini", "o200k_base"
        "gpt-5", "o200k_base"
        "gpt-4.1", "o200k_base"
        "gpt-4o", "o200k_base"
        "gpt-4o-mini", "o200k_base"
        "gpt-4.1-mini", "o200k_base"
        "gpt-4.1-nano", "o200k_base"
        "gpt-oss-120b", "o200k_harmony"
        "gpt-4", "cl100k_base"
        "gpt-3.5-turbo", "cl100k_base"
        "gpt-3.5", "cl100k_base"
        "gpt-35-turbo", "cl100k_base"
        "davinci-002", "cl100k_base"
        "babbage-002", "cl100k_base"
        "text-embedding-ada-002", "cl100k_base"
        "text-embedding-3-small", "cl100k_base"
        "text-embedding-3-large", "cl100k_base"
        "text-davinci-003", "p50k_base"
        "text-davinci-002", "p50k_base"
        "text-davinci-001", "r50k_base"
        "text-curie-001", "r50k_base"
        "text-babbage-001", "r50k_base"
        "text-ada-001", "r50k_base"
        "davinci", "r50k_base"
        "curie", "r50k_base"
        "babbage", "r50k_base"
        "ada", "r50k_base"
        "code-davinci-002", "p50k_base"
        "code-davinci-001", "p50k_base"
        "code-cushman-002", "p50k_base"
        "code-cushman-001", "p50k_base"
        "davinci-codex", "p50k_base"
        "cushman-codex", "p50k_base"
        "text-davinci-edit-001", "p50k_edit"
        "code-davinci-edit-001", "p50k_edit"
        "text-similarity-davinci-001", "r50k_base"
        "text-similarity-curie-001", "r50k_base"
        "text-similarity-babbage-001", "r50k_base"
        "text-similarity-ada-001", "r50k_base"
        "text-search-davinci-doc-001", "r50k_base"
        "text-search-curie-doc-001", "r50k_base"
        "text-search-babbage-doc-001", "r50k_base"
        "text-search-ada-doc-001", "r50k_base"
        "code-search-babbage-code-001", "r50k_base"
        "code-search-ada-code-001", "r50k_base"
        "gpt2", "gpt2"
        "gpt-2", "r50k_base"
    ]

let private modelPrefixToEncoding : (string * string) list =
    [ "o1-", "o200k_base"
      "o3-", "o200k_base"
      "o4-mini-", "o200k_base"
      "gpt-5-", "o200k_base"
      "gpt-4.5-", "o200k_base"
      "gpt-4.1-", "o200k_base"
      "chatgpt-4o-", "o200k_base"
      "gpt-4o-", "o200k_base"
      "gpt-oss-", "o200k_harmony"
      "gpt-4-", "cl100k_base"
      "gpt-3.5-turbo-", "cl100k_base"
      "gpt-35-turbo-", "cl100k_base"
      "ft:gpt-4o", "o200k_base"
      "ft:gpt-4", "cl100k_base"
      "ft:gpt-3.5-turbo", "cl100k_base"
      "ft:davinci-002", "cl100k_base"
      "ft:babbage-002", "cl100k_base" ]

let getEncodingSpec (name: string) : Result<EncodingSpec, string> =
    match Map.tryFind name encodingSpecs with
    | Some spec -> Ok spec
    | None ->
        let supported = listEncodingNames () |> String.concat ", "
        Error (sprintf "Unknown encoding '%s'. Supported: %s" name supported)

and listEncodingNames () : string list =
    encodingSpecs |> Map.toList |> List.map fst |> List.sort

let modelToEncoding (model: string) : Result<string, string> =
    match Map.tryFind model modelToEncodingMap with
    | Some enc -> Ok enc
    | None ->
        match modelPrefixToEncoding |> List.tryFind (fun (prefix, _) -> model.StartsWith(prefix)) with
        | Some (_, enc) -> Ok enc
        | None ->
            Error (sprintf "Could not automatically map '%s' to an encoding. Use getEncoding(name) to select one explicitly." model)
