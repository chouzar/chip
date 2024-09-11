-module(chip_erlang_ffi).
-export([
    decode_down_message/1,
    demonitor/1,
    schedulers/0,
    search/3, 
    search/1
]).

search(Table, Pattern, Limit) -> 
    Result = ets:match(Table, Pattern, Limit),
    handle_search(Result).
    
search(Continuation) -> 
    Result = ets:match(Continuation),
    handle_search(Result).
    
handle_search(Result) -> 
    case Result of
        {Objects, '$end_of_table'} -> 
            {end_of_table, Objects};
            
        {Objects, Continuation} -> 
            {partial, Objects, Continuation};
            
        '$end_of_table' ->
            {end_of_table, []}
        end.

schedulers() -> 
    erlang:system_info(schedulers).

decode_down_message(Message) ->
    % Exit reasons: https://elixirforum.com/t/why-does-registry-use-set-and-duplicate-bag/44058
    case Message of
        {'DOWN', Monitor, process, Pid, _ExitReason} when is_reference(Monitor) and is_pid(Pid) -> 
            {ok, {process_down, Monitor, Pid}};
        
        _other -> 
            {error, nil}
        end.
                
demonitor(Reference) ->
    erlang:demonitor(Reference, [flush]),
    nil.
