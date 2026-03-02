module TurboToken.Encoding

open System
open System.Runtime.InteropServices
open System.Text
open TurboToken.Native
open TurboToken.Chat
open TurboToken.Registry

type Encoding =
    { Name: string
      Spec: EncodingSpec
      RankPayload: byte[] }

let private utf8 = Encoding.UTF8

let private twoPassUInt32
    (rankPayload: byte[])
    (input: byte[])
    (fn: nativeint -> unativeint -> nativeint -> unativeint -> nativeint -> unativeint -> nativeint)
    : Result<uint32[], string> =
    let rankHandle = GCHandle.Alloc(rankPayload, GCHandleType.Pinned)
    let inputHandle = GCHandle.Alloc(input, GCHandleType.Pinned)
    try
        let rankPtr = rankHandle.AddrOfPinnedObject()
        let rankLen = unativeint rankPayload.Length
        let inputPtr = inputHandle.AddrOfPinnedObject()
        let inputLen = unativeint input.Length

        let sizeResult = fn rankPtr rankLen inputPtr inputLen IntPtr.Zero (unativeint 0)
        let count = int64 sizeResult
        if count < 0L then
            Error (sprintf "FFI size query returned error code %d" count)
        elif count = 0L then
            Ok Array.empty
        else
            let buffer = Array.zeroCreate<uint32> (int count)
            let outHandle = GCHandle.Alloc(buffer, GCHandleType.Pinned)
            try
                let outPtr = outHandle.AddrOfPinnedObject()
                let written = fn rankPtr rankLen inputPtr inputLen outPtr (unativeint count)
                let writtenCount = int64 written
                if writtenCount < 0L then
                    Error (sprintf "FFI fill returned error code %d" writtenCount)
                elif writtenCount < count then
                    Ok (Array.sub buffer 0 (int writtenCount))
                else
                    Ok buffer
            finally
                outHandle.Free()
    finally
        rankHandle.Free()
        inputHandle.Free()

let private twoPassUInt8
    (rankPayload: byte[])
    (input: uint32[])
    (fn: nativeint -> unativeint -> nativeint -> unativeint -> nativeint -> unativeint -> nativeint)
    : Result<byte[], string> =
    let rankHandle = GCHandle.Alloc(rankPayload, GCHandleType.Pinned)
    let inputHandle = GCHandle.Alloc(input, GCHandleType.Pinned)
    try
        let rankPtr = rankHandle.AddrOfPinnedObject()
        let rankLen = unativeint rankPayload.Length
        let inputPtr = inputHandle.AddrOfPinnedObject()
        let inputLen = unativeint input.Length

        let sizeResult = fn rankPtr rankLen inputPtr inputLen IntPtr.Zero (unativeint 0)
        let count = int64 sizeResult
        if count < 0L then
            Error (sprintf "FFI size query returned error code %d" count)
        elif count = 0L then
            Ok Array.empty
        else
            let buffer = Array.zeroCreate<byte> (int count)
            let outHandle = GCHandle.Alloc(buffer, GCHandleType.Pinned)
            try
                let outPtr = outHandle.AddrOfPinnedObject()
                let written = fn rankPtr rankLen inputPtr inputLen outPtr (unativeint count)
                let writtenCount = int64 written
                if writtenCount < 0L then
                    Error (sprintf "FFI fill returned error code %d" writtenCount)
                elif writtenCount < count then
                    Ok (Array.sub buffer 0 (int writtenCount))
                else
                    Ok buffer
            finally
                outHandle.Free()
    finally
        rankHandle.Free()
        inputHandle.Free()

let encode (enc: Encoding) (text: string) : Result<uint32[], string> =
    let textBytes = utf8.GetBytes(text)
    twoPassUInt32 enc.RankPayload textBytes (fun rp rl ip il op oc ->
        turbotoken_encode_bpe_from_ranks(rp, rl, ip, il, op, oc))

let decode (enc: Encoding) (tokens: uint32[]) : Result<string, string> =
    twoPassUInt8 enc.RankPayload tokens (fun rp rl ip il op oc ->
        turbotoken_decode_bpe_from_ranks(rp, rl, ip, il, op, oc))
    |> Result.map utf8.GetString

let count (enc: Encoding) (text: string) : Result<int, string> =
    let textBytes = utf8.GetBytes(text)
    let rankHandle = GCHandle.Alloc(enc.RankPayload, GCHandleType.Pinned)
    let textHandle = GCHandle.Alloc(textBytes, GCHandleType.Pinned)
    try
        let result =
            turbotoken_count_bpe_from_ranks(
                rankHandle.AddrOfPinnedObject(), unativeint enc.RankPayload.Length,
                textHandle.AddrOfPinnedObject(), unativeint textBytes.Length)
        let code = int64 result
        if code < 0L then Error (sprintf "count returned error code %d" code)
        else Ok (int code)
    finally
        rankHandle.Free()
        textHandle.Free()

let countTokens (enc: Encoding) (text: string) : Result<int, string> =
    count enc text

let isWithinTokenLimit (enc: Encoding) (text: string) (limit: int) : Result<int option, string> =
    let textBytes = utf8.GetBytes(text)
    let rankHandle = GCHandle.Alloc(enc.RankPayload, GCHandleType.Pinned)
    let textHandle = GCHandle.Alloc(textBytes, GCHandleType.Pinned)
    try
        let result =
            turbotoken_is_within_token_limit_bpe_from_ranks(
                rankHandle.AddrOfPinnedObject(), unativeint enc.RankPayload.Length,
                textHandle.AddrOfPinnedObject(), unativeint textBytes.Length,
                unativeint limit)
        let code = int64 result
        if code = -2L then Ok None
        elif code < 0L then Error (sprintf "isWithinTokenLimit returned error code %d" code)
        else Ok (Some (int code))
    finally
        rankHandle.Free()
        textHandle.Free()

let encodeChat (enc: Encoding) (messages: ChatMessage list) (options: ChatOptions) : Result<uint32[], string> =
    let text = formatChat messages options
    encode enc text

let countChat (enc: Encoding) (messages: ChatMessage list) (options: ChatOptions) : Result<int, string> =
    let text = formatChat messages options
    count enc text

let isChatWithinTokenLimit (enc: Encoding) (messages: ChatMessage list) (limit: int) (options: ChatOptions) : Result<int option, string> =
    let text = formatChat messages options
    isWithinTokenLimit enc text limit

let encodeFilePath (enc: Encoding) (path: string) : Result<uint32[], string> =
    let pathBytes = utf8.GetBytes(path)
    twoPassUInt32 enc.RankPayload pathBytes (fun rp rl ip il op oc ->
        turbotoken_encode_bpe_file_from_ranks(rp, rl, ip, il, op, oc))

let countFilePath (enc: Encoding) (path: string) : Result<int, string> =
    let pathBytes = utf8.GetBytes(path)
    let rankHandle = GCHandle.Alloc(enc.RankPayload, GCHandleType.Pinned)
    let pathHandle = GCHandle.Alloc(pathBytes, GCHandleType.Pinned)
    try
        let result =
            turbotoken_count_bpe_file_from_ranks(
                rankHandle.AddrOfPinnedObject(), unativeint enc.RankPayload.Length,
                pathHandle.AddrOfPinnedObject(), unativeint pathBytes.Length)
        let code = int64 result
        if code < 0L then Error (sprintf "countFilePath returned error code %d" code)
        else Ok (int code)
    finally
        rankHandle.Free()
        pathHandle.Free()

let isFilePathWithinTokenLimit (enc: Encoding) (path: string) (limit: int) : Result<int option, string> =
    let pathBytes = utf8.GetBytes(path)
    let rankHandle = GCHandle.Alloc(enc.RankPayload, GCHandleType.Pinned)
    let pathHandle = GCHandle.Alloc(pathBytes, GCHandleType.Pinned)
    try
        let result =
            turbotoken_is_within_token_limit_bpe_file_from_ranks(
                rankHandle.AddrOfPinnedObject(), unativeint enc.RankPayload.Length,
                pathHandle.AddrOfPinnedObject(), unativeint pathBytes.Length,
                unativeint limit)
        let code = int64 result
        if code = -2L then Ok None
        elif code < 0L then Error (sprintf "isFilePathWithinTokenLimit returned error code %d" code)
        else Ok (Some (int code))
    finally
        rankHandle.Free()
        pathHandle.Free()
