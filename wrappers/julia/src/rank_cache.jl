"""
    cache_dir() -> String

Return the directory used for caching rank files.
Uses TURBOTOKEN_CACHE_DIR env var or defaults to ~/.cache/turbotoken/.
"""
function cache_dir()::String
    dir = get(ENV, "TURBOTOKEN_CACHE_DIR", "")
    if isempty(dir)
        dir = joinpath(homedir(), ".cache", "turbotoken")
    end
    return dir
end

"""
    ensure_rank_file(name::AbstractString) -> String

Ensure the rank file for the given encoding is downloaded and cached.
Returns the path to the cached file.
"""
function ensure_rank_file(name::AbstractString)::String
    spec = get_encoding_spec(name)
    dir = cache_dir()
    mkpath(dir)
    filepath = joinpath(dir, "$(spec.name).tiktoken")

    if !isfile(filepath)
        @info "Downloading rank file for $(spec.name)..."
        Downloads = Base.require(Base.PkgId(Base.UUID("f43a241f-c20a-4ad4-852c-f6b1247861c6"), "Downloads"))
        Downloads.download(spec.rank_file_url, filepath)
    end

    return filepath
end

"""
    read_rank_file(name::AbstractString) -> Vector{UInt8}

Read the rank file bytes for the given encoding, downloading if necessary.
"""
function read_rank_file(name::AbstractString)::Vector{UInt8}
    filepath = ensure_rank_file(name)
    return read(filepath)
end
