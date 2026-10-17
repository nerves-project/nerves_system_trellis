%% Boot script tracer: records timestamped marks while init evaluates the
%% boot script. Marks are kept by a tiny registered process so they survive
%% the boot process exiting. Read them later with boot_trace:marks/0.
-module(boot_trace).
-export([start/0, mark/1, marks/0, snapshot/0, samples/0, cpu/0, init/0, sampler/2, proc_snapshot/0, procs/0]).

start() ->
    T = erlang:monotonic_time(microsecond),
    case whereis(boot_trace) of
        undefined ->
            Pid = spawn(?MODULE, init, []),
            register(boot_trace, Pid),
            %% Cheap global accounting (per-scheduler emulator/gc/sleep/...
            %% time) instead of sampling, which is too costly on a T113.
            %% The per-process sampler (sampler/2) is kept for desktop use.
            catch erlang:system_flag(microstate_accounting, true),
            Pid ! {cpu, trace_start, cpu_snapshot()};
        _ -> ok
    end,
    boot_trace ! {mark, T, trace_start},
    ok.

mark(Label) ->
    T = erlang:monotonic_time(microsecond),
    case whereis(boot_trace) of
        undefined -> ok;
        Pid ->
            Loaded = erlang:loaded(),
            Pid ! {mark, T, Label, length(Loaded)},
            %% Keep the module set at IEx startup as a preload profile.
            Label =:= iex_exs andalso (Pid ! {snapshot, Loaded}),
            lists:member(Label, [script_done, iex_exs]) andalso (Pid ! {cpu, Label, cpu_snapshot()})
    end,
    ok.

%% One-time snapshot of per-process reductions (CPU work) at the end of the
%% boot script (inserted by BootTools.Step when BOOT_PROC_SNAPSHOT=1).
proc_snapshot() ->
    T = erlang:monotonic_time(microsecond),
    Procs = [{who(P), R} || P <- erlang:processes(),
                            {reductions, R} <- [erlang:process_info(P, reductions)]],
    case whereis(boot_trace) of
        undefined -> ok;
        Pid -> Pid ! {procs, {T, Procs}}
    end,
    ok.

procs() ->
    boot_trace ! {get_procs, self()},
    receive {boot_trace_procs, S} -> S after 5000 -> timeout end.

cpu_snapshot() ->
    Msacc = try erlang:statistics(microstate_accounting) catch _:_ -> undefined end,
    {erlang:monotonic_time(microsecond), erlang:statistics(runtime),
     read_file("/proc/stat"), read_file("/proc/self/stat"), Msacc}.

read_file(F) ->
    case prim_file:read_file(F) of {ok, B} -> B; _ -> <<>> end.

cpu() ->
    boot_trace ! {get_cpu, self()},
    receive {boot_trace_cpu, S} -> S after 5000 -> timeout end.

samples() ->
    boot_trace ! {get_samples, self()},
    receive {boot_trace_samples, S} -> S after 5000 -> timeout end.

sampler(BootPid, Store) ->
    process_flag(priority, high),
    sampler_loop(BootPid, Store, []).

sampler_loop(BootPid, Store, Acc) ->
    receive after 10 -> ok end,
    T = erlang:monotonic_time(microsecond),
    Busy = [{who(P), frames(P)} || P <- erlang:processes(), P =/= self(),
                                   lists:member(status(P), [running, runnable, garbage_collecting])],
    Acc1 = [{T, Busy} | Acc],
    %% Stop once the boot script has finished (boot process gone) plus 1 s.
    case is_process_alive(BootPid) of
        true -> sampler_loop(BootPid, Store, Acc1);
        false when length(Acc1) > 0 ->
            sampler_tail(Store, Acc1, 100)
    end.

sampler_tail(Store, Acc, 0) -> Store ! {samples, lists:reverse(Acc)};
sampler_tail(Store, Acc, N) ->
    receive after 10 -> ok end,
    T = erlang:monotonic_time(microsecond),
    Busy = [{who(P), frames(P)} || P <- erlang:processes(), P =/= self(),
                                   lists:member(status(P), [running, runnable, garbage_collecting])],
    sampler_tail(Store, [{T, Busy} | Acc], N - 1).

status(P) -> case erlang:process_info(P, status) of {status, S} -> S; _ -> exited end.

who(P) ->
    case erlang:process_info(P, [registered_name, dictionary, initial_call]) of
        [{registered_name, N}, _, _] when is_atom(N) -> N;
        [_, {dictionary, D}, {initial_call, IC}] ->
            case lists:keyfind('$initial_call', 1, D) of
                {_, {M, F, A}} -> {M, F, A};
                _ -> IC
            end;
        _ -> exited
    end.

frames(P) ->
    case erlang:process_info(P, current_stacktrace) of
        {current_stacktrace, Stack} ->
            [{M, F, if is_list(A) -> length(A); true -> A end} || {M, F, A, _} <- lists:sublist(Stack, 4)];
        _ -> []
    end.

snapshot() ->
    boot_trace ! {get_snapshot, self()},
    receive {boot_trace_snapshot, S} -> S after 5000 -> timeout end.

marks() ->
    boot_trace ! {get, self()},
    receive {boot_trace, Marks} -> Marks after 5000 -> timeout end.

init() -> put(snapshot, []), put(samples, []), put(cpu, []), put(procs, undefined), loop([]).

loop(Acc) ->
    receive
        {snapshot, S} -> put(snapshot, S), loop(Acc);
        {get_snapshot, From} -> From ! {boot_trace_snapshot, get(snapshot)}, loop(Acc);
        {samples, S} -> put(samples, S), loop(Acc);
        {cpu, L, S} -> put(cpu, [{L, S} | get(cpu)]), loop(Acc);
        {procs, S} -> put(procs, S), loop(Acc);
        {get_procs, From} -> From ! {boot_trace_procs, get(procs)}, loop(Acc);
        {get_cpu, From} -> From ! {boot_trace_cpu, lists:reverse(get(cpu))}, loop(Acc);
        {get_samples, From} -> From ! {boot_trace_samples, get(samples)}, loop(Acc);
        {mark, T, Label} -> loop([{T, Label, 0} | Acc]);
        {mark, T, Label, N} -> loop([{T, Label, N} | Acc]);
        {get, From} -> From ! {boot_trace, lists:reverse(Acc)}, loop(Acc)
    end.
