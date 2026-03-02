module TurboToken.Chat

open System.Text

type ChatMessage =
    { Role: string
      Name: string option
      Content: string }

type ChatTemplate =
    { MessagePrefix: string
      MessageSuffix: string
      AssistantPrefix: string option }

type ChatTemplateMode =
    | TurbotokenV1
    | ImTokens

type ChatOptions =
    { PrimeWithAssistantResponse: bool
      Template: ChatTemplateMode }

let defaultChatOptions =
    { PrimeWithAssistantResponse = false
      Template = TurbotokenV1 }

let resolveChatTemplate (mode: ChatTemplateMode) : ChatTemplate =
    match mode with
    | TurbotokenV1 ->
        { MessagePrefix = "<|im_start|>"
          MessageSuffix = "<|im_end|>\n"
          AssistantPrefix = Some "<|im_start|>assistant\n" }
    | ImTokens ->
        { MessagePrefix = ""
          MessageSuffix = ""
          AssistantPrefix = None }

let formatChat (messages: ChatMessage list) (options: ChatOptions) : string =
    let sb = StringBuilder()
    let template = resolveChatTemplate options.Template

    match options.Template with
    | TurbotokenV1 ->
        for msg in messages do
            sb.Append("<|im_start|>") |> ignore
            match msg.Name with
            | Some name -> sb.Append(sprintf "%s name=%s\n" msg.Role name) |> ignore
            | None -> sb.Append(sprintf "%s\n" msg.Role) |> ignore
            sb.Append(sprintf "%s<|im_end|>\n" msg.Content) |> ignore
        if options.PrimeWithAssistantResponse then
            sb.Append("<|im_start|>assistant\n") |> ignore
    | ImTokens ->
        for msg in messages do
            sb.Append(template.MessagePrefix) |> ignore
            match msg.Name with
            | Some name -> sb.Append(sprintf "%s name=%s\n" msg.Role name) |> ignore
            | None -> sb.Append(sprintf "%s\n" msg.Role) |> ignore
            sb.Append(msg.Content) |> ignore
            sb.Append(template.MessageSuffix) |> ignore
        if options.PrimeWithAssistantResponse then
            match template.AssistantPrefix with
            | Some prefix -> sb.Append(prefix) |> ignore
            | None -> ()

    sb.ToString()
