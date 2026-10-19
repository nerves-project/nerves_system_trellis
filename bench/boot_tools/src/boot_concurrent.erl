%% Start the boot script's applications concurrently (inserted by
%% BootTools.Step when BOOT_CONCURRENT=1). systools boot scripts start
%% applications strictly one after another with application:start_boot/2;
%% this hands the same list to application:ensure_all_started/3 in
%% concurrent mode (OTP 26+), which starts each application as soon as its
%% dependencies are running.
-module(boot_concurrent).
-export([start/2]).

start(Apps, Type) ->
    case application:ensure_all_started(Apps, Type, concurrent) of
        {ok, _} -> ok;
        {error, Reason} -> exit({boot_concurrent, Reason})
    end.
