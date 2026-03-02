module TurboToken.Api

open System
open System.Runtime.InteropServices

let version () : string =
    let ptr = Native.turbotoken_version()
    if ptr = IntPtr.Zero then "unknown"
    else
        let s = Marshal.PtrToStringAnsi(ptr)
        if isNull s then "unknown" else s

let clearCache () : unit =
    Native.turbotoken_clear_rank_table_cache()

let getEncoding (name: string) : Async<Result<Encoding.Encoding, string>> =
    async {
        match Registry.getEncodingSpec name with
        | Error e -> return Error e
        | Ok spec ->
            let! rankResult = RankCache.readRankFile spec.Name
            match rankResult with
            | Error e -> return Error e
            | Ok rankData ->
                return Ok { Encoding.Name = spec.Name; Encoding.Spec = spec; Encoding.RankPayload = rankData }
    }

let getEncodingForModel (model: string) : Async<Result<Encoding.Encoding, string>> =
    async {
        match Registry.modelToEncoding model with
        | Error e -> return Error e
        | Ok encodingName -> return! getEncoding encodingName
    }

let listEncodingNames () : string list =
    Registry.listEncodingNames ()
