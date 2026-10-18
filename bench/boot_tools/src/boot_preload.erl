%% Profile-guided background preload for interactive mode: load the modules
%% a previous boot used (the list is grouped by application in the boot
%% script's start order, alphabetical within each application; it is not the
%% order modules were actually loaded), in parallel chunks, while the boot
%% script starts applications.
-module(boot_preload).
-export([start/2]).

start(Mods, ChunkSize) ->
    _ = spawn(fun() ->
                      wait_for(code_server),
                      catch boot_trace:mark(preload_start),
                      Res = [begin
                                 R = (catch code:ensure_modules_loaded(C)),
                                 catch boot_trace:mark({preload_chunk_done, length(C)}),
                                 R
                             end || C <- chunks(Mods, ChunkSize)],
                      case [R || R <- Res, R =/= ok] of
                          [] -> ok;
                          [E | _] -> catch boot_trace:mark({preload_error, length(Res), E})
                      end,
                      catch boot_trace:mark(preload_done)
              end),
    ok.

wait_for(Name) ->
    case whereis(Name) of
        undefined -> receive after 5 -> wait_for(Name) end;
        _ -> ok
    end.

chunks([], _) -> [];
chunks(L, N) when length(L) =< N -> [L];
chunks(L, N) -> {H, T} = lists:split(N, L), [H | chunks(T, N)].
