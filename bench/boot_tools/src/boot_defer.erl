%% Start some applications in the background after the boot script finishes
%% its synchronous part, so IEx (started by -run elixir start_cli once init is
%% done) doesn't wait for them.
-module(boot_defer).
-export([start/1, start/2]).

start(AppsTypes) -> start(AppsTypes, normal).

start(AppsTypes, Priority) ->
    _ = spawn_opt(fun() ->
                      [begin
                           catch boot_trace:mark({deferred_start, App}),
                           case application:start(App, Type) of
                               ok -> ok;
                               {error, {already_started, _}} -> ok;
                               Error -> erlang:display({boot_defer, App, Error})
                           end
                       end || {App, Type} <- AppsTypes],
                      catch boot_trace:mark(deferred_done)
              end, [{priority, Priority}]),
    ok.
