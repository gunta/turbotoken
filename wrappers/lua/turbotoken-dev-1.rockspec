package = "turbotoken"
version = "dev-1"
source = {
    url = "git+https://github.com/turbotoken/turbotoken.git",
    tag = "v0.1.0",
}
description = {
    summary = "The fastest BPE tokenizer on every platform -- drop-in tiktoken replacement",
    detailed = [[
        turbotoken is a drop-in replacement for tiktoken using Zig + hand-written
        assembly for maximum performance. This Lua binding uses LuaJIT FFI or
        cffi-lua to call the native library.
    ]],
    homepage = "https://github.com/turbotoken/turbotoken/tree/main/wrappers/lua",
    license = "MIT",
}
dependencies = {
    "lua >= 5.1",
}
build = {
    type = "builtin",
    modules = {
        ["turbotoken"] = "src/turbotoken/init.lua",
        ["turbotoken.ffi_bridge"] = "src/turbotoken/ffi_bridge.lua",
        ["turbotoken.encoding"] = "src/turbotoken/encoding.lua",
        ["turbotoken.registry"] = "src/turbotoken/registry.lua",
        ["turbotoken.rank_cache"] = "src/turbotoken/rank_cache.lua",
        ["turbotoken.chat"] = "src/turbotoken/chat.lua",
    },
}
