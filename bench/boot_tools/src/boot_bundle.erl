%% Load every boot module from one pre-built bundle file instead of one
%% path-searched read per module. Runs inside init's boot process (via an
%% {apply,...} boot script instruction) so it can report loaded modules to
%% init exactly like primLoad does; later primLoad instructions then skip the
%% already-loaded modules.
-module(boot_bundle).
-export([load/1]).

load(File) ->
    {ok, Bin} = prim_file:read_file(File),
    Entries = binary_to_term(Bin),  %% [{Mod, FullName, Beam}]
    Todo = [E || {M, _, _} = E <- Entries, not erlang:module_loaded(M)],
    N = erlang:system_info(schedulers_online),
    Prepared = pmap(fun prepare/1, chunk(Todo, N)),
    {Ok, OnLoad} = lists:partition(fun({_, _, {prepared, _}}) -> true; (_) -> false end, lists:append(Prepared)),
    ok = erlang:finish_loading([P || {_, _, {prepared, P}} <- Ok]),
    Init = whereis(init),
    Init ! {self(), loaded, [{M, F} || {M, F, _} <- Ok]},
    %% Modules with -on_load are left for the normal primLoad path, which
    %% runs their on_load function through init's on-load handler.
    _ = OnLoad,
    ok.

prepare(Chunk) ->
    [case erlang:prepare_loading(M, B) of
         {error, R} -> erlang:error({boot_bundle, M, R});
         P -> case erlang:has_prepared_code_on_load(P) of
                  true -> {M, F, {on_load, B}};
                  false -> {M, F, {prepared, P}}
              end
     end || {M, F, B} <- Chunk].

chunk(L, N) ->
    Tagged = lists:zip(lists:seq(0, length(L) - 1), L),
    [[E || {I, E} <- Tagged, I rem N =:= K] || K <- lists:seq(0, N - 1)].

pmap(F, Chunks) ->
    Self = self(),
    Pids = [spawn_link(fun() -> Self ! {self(), F(C)} end) || C <- Chunks],
    [receive {P, R} -> R end || P <- Pids].
