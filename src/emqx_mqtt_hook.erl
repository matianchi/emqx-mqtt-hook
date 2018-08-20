%%--------------------------------------------------------------------
%% Copyright (c) 2013-2017 EMQ Enterprise, Inc. (http://emqtt.io)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_mqtt_hook).

-include_lib("emqx/include/emqx.hrl").

-define(APP, emqx_mqtt_hook).

-export([load/0, unload/0]).

-export([on_client_connected/3, on_client_disconnected/3]).
-export([on_client_subscribe/4, on_client_unsubscribe/4]).
-export([on_session_created/3, on_session_subscribed/4, on_session_unsubscribed/4,
         on_session_terminated/4]).
-export([on_message_publish/2, on_message_delivered/4, on_message_acked/4]).

-define(LOG(Level, Format, Args), emqx_logger:Level("MqttHook: " ++ Format, Args)).

load() ->
    lists:foreach(
      fun({Hook, Fun, Filter}) ->
        load_(Hook, binary_to_atom(Fun, utf8), Filter, {Filter})
      end, parse_rule(application:get_env(?APP, rules, []))).

unload() ->
    lists:foreach(
      fun({Hook, Fun, Filter}) ->
          unload_(Hook, binary_to_atom(Fun, utf8), Filter)
      end, parse_rule(application:get_env(?APP, rules, []))).

%%--------------------------------------------------------------------
%% Client connected
%%--------------------------------------------------------------------
on_client_connected(ConnAck, Client = #mqtt_client{client_id  = ClientId,
                                                   username   = Username,
                                                   peername   = {IpAddr, _},
                                                   clean_sess = CleanSess,
                                                   proto_ver  = ProtoVer}, _Env) ->
    Payload = mochijson2:encode([{action, <<"client_connected">>},
                                 {clientid, ClientId},
                                 {username, Username},
                                 {ipaddress, iolist_to_binary(emqttd_net:ntoa(IpAddr))},
                                 {clean_sess, CleanSess},
                                 {protocol, ProtoVer},
                                 {connack, ConnAck},
                                 {ts, emqttd_time:now_secs()}]),
    Msg = message(qos(), listener_name(), Payload),
    emqttd:publish(emqttd_message:set_flag(sys, Msg)),
    {ok, Client}.

%%--------------------------------------------------------------------
%% Client disconnected
%%--------------------------------------------------------------------
on_client_disconnected({shutdown, Reason}, Client, Env) when is_atom(Reason) ->
  on_client_disconnected(Reason, Client, Env);
on_client_disconnected(Reason, _Client = #mqtt_client{client_id = ClientId,
                                                      username   = Username,
                                                      peername   = {IpAddr, _},
                                                      clean_sess = CleanSess,
                                                      proto_ver  = ProtoVer}, _Env) when is_atom(Reason) ->
    Payload = mochijson2:encode([{action, <<"client_disconnected">>},
                                 {clientid, ClientId},
                                 {username, Username},
                                 {ipaddress, iolist_to_binary(emqttd_net:ntoa(IpAddr))},
                                 {clean_sess, CleanSess},
                                 {protocol, ProtoVer},
                                 {reason, reason(Reason)},
                                 {ts, emqttd_time:now_secs()}]),
    Msg = message(qos(), listener_name(), Payload),
    emqttd:publish(emqttd_message:set_flag(sys, Msg)), ok;
on_client_disconnected(Reason, _Client, _Env) ->
  lager:error("Client disconnected reason:~p not encode json", [Reason]),
  ok.

%%--------------------------------------------------------------------
%% Client subscribe
%%--------------------------------------------------------------------
on_client_subscribe(ClientId, Username, TopicTable, {Filter}) ->
  lists:foreach(fun({Topic, Opts}) ->
    with_filter(
      fun() ->
        Payload = mochijson2:encode([{action, <<"client_subscribe">>},
                                     {clientid, ClientId},
                                     {username, Username},
                                     {topic, Topic},
                                     {opts, Opts},
                                     {ts, emqttd_time:now_secs()}]),
        Msg = message(qos(), listener_name(), Payload),
        emqttd:publish(emqttd_message:set_flag(sys, Msg))
      end, Topic, Filter)
                end, TopicTable),
  {ok, TopicTable}.

%%--------------------------------------------------------------------
%% Client unsubscribe
%%--------------------------------------------------------------------
on_client_unsubscribe(ClientId, Username, TopicTable, {Filter}) ->
  lists:foreach(fun({Topic, Opts}) ->
    with_filter(
      fun() ->
        Payload = mochijson2:encode([{action, <<"client_unsubscribe">>},
                                     {clientid, ClientId},
                                     {username, Username},
                                     {topic, Topic},
                                     {opts, Opts},
                                     {ts, emqttd_time:now_secs()}]),
        Msg = message(qos(), listener_name(), Payload),
        emqttd:publish(emqttd_message:set_flag(sys, Msg))
      end, Topic, Filter)
                end, TopicTable),
  {ok, TopicTable}.
%%--------------------------------------------------------------------
%% Session created
%%--------------------------------------------------------------------
on_session_created(ClientId, Username, _Env) ->
    Payload = mochijson2:encode([{action, session_created},
                                 {clientid, ClientId},
                                 {username, Username},
                                 {ts, emqttd_time:now_secs()}]),
    Msg = message(qos(), listener_name(), Payload),
    emqttd:publish(emqttd_message:set_flag(sys, Msg)),
    ok.

%%--------------------------------------------------------------------
%% Session subscribed
%%--------------------------------------------------------------------
on_session_subscribed(ClientId, Username, {Topic, Opts}, {Filter}) ->
  with_filter(
    fun() ->
        Payload = mochijson2:encode([{action, session_subscribed},
                                     {clientid, ClientId},
                                     {username, Username},
                                     {topic, Topic},
                                     {opts, Opts},
                                     {ts, emqttd_time:now_secs()}]),
        Msg = message(qos(), listener_name(), Payload),
        emqttd:publish(emqttd_message:set_flag(sys, Msg))
    end, Topic, Filter).


%%--------------------------------------------------------------------
%% Session unsubscribed
%%--------------------------------------------------------------------
on_session_unsubscribed(ClientId, Username, {Topic, _Opts}, {Filter}) ->
  with_filter(
    fun() ->
        Payload = mochijson2:encode([{action, session_unsubscribed},
                                     {clientid, ClientId},
                                     {username, Username},
                                     {topic, Topic},
                                     {ts, emqttd_time:now_secs()}]),
        Msg = message(qos(), listener_name(), Payload),
        emqttd:publish(emqttd_message:set_flag(sys, Msg))
    end, Topic, Filter).

%%--------------------------------------------------------------------
%% Session terminated
%%--------------------------------------------------------------------
on_session_terminated(ClientId, Username, {shutdown, Reason}, Env) when is_atom(Reason) ->
  on_session_terminated(ClientId, Username, Reason, Env);
on_session_terminated(ClientId, Username, Reason, _Env) when is_atom(Reason) ->
    Payload = mochijson2:encode([{action, session_terminated},
                                 {clientid, ClientId},
                                 {username, Username},
                                 {reason, Reason},
                                 {ts, emqttd_time:now_secs()}]),
    Msg = message(qos(), listener_name(), Payload),
    emqttd:publish(emqttd_message:set_flag(sys, Msg)),
    ok;
on_session_terminated(_ClientId, _Username, Reason, _Env) ->
  lager:error("Session terminated reason:~p not encode json", [Reason]),
  ok.

%%--------------------------------------------------------------------
%% Message publish
%%--------------------------------------------------------------------
on_message_publish(Message = #mqtt_message{topic = <<"$SYS/", _/binary>>}, _Env) ->
  {ok, Message};                     
on_message_publish(Message = #mqtt_message{topic = <<"dataflow">>}, _Env) ->
  {ok, Message};                     
on_message_publish(Message = #mqtt_message{topic = Topic}, {Filter}) ->
  with_filter(
    fun() ->
      {FromClientId, FromUsername} = format_from(Message#mqtt_message.from),
      Payload = mochijson2:encode([{action, message_publish},
                                   {from_client_id, FromClientId},
                                   {from_username, FromUsername},
                                   {topic, Message#mqtt_message.topic},
                                   {qos, Message#mqtt_message.qos},
                                   {retain, Message#mqtt_message.retain},
                                   {payload, Message#mqtt_message.payload},
                                   {ts, emqttd_time:now_secs(Message#mqtt_message.timestamp)}]),
      Msg = message(qos(), listener_name(), Payload),
      emqttd:publish(emqttd_message:set_flag(sys, Msg)),
      {ok, Message}              
    end, Message, Topic, Filter).

%%--------------------------------------------------------------------
%% Message delivered
%%--------------------------------------------------------------------
on_message_delivered(_ClientId, _Username, Message = #mqtt_message{topic = <<"$SYS/", _/binary>>}, _Env) ->
  {ok, Message};
on_message_delivered(_ClientId, _Username, Message = #mqtt_message{topic = <<"dataflow">>}, _Env) ->
  {ok, Message};
on_message_delivered(ClientId, Username, Message = #mqtt_message{topic = Topic}, {Filter}) ->
  with_filter(
    fun() ->
      {FromClientId, FromUsername} = format_from(Message#mqtt_message.from),
      Payload = mochijson2:encode([{action, message_delivered},
                                   {client_id, ClientId},
                                   {username, Username},
                                   {from_client_id, FromClientId},
                                   {from_username, FromUsername},
                                   {topic, Message#mqtt_message.topic},
                                   {qos, Message#mqtt_message.qos},
                                   {retain, Message#mqtt_message.retain},
                                   {payload, Message#mqtt_message.payload},
                                   {ts, emqttd_time:now_secs(Message#mqtt_message.timestamp)}]),
      Msg = message(qos(), listener_name(), Payload),
      emqttd:publish(emqttd_message:set_flag(sys, Msg)),
      {ok, Message}
    end, Topic, Filter).

%%--------------------------------------------------------------------
%% Message acked
%%--------------------------------------------------------------------
on_message_acked(_ClientId, _Username, Message = #mqtt_message{topic = <<"$SYS/", _/binary>>}, _Env) ->
  {ok, Message};
on_message_acked(_ClientId, _Username, Message = #mqtt_message{topic = <<"dataflow">>}, _Env) ->
  {ok, Message};
on_message_acked(ClientId, Username, Message = #mqtt_message{topic = Topic}, {Filter}) ->
  with_filter(
    fun() ->
      {FromClientId, FromUsername} = format_from(Message#mqtt_message.from),
      Payload = mochijson2:encode([{action, message_acked},
                                   {client_id, ClientId},
                                   {username, Username},
                                   {from_client_id, FromClientId},
                                   {from_username, FromUsername},
                                   {topic, Message#mqtt_message.topic},
                                   {qos, Message#mqtt_message.qos},
                                   {retain, Message#mqtt_message.retain},
                                   {payload, Message#mqtt_message.payload},
                                   {ts, emqttd_time:now_secs(Message#mqtt_message.timestamp)}]),
      Msg = message(qos(), listener_name(), Payload),
      emqttd:publish(emqttd_message:set_flag(sys, Msg)),
      {ok, Message}
    end, Topic, Filter).

%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------

parse_rule(Rules) ->
    parse_rule(Rules, []).
parse_rule([], Acc) ->
    lists:reverse(Acc);
parse_rule([{Rule, Conf} | Rules], Acc) ->
    {_, Params} = mochijson2:decode(Conf),
    Action = proplists:get_value(<<"action">>, Params),
    Filter = proplists:get_value(<<"topic">>, Params),
    parse_rule(Rules, [{list_to_atom(Rule), Action, Filter} | Acc]).

with_filter(Fun, _, undefined) ->
    Fun(), ok;
with_filter(Fun, Topic, Filter) ->
    case emqx_topic:match(Topic, Filter) of
        true  -> Fun(), ok;
        false -> ok
    end.

with_filter(Fun, _, _, undefined) ->
    Fun();
with_filter(Fun, Msg, Topic, Filter) ->
    case emqx_topic:match(Topic, Filter) of
        true  -> Fun();
        false -> {ok, Msg}
    end.

format_from({ClientId, Username}) ->
    {ClientId, Username};
format_from(From) when is_atom(From) ->
    {a2b(From), a2b(From)};
format_from(_) ->
    {<<>>, <<>>}.

reason(Reason) when is_atom(Reason) -> Reason;
reason({Error, _}) when is_atom(Error) -> Error;
reason(_) -> internal_error.

a2b(A) -> erlang:atom_to_binary(A, utf8).

message(Qos, Topic, Payload) ->
    emqttd_message:make(presence, Qos, Topic, iolist_to_binary(Payload)).

qos() ->
    Env = application:get_all_env(),
    proplists:get_value(qos, Env, 1).

listener_name() ->
    Env = application:get_all_env(),
    proplists:get_value(listener_name, Env, <<"dataflow">>).

load_(Hook, Fun, Filter, Params) ->
    case Hook of
        'client.connected'    -> emqx:hook(Hook, {Filter, fun ?MODULE:Fun/3}, [Params]);
        'client.disconnected' -> emqx:hook(Hook, {Filter, fun ?MODULE:Fun/3}, [Params]);
        'client.subscribe'    -> emqx:hook(Hook, {Filter, fun ?MODULE:Fun/4}, [Params]);
        'client.unsubscribe'  -> emqx:hook(Hook, {Filter, fun ?MODULE:Fun/4}, [Params]);
        'session.created'     -> emqx:hook(Hook, {Filter, fun ?MODULE:Fun/3}, [Params]);
        'session.subscribed'  -> emqx:hook(Hook, {Filter, fun ?MODULE:Fun/4}, [Params]);
        'session.unsubscribed'-> emqx:hook(Hook, {Filter, fun ?MODULE:Fun/4}, [Params]);
        'session.terminated'  -> emqx:hook(Hook, {Filter, fun ?MODULE:Fun/4}, [Params]);
        'message.publish'     -> emqx:hook(Hook, {Filter, fun ?MODULE:Fun/2}, [Params]);
        'message.acked'       -> emqx:hook(Hook, {Filter, fun ?MODULE:Fun/4}, [Params]);
        'message.delivered'   -> emqx:hook(Hook, {Filter, fun ?MODULE:Fun/4}, [Params])
    end.

unload_(Hook, Fun, Filter) ->
    case Hook of
        'client.connected'    -> emqx:unhook(Hook, {Filter, fun ?MODULE:Fun/3});
        'client.disconnected' -> emqx:unhook(Hook, {Filter, fun ?MODULE:Fun/3});
        'client.subscribe'    -> emqx:unhook(Hook, {Filter, fun ?MODULE:Fun/4});
        'client.unsubscribe'  -> emqx:unhook(Hook, {Filter, fun ?MODULE:Fun/4});
        'session.created'     -> emqx:unhook(Hook, {Filter, fun ?MODULE:Fun/3});
        'session.subscribed'  -> emqx:unhook(Hook, {Filter, fun ?MODULE:Fun/4});
        'session.unsubscribed'-> emqx:unhook(Hook, {Filter, fun ?MODULE:Fun/4});
        'session.terminated'  -> emqx:unhook(Hook, {Filter, fun ?MODULE:Fun/4});
        'message.publish'     -> emqx:unhook(Hook, {Filter, fun ?MODULE:Fun/2});
        'message.acked'       -> emqx:unhook(Hook, {Filter, fun ?MODULE:Fun/4});
        'message.delivered'   -> emqx:unhook(Hook, {Filter, fun ?MODULE:Fun/4})
    end.

