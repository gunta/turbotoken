local registry = require("turbotoken.registry")

local M = {}

function M.cache_dir()
    local env = os.getenv("TURBOTOKEN_CACHE_DIR")
    if env and env ~= "" then
        return env
    end

    local home = os.getenv("HOME") or os.getenv("USERPROFILE") or os.tmpname():match("(.+)/")
    return home .. "/.cache/turbotoken"
end

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

local function mkdir_p(path)
    -- Use os.execute for cross-platform directory creation
    if package.config:sub(1, 1) == "\\" then
        os.execute('mkdir "' .. path .. '" 2>NUL')
    else
        os.execute('mkdir -p "' .. path .. '"')
    end
end

local function download_file(url, dest)
    -- Try LuaSocket first
    local ok, http = pcall(require, "socket.http")
    if ok then
        local ltn12 = require("ltn12")
        local sink = ltn12.sink.file(io.open(dest, "wb"))
        local result, status = http.request({
            url = url,
            sink = sink,
        })
        if result and status == 200 then
            return true
        end
        os.remove(dest)
    end

    -- Fallback to curl
    local cmd = string.format('curl -sL -o "%s" "%s"', dest, url)
    local ret = os.execute(cmd)
    if ret == 0 or ret == true then
        return true
    end

    -- Fallback to wget
    cmd = string.format('wget -q -O "%s" "%s"', dest, url)
    ret = os.execute(cmd)
    if ret == 0 or ret == true then
        return true
    end

    error("Failed to download rank file from: " .. url)
end

function M.ensure_rank_file(name)
    local spec = registry.get_encoding_spec(name)
    local dir = M.cache_dir()
    local file_path = dir .. "/" .. spec.name .. ".tiktoken"

    if file_exists(file_path) then
        return file_path
    end

    mkdir_p(dir)
    download_file(spec.rank_file_url, file_path)

    if not file_exists(file_path) then
        error("Failed to create rank file: " .. file_path)
    end

    return file_path
end

function M.read_rank_file(name)
    local file_path = M.ensure_rank_file(name)
    local f = io.open(file_path, "rb")
    if not f then
        error("Failed to read rank file: " .. file_path)
    end
    local data = f:read("*a")
    f:close()
    return data
end

return M
