%% Profile-guided background preload for interactive mode: load the modules
%% a previous boot used, in parallel, while the boot script starts
%% applications.
%%
%% start/2: code:ensure_modules_loaded/1 per chunk. It spawns one process per
%% module, and each one asks code_server for the file and reads it through
%% erl_prim_loader (both single processes the boot process also needs).
%%
%% start_pool/2: N workers read files directly by path (paths computed at
%% build time, relative to the release root), prepare them without waiting
%% for code_server, and a collector hands prepared code to code_server in
%% batches once it is running.
-module(boot_preload).
-export([start/2, start_pool/4]).

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

%% ModPaths: [{Module, PathRelativeToRoot}]. Workers 0 = schedulers online.
%% Only uses modules that are loaded before the boot script's
%% kernel_load_completed (no maps/proplists).
start_pool(ModPaths, Workers, Batch, Prio) ->
    N = case Workers of 0 -> erlang:system_info(schedulers_online); _ -> Workers end,
    {ok, [[Root]]} = init:get_argument(root),
    _ = spawn(fun() ->
                      process_flag(priority, Prio),
                      catch boot_trace:mark(preload_start),
                      Self = self(),
                      Lists = deal(ModPaths, N),
                      [spawn_link(fun() ->
                                          process_flag(priority, Prio),
                                          [prep(Self, Root, M, P) || {M, P} <- L],
                                          Self ! worker_done
                                  end) || L <- Lists],
                      collect(length(Lists), Batch, [], 0, 0)
              end),
    ok.

prep(Collector, Root, M, Rel) ->
    case erlang:module_loaded(M) of
        true -> Collector ! skipped;
        false ->
            File = Root ++ "/" ++ Rel,
            case prim_file:read_file(File) of
                {ok, Bin} ->
                    case erlang:prepare_loading(M, Bin) of
                        {error, _} = E -> Collector ! {failed, M, E};
                        Prep ->
                            case erlang:has_prepared_code_on_load(Prep) of
                                true -> Collector ! {failed, M, on_load};
                                false -> Collector ! {prepared, M, Prep, File}
                            end
                    end;
                E -> Collector ! {failed, M, E}
            end
    end.

collect(0, _Batch, Acc, Loaded, Failed) ->
    Loaded1 = Loaded + finish(Acc),
    catch boot_trace:mark({preload_pool_done, Loaded1, Failed}),
    catch boot_trace:mark(preload_done);
collect(Workers, Batch, Acc, Loaded, Failed) ->
    receive
        worker_done -> collect(Workers - 1, Batch, Acc, Loaded, Failed);
        skipped -> collect(Workers, Batch, Acc, Loaded, Failed);
        {failed, _M, _E} -> collect(Workers, Batch, Acc, Loaded, Failed + 1);
        {prepared, M, Prep, File} ->
            Acc1 = [{M, {Prep, File}} | Acc],
            case length(Acc1) >= Batch andalso whereis(code_server) =/= undefined of
                true -> collect(Workers, Batch, [], Loaded + finish(Acc1), Failed);
                false -> collect(Workers, Batch, Acc1, Loaded, Failed)
            end
    end.

finish([]) -> 0;
finish(Acc) ->
    wait_for(code_server),
    %% Same call code:ensure_modules_loaded/1 makes; skips modules that got
    %% loaded on demand in the meantime.
    case catch code_server:call({finish_loading, Acc, true}) of
        ok -> length(Acc);
        Other -> catch boot_trace:mark({preload_finish_error, Other}), 0
    end.

%% Round-robin so every worker starts near the front of the list.
deal(L, N) ->
    Tagged = lists:zip(lists:seq(0, length(L) - 1), L),
    [[X || {I, X} <- Tagged, I rem N =:= K] || K <- lists:seq(0, N - 1)].

wait_for(Name) ->
    case whereis(Name) of
        undefined -> receive after 5 -> wait_for(Name) end;
        _ -> ok
    end.

chunks([], _) -> [];
chunks(L, N) when length(L) =< N -> [L];
chunks(L, N) -> {H, T} = lists:split(N, L), [H | chunks(T, N)].
