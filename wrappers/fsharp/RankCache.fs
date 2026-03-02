module TurboToken.RankCache

open System
open System.IO
open System.Net.Http

let private httpClient = new HttpClient()

let cacheDir () : string =
    let xdgCache = Environment.GetEnvironmentVariable("XDG_CACHE_HOME")
    let baseDir =
        if not (String.IsNullOrEmpty xdgCache) then xdgCache
        else Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".cache")
    Path.Combine(baseDir, "turbotoken")

let ensureRankFile (name: string) : Async<Result<string, string>> =
    async {
        match Registry.getEncodingSpec name with
        | Error e -> return Error e
        | Ok spec ->
            let uri = Uri(spec.RankFileUrl)
            let fileName = Path.GetFileName(uri.AbsolutePath)
            let localPath = Path.Combine(cacheDir (), fileName)

            if File.Exists localPath then
                return Ok localPath
            else
                Directory.CreateDirectory(cacheDir ()) |> ignore
                let! data = httpClient.GetByteArrayAsync(spec.RankFileUrl) |> Async.AwaitTask
                let tempPath = localPath + ".tmp"
                File.WriteAllBytes(tempPath, data)
                File.Move(tempPath, localPath)
                return Ok localPath
    }

let readRankFile (name: string) : Async<Result<byte[], string>> =
    async {
        let! pathResult = ensureRankFile name
        match pathResult with
        | Error e -> return Error e
        | Ok filePath -> return Ok (File.ReadAllBytes filePath)
    }
