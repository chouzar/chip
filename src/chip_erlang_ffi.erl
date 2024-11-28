-module(chip_erlang_ffi).
-export([decode_down_message/1]).

decode_down_message(Message) ->
    % Exit reasons: https://elixirforum.com/t/why-does-registry-use-set-and-duplicate-bag/44058
    case Message of
        {'DOWN', Monitor, process, Pid, _ExitReason} when is_reference(Monitor) and is_pid(Pid) ->
            {ok, {process_down, Monitor, Pid}};

        _other ->
            {error, nil}
        end.
