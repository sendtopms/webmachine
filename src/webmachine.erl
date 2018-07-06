%% @author Justin Sheehy <justin@basho.com>
%% @author Andy Gross <andy@basho.com>
%% @copyright 2007-2014 Basho Technologies
%%
%%    Licensed under the Apache License, Version 2.0 (the "License");
%%    you may not use this file except in compliance with the License.
%%    You may obtain a copy of the License at
%%
%%        http://www.apache.org/licenses/LICENSE-2.0
%%
%%    Unless required by applicable law or agreed to in writing, software
%%    distributed under the License is distributed on an "AS IS" BASIS,
%%    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%    See the License for the specific language governing permissions and
%%    limitations under the License.

-module(webmachine).
-author('Justin Sheehy <justin@basho.com>').
-author('Andy Gross <andy@basho.com>').
-export([start/0, stop/0]).
-export([new_request/2]).

-include("webmachine_logger.hrl").
-include("wm_reqstate.hrl").
-include("wm_reqdata.hrl").

%% @spec start() -> ok
%% @doc Start the webmachine server.
start() ->
    webmachine_deps:ensure(),
    ok = ensure_started(crypto),
    ok = ensure_started(webmachine).

ensure_started(App) ->
    case application:start(App) of
        ok ->
            ok;
        {error, {already_started, App}} ->
            ok;
        {error, _} = E ->
            E
    end.

%% @spec stop() -> ok
%% @doc Stop the webmachine server.
stop() ->
    application:stop(webmachine).

new_request(mochiweb, Request) ->
	io:format("~n~n1TEst ~p~n", [1]),
    Method = mochiweb_request:get(method, Request),
	io:format("~n~n2TEst ~p~n", [Method]),
    Scheme = mochiweb_request:get(scheme, Request),
    Version = mochiweb_request:get(version, Request),
    {Headers, RawPath} = case application:get_env(webmachine, rewrite_module) of
        {ok, RewriteMod} ->
            do_rewrite(RewriteMod,
                       Method,
                       Scheme,
                       Version,
                       mochiweb_request:get(headers, Request),
                       mochiweb_request:get(raw_path, Request));
        undefined ->
            {mochiweb_request:get(headers, Request), mochiweb_request:get(raw_path, Request)}
    end,
    Socket = mochiweb_request:get(socket, Request),
    InitState = #wm_reqstate{socket=Socket,
                          reqdata=wrq:create(Method,Scheme,Version,RawPath,Headers)},

    InitReq = {webmachine_request,InitState},
    {Peer, _ReqState} = webmachine_request:get_peer(InitReq),
    {Sock, ReqState} = webmachine_request:get_sock(InitReq),
    ReqData = wrq:set_sock(Sock,
                           wrq:set_peer(Peer,
                                        ReqState#wm_reqstate.reqdata)),
    LogData = #wm_log_data{start_time=os:timestamp(),
                           method=Method,
                           headers=Headers,
                           peer=Peer,
                           sock=Sock,
                           path=RawPath,
                           version=Version,
                           response_code=404,
                           response_length=0},
    webmachine_request:new(ReqState#wm_reqstate{log_data=LogData,
                                                reqdata=ReqData}).

do_rewrite(RewriteMod, Method, Scheme, Version, Headers, RawPath) ->
    case RewriteMod:rewrite(Method, Scheme, Version, Headers, RawPath) of
        %% only raw path has been rewritten (older style rewriting)
        NewPath when is_list(NewPath) -> {Headers, NewPath};

        %% headers and raw path rewritten (new style rewriting)
        {NewHeaders, NewPath} -> {NewHeaders,NewPath}
    end.

%%
%% TEST
%%
-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

start_mochiweb() ->
    webmachine_util:ensure_all_started(mochiweb).

start_stop_test() ->
    {Res, Apps} = start_mochiweb(),
    ?assertEqual(ok, Res),
    ?assertEqual(ok, webmachine:start()),
    ?assertEqual(ok, webmachine:stop()),
    [application:stop(App) || App <- Apps],
    ok.

-endif.
