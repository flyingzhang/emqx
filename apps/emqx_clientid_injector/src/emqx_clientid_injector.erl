%%--------------------------------------------------------------------
%% Copyright (c) 2020-2025 EMQ Technologies Co., Ltd. All Rights Reserved.
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

-module(emqx_clientid_injector).

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/emqx_hooks.hrl").

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------
-export([load/0, unload/0]).

%% hook callback
-export([on_message_publish/1]).

%%--------------------------------------------------------------------
%% Load/Unload
%%--------------------------------------------------------------------

%% @doc 插件加载时调用,注册 hook
%% 使用 942 优先级,略高于 MESSAGE_TRANSFORMATION(943)
load() ->
    emqx_hooks:put('message.publish', {?MODULE, on_message_publish, []}, 942).

%% @doc 插件卸载时调用,注销 hook
unload() ->
    emqx_hooks:del('message.publish', {?MODULE, on_message_publish}).

%%--------------------------------------------------------------------
%% Hook Implementation
%%--------------------------------------------------------------------

%% @doc 消息发布时的 hook 回调
%% @param Message 原始消息
%% @returns {ok, Message} | {ok, NewMessage}
-spec on_message_publish(emqx_types:message()) -> {ok, emqx_types:message()}.
on_message_publish(Message = #message{from = ClientId, topic = Topic, headers = Headers}) ->
    %% 调试日志
    logger:info("[ClientIdInjector] Processing message from=~p topic=~p", [ClientId, Topic]),

    %% 1. 检查是否应该处理此消息
    case should_process(Topic) of
        false ->
            logger:info("[ClientIdInjector] Skipped (topic filter)"),
            {ok, Message};
        true ->
            %% 2. 读取配置
            Config = emqx_clientid_injector_config:get_config(),

            %% 3. 检查是否启用
            case maps:get(enable, Config, true) of
                false ->
                    logger:info("[ClientIdInjector] Skipped (disabled)"),
                    {ok, Message};
                true ->
                    %% 4. 注入 User Properties
                    NewHeaders = inject_properties(Headers, ClientId, Config),

                    %% 5. 返回修改后的消息
                    logger:info("[ClientIdInjector] Injected properties: ~p", [NewHeaders]),
                    {ok, Message#message{headers = NewHeaders}}
            end
    end.

%%--------------------------------------------------------------------
%% Internal Functions
%%--------------------------------------------------------------------

%% @doc 判断是否应该处理此消息
should_process(Topic) ->
    Config = emqx_clientid_injector_config:get_config(),

    %% 检查排除列表
    ExcludePrefixes = maps:get(exclude_prefixes, Config, [<<"$SYS/">>, <<"$share/">>]),
    case is_prefix_match(Topic, ExcludePrefixes) of
        true ->
            false;
        false ->
            %% 检查包含列表
            IncludePrefixes = maps:get(include_prefixes, Config, []),
            case IncludePrefixes of
                [] -> true;
                _ -> is_prefix_match(Topic, IncludePrefixes)
            end
    end.

%% @doc 检查 topic 是否匹配任何前缀
is_prefix_match(_Topic, []) ->
    false;
is_prefix_match(Topic, [Prefix | Rest]) ->
    PrefixSize = byte_size(Prefix),
    case Topic of
        <<Match:PrefixSize/binary, _/binary>> when Match =:= Prefix ->
            true;
        _ ->
            is_prefix_match(Topic, Rest)
    end.

%% @doc 注入 User Properties
inject_properties(Headers, ClientId, Config) ->
    %% 获取现有的 properties 字段
    Props = maps:get(properties, Headers, #{}),

    %% 获取现有的 User Properties
    ExistingProps = maps:get('User-Property', Props, []),

    %% 构建新的 Properties 列表
    NewProps = build_properties(ClientId, Config),

    %% 合并(新属性追加到前面,保留设备原有属性)
    MergedProps = NewProps ++ ExistingProps,

    %% 更新 properties 子字段
    PropsWithUserProp = maps:put('User-Property', MergedProps, Props),

    %% 更新 headers
    maps:put(properties, PropsWithUserProp, Headers).

%% @doc 根据配置构建要注入的属性列表
build_properties(ClientId, Config) ->
    Props0 = [],

    %% 注入 ClientId(始终启用)
    ClientIdKey = maps:get(clientid_key, Config, <<"x-emqx-clientid">>),
    Props1 = [{ClientIdKey, ensure_binary(ClientId)} | Props0],

    %% 可选:注入 Username
    Props2 =
        case maps:get(inject_username, Config, false) of
            true ->
                UsernameKey = maps:get(username_key, Config, <<"x-emqx-username">>),
                Username = get_client_username(ClientId),
                [{UsernameKey, Username} | Props1];
            false ->
                Props1
        end,

    %% 可选:注入 PeerName
    Props3 =
        case maps:get(inject_peername, Config, false) of
            true ->
                PeernameKey = maps:get(peername_key, Config, <<"x-emqx-peername">>),
                Peername = get_client_peername(ClientId),
                [{PeernameKey, Peername} | Props2];
            false ->
                Props2
        end,

    lists:reverse(Props3).

%% @doc 确保值为 binary
ensure_binary(Value) when is_binary(Value) ->
    Value;
ensure_binary(Value) when is_atom(Value) ->
    atom_to_binary(Value, utf8);
ensure_binary(Value) when is_list(Value) ->
    list_to_binary(Value);
ensure_binary(Value) when is_integer(Value) ->
    integer_to_binary(Value).

%% @doc 获取客户端的 Username
get_client_username(ClientId) ->
    case emqx_cm:get_chan_info(ClientId) of
        undefined -> <<"">>;
        ChanInfo -> maps:get(username, ChanInfo, <<"">>)
    end.

%% @doc 获取客户端的连接地址
get_client_peername(ClientId) ->
    case emqx_cm:get_chan_info(ClientId) of
        undefined ->
            <<"">>;
        ChanInfo ->
            case maps:get(peername, ChanInfo, undefined) of
                undefined ->
                    <<"">>;
                {IP, Port} ->
                    iolist_to_binary([inet:ntoa(IP), ":", integer_to_binary(Port)]);
                IP when is_tuple(IP) ->
                    %% 某些情况下只有 IP 没有 Port
                    iolist_to_binary([inet:ntoa(IP)])
            end
    end.
