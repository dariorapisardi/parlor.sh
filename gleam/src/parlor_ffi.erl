%% The few things parlor needs from Erlang that the Gleam libraries do not wrap: the clock in the
%% format the Node server wrote, a lenient UTF-8 decoder, a process-wide "draining" flag, SIGTERM.
-module(parlor_ffi).
-behaviour(gen_event).
-export([now_ms/0, iso/1, parse_iso/1, lossy_utf8/1, set_draining/0, is_draining/0,
         on_sigterm/1, halt/1, put_global/2, get_global/1,
         collect_garbage/0, small_receive_buffers/1]).
-export([init/1, handle_event/2, handle_call/2, handle_info/2, terminate/2]).

now_ms() -> erlang:system_time(millisecond).

%% 2026-09-23T17:11:02.123Z, as JavaScript's toISOString() writes it.
iso(Ms) ->
    list_to_binary(calendar:system_time_to_rfc3339(Ms, [{unit, millisecond}, {offset, "Z"}])).

parse_iso(Bin) ->
    try {ok, calendar:rfc3339_to_system_time(binary_to_list(Bin), [{unit, millisecond}])}
    catch _:_ -> {error, nil}
    end.

%% Bytes to text the way Node's Buffer#toString('utf8') does it: every invalid sequence becomes
%% U+FFFD (one per maximal invalid subpart), nothing is refused.
lossy_utf8(Bin) -> lossy(Bin, []).

lossy(<<>>, Acc) -> iolist_to_binary(lists:reverse(Acc));
lossy(Bin, Acc) ->
    case Bin of
        <<C/utf8, Rest/binary>> -> lossy(Rest, [<<C/utf8>> | Acc]);
        <<_, Rest/binary>> -> lossy(skip_subpart(Bin, Rest), [<<16#FFFD/utf8>> | Acc])
    end.

%% After an invalid lead, also swallow the continuation bytes that were a valid prefix of it.
skip_subpart(<<Lead, _/binary>>, Rest) ->
    {Need, Lo, Hi} =
        if Lead >= 16#C2, Lead =< 16#DF -> {1, 16#80, 16#BF};
           Lead =:= 16#E0 -> {2, 16#A0, 16#BF};
           Lead >= 16#E1, Lead =< 16#EC -> {2, 16#80, 16#BF};
           Lead =:= 16#ED -> {2, 16#80, 16#9F};
           Lead >= 16#EE, Lead =< 16#EF -> {2, 16#80, 16#BF};
           Lead =:= 16#F0 -> {3, 16#90, 16#BF};
           Lead >= 16#F1, Lead =< 16#F3 -> {3, 16#80, 16#BF};
           Lead =:= 16#F4 -> {3, 16#80, 16#8F};
           true -> {0, 0, 0}
        end,
    continuation(Rest, Need, Lo, Hi).

continuation(Rest, 0, _, _) -> Rest;
continuation(<<B, Rest/binary>>, Need, Lo, Hi) when B >= Lo, B =< Hi ->
    continuation(Rest, Need - 1, 16#80, 16#BF);
continuation(Rest, _, _, _) -> Rest.

set_draining() -> persistent_term:put(parlor_draining, true), nil.
is_draining() -> persistent_term:get(parlor_draining, false).

%% Replace the VM's own SIGTERM handling (a plain init:stop) with ours.
on_sigterm(Fun) ->
    ok = os:set_signal(sigterm, handle),
    ok = gen_event:swap_handler(erl_signal_server, {erl_signal_handler, []}, {?MODULE, Fun}),
    nil.

init({Fun, _}) -> {ok, Fun}.
handle_event(sigterm, Fun) -> Fun(), {ok, Fun};
handle_event(_, Fun) -> {ok, Fun}.
handle_call(_, Fun) -> {ok, ok, Fun}.
handle_info(_, Fun) -> {ok, Fun}.
terminate(_, _) -> ok.

halt(Code) -> erlang:halt(Code).

%% Read-only data every connection needs (the pages), stored once instead of copied into each
%% connection process.
put_global(Key, Value) -> persistent_term:put({parlor, Key}, Value), nil.
get_global(Key) -> persistent_term:get({parlor, Key}).

%% Before a connection process blocks in a long-poll: what it allocated to parse the request
%% (among it glisten's receive buffer, sized to the kernel's 128 KiB) is garbage, but would stay
%% allocated for the whole wait. Tens of KiB per held poll, collected here in microseconds.
collect_garbage() -> erlang:garbage_collect(), nil.

%% glisten sizes each connection's receive buffer to the kernel's socket buffer (128 KiB on
%% Linux) and allocates it for every request, so a burst of long-polls costs 128 KiB each until
%% they are collected. Requests here are a few KiB. Accepted sockets inherit the listening
%% socket's kernel buffer, which glisten then copies: set it there. Found by port number, as
%% glisten does not hand out its socket.
small_receive_buffers(Port) ->
    _ = [inet:setopts(P, [{recbuf, 8192}])
         || P <- erlang:ports(),
            erlang:port_info(P, name) =:= {name, "tcp_inet"},
            {ok, {_, Port}} <- [inet:sockname(P)],
            {ok, [{active, false}]} <- [inet:getopts(P, [active])]],
    nil.
