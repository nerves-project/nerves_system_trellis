%% Embedded-mode loader: replaces the boot script's per-application primLoad
%% groups (inserted by BootTools.Step when BOOT_ELOAD is set).
%%
%% init loads each primLoad group in parallel, but groups run one after
%% another and each waits for its slowest module, so small applications
%% leave cores idle. This loads every module after kernel_load_completed in
%% one pass: N workers read files by exact path (no path search) and
%% prepare them, and the boot process installs them in batches and tells
%% init what it loaded, as init's own primLoad does.
%%
%% Runs in the boot process before code_server exists, so it only uses
%% preloaded modules and the ones in the first primLoad group.
-module(boot_eload).
-export([load/3]).

-define(ON_LOAD_HANDLER, init__boot__on_load_handler).

load(ModPaths, Workers, Batch) ->
    N = case Workers of 0 -> erlang:system_info(schedulers_online); _ -> Workers end,
    {ok, [[Root]]} = init:get_argument(root),
    Self = self(),
    Todo = [{M, Root ++ "/" ++ P} || {M, P} <- ModPaths, not erlang:module_loaded(M)],
    Lists = [L || L <- deal(Todo, N), L =/= []],
    %% Monitors, not links: the boot process traps exits, and init's next
    %% kernelProcess start would take a leftover 'EXIT' message as its reply.
    %% Every 'DOWN' is consumed below (it arrives after the worker's last
    %% message).
    _ = [spawn_monitor(fun() -> [Self ! prep(M, F) || {M, F} <- L] end) || L <- Lists],
    collect(length(Lists), Batch, [], []).

prep(M, File) ->
    case prim_file:read_file(File) of
        {ok, Bin} ->
            case erlang:prepare_loading(M, Bin) of
                {error, _} = E -> {failed, M, E};
                Prep ->
                    case erlang:has_prepared_code_on_load(Prep) of
                        true -> {on_load, M, Bin, File};
                        false -> {prepared, M, Prep, File}
                    end
            end;
        E -> {failed, M, E}
    end.

collect(0, _Batch, Acc, OnLoad) ->
    finish(Acc),
    [load_on_load(M, Bin, File) || {M, Bin, File} <- lists:reverse(OnLoad)],
    ok;
collect(Workers, Batch, Acc, OnLoad) ->
    receive
        {'DOWN', _, process, _, normal} -> collect(Workers - 1, Batch, Acc, OnLoad);
        {'DOWN', _, process, _, Reason} -> exit({boot_eload_worker, Reason});
        {failed, M, E} -> exit({load_failed, M, E});
        {on_load, M, Bin, File} -> collect(Workers, Batch, Acc, [{M, Bin, File} | OnLoad]);
        {prepared, M, Prep, File} ->
            case [{M, Prep, File} | Acc] of
                Acc1 when length(Acc1) >= Batch ->
                    finish(Acc1),
                    collect(Workers, Batch, [], OnLoad);
                Acc1 ->
                    collect(Workers, Batch, Acc1, OnLoad)
            end
    end.

finish([]) -> ok;
finish(Acc) ->
    ok = erlang:finish_loading([P || {_, P, _} <- Acc]),
    init ! {self(), loaded, [{M, F} || {M, _, F} <- Acc]},
    ok.

%% Same as init's do_load_module/2 for modules with -on_load.
load_on_load(M, Bin, File) ->
    case erlang:load_module(M, Bin) of
        {module, M} -> ok;
        {error, on_load} -> ?ON_LOAD_HANDLER ! {loaded, M}
    end,
    init ! {self(), loaded, [{M, File}]},
    ok.

deal(L, N) ->
    Tagged = lists:zip(lists:seq(0, length(L) - 1), L),
    [[X || {I, X} <- Tagged, I rem N =:= K] || K <- lists:seq(0, N - 1)].
