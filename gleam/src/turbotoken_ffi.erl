%% turbotoken_ffi.erl — Erlang FFI bridge for Gleam.
%%
%% Adapts between Gleam calling conventions and the turbotoken NIF module
%% (Elixir.TurboToken.Nif). Also provides file I/O and HTTP download helpers.

-module(turbotoken_ffi).
-export([
    version/0,
    encode_bpe/2,
    decode_bpe/2,
    count_bpe/2,
    is_within_token_limit/3,
    count_bpe_file/2,
    clear_rank_table_cache/0,
    read_file/1,
    download_and_cache/2,
    home_dir/0
]).

version() ->
    V = 'Elixir.TurboToken.Nif':version(),
    list_to_binary(V).

encode_bpe(RankPayload, Text) ->
    case 'Elixir.TurboToken.Nif':encode_bpe(RankPayload, Text) of
        {ok, Tokens} -> {ok, Tokens};
        {error, Reason} -> {error, atom_to_binary(Reason, utf8)}
    end.

decode_bpe(RankPayload, Tokens) ->
    case 'Elixir.TurboToken.Nif':decode_bpe(RankPayload, Tokens) of
        {ok, Data} -> {ok, Data};
        {error, Reason} -> {error, atom_to_binary(Reason, utf8)}
    end.

count_bpe(RankPayload, Text) ->
    case 'Elixir.TurboToken.Nif':count_bpe(RankPayload, Text) of
        {ok, Count} -> {ok, Count};
        {error, Reason} -> {error, atom_to_binary(Reason, utf8)}
    end.

is_within_token_limit(RankPayload, Text, Limit) ->
    case 'Elixir.TurboToken.Nif':is_within_token_limit(RankPayload, Text, Limit) of
        {ok, false} -> {error, <<"exceeded">>};
        {ok, Count} -> {ok, Count};
        {error, Reason} -> {error, atom_to_binary(Reason, utf8)}
    end.

count_bpe_file(RankPayload, FilePath) ->
    case 'Elixir.TurboToken.Nif':count_bpe_file(RankPayload, FilePath) of
        {ok, Count} -> {ok, Count};
        {error, Reason} -> {error, atom_to_binary(Reason, utf8)}
    end.

clear_rank_table_cache() ->
    'Elixir.TurboToken.Nif':clear_rank_table_cache(),
    nil.

read_file(Path) ->
    case file:read_file(Path) of
        {ok, Data} -> {ok, Data};
        {error, Reason} -> {error, atom_to_binary(Reason, utf8)}
    end.

download_and_cache(Url, DestPath) ->
    ok = ensure_http_started(),
    UrlList = binary_to_list(Url),
    SslOpts = [
        {ssl, [
            {verify, verify_peer},
            {cacerts, public_key:cacerts_get()},
            {depth, 3}
        ]}
    ],
    case httpc:request(get, {UrlList, []}, SslOpts, [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, Body}} ->
            ok = filelib:ensure_dir(DestPath),
            ok = file:write_file(DestPath, Body),
            {ok, Body};
        {ok, {{_, Status, _}, _, _}} ->
            {error, list_to_binary(io_lib:format("HTTP ~p", [Status]))};
        {error, Reason} ->
            {error, list_to_binary(io_lib:format("~p", [Reason]))}
    end.

home_dir() ->
    case os:getenv("HOME") of
        false -> <<"/tmp">>;
        Home -> list_to_binary(Home)
    end.

ensure_http_started() ->
    case inets:start() of
        ok -> ok;
        {error, {already_started, inets}} -> ok
    end,
    case ssl:start() of
        ok -> ok;
        {error, {already_started, ssl}} -> ok
    end,
    ok.
