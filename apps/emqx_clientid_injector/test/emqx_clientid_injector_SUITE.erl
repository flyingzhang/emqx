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
-module(emqx_clientid_injector_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/emqx_hooks.hrl").

%%--------------------------------------------------------------------
%% Suite callbacks
%%--------------------------------------------------------------------

all() ->
    [
        {group, basic_tests},
        {group, topic_filter_tests},
        {group, optional_properties_tests},
        {group, edge_case_tests}
    ].

groups() ->
    [
        {basic_tests, [sequence], [
            t_clientid_injection,
            t_preserve_existing_properties,
            t_plugin_disabled
        ]},
        {topic_filter_tests, [sequence], [
            t_exclude_system_messages,
            t_exclude_custom_prefixes,
            t_include_prefixes
        ]},
        {optional_properties_tests, [sequence], [
            t_inject_username,
            t_inject_peername
        ]},
        {edge_case_tests, [sequence], [
            t_empty_clientid,
            t_special_characters_clientid,
            t_unicode_clientid
        ]}
    ].

init_per_suite(Config) ->
    Apps = emqx_cth_suite:start(
        [emqx, emqx_conf, emqx_clientid_injector],
        #{work_dir => emqx_cth_suite:work_dir(Config)}
    ),
    [{apps, Apps} | Config].

end_per_suite(Config) ->
    emqx_cth_suite:stop(proplists:get_value(apps, Config)).

init_per_group(_Group, Config) ->
    Config.

end_per_group(_Group, _Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    % 重置配置为默认值
    application:set_env(emqx_clientid_injector, config, default_config()),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% Test cases - Basic functionality
%%--------------------------------------------------------------------

t_clientid_injection(_Config) ->
    % Given: 一个消息，没有 User Properties
    ClientId = <<"test-device-001">>,
    Message = #message{
        id = emqx_guid:gen(),
        from = ClientId,
        topic = <<"test/topic">>,
        headers = #{},
        payload = <<"hello">>,
        timestamp = erlang:system_time(millisecond)
    },

    % When: 通过 hook 处理消息
    {ok, ResultMessage} = emqx_clientid_injector:on_message_publish(Message),

    % Then: 应该包含 x-emqx-clientid 属性
    Headers = ResultMessage#message.headers,
    ?assertMatch({_, _}, maps:get('User-Property', Headers, undefined)),
    UserProps = maps:get('User-Property', Headers),
    ?assertEqual(1, length(UserProps)),
    ?assertEqual(<<"x-emqx-clientid">>, element(1, hd(UserProps))),
    ?assertEqual(ClientId, element(2, hd(UserProps))).

t_preserve_existing_properties(_Config) ->
    % Given: MQTT 5.0 消息，包含原有的 User Properties
    ClientId = <<"device-001">>,
    OriginalProps = [{<<"custom-key">>, <<"custom-value">>}],
    Message = #message{
        id = emqx_guid:gen(),
        from = ClientId,
        topic = <<"test/topic">>,
        headers = #{'User-Property' => OriginalProps},
        payload = <<"hello">>,
        timestamp = erlang:system_time(millisecond)
    },

    % When: 通过 hook 处理消息
    {ok, ResultMessage} = emqx_clientid_injector:on_message_publish(Message),

    % Then: 应该保留原有属性，并添加新属性
    Headers = ResultMessage#message.headers,
    UserProps = maps:get('User-Property', Headers),

    % 新属性在前面
    ?assertEqual(2, length(UserProps)),
    ?assertEqual(<<"x-emqx-clientid">>, element(1, lists:nth(1, UserProps))),
    ?assertEqual(ClientId, element(2, lists:nth(1, UserProps))),

    % 原有属性在后面
    ?assertEqual(<<"custom-key">>, element(1, lists:nth(2, UserProps))),
    ?assertEqual(<<"custom-value">>, element(2, lists:nth(2, UserProps))).

t_plugin_disabled(_Config) ->
    % Given: 插件被禁用
    BaseConfig = default_config(),
    DisabledConfig = BaseConfig#{enable => false},
    application:set_env(emqx_clientid_injector, config, DisabledConfig),

    ClientId = <<"device-001">>,
    Message = #message{
        id = emqx_guid:gen(),
        from = ClientId,
        topic = <<"test/topic">>,
        headers = #{},
        payload = <<"hello">>,
        timestamp = erlang:system_time(millisecond)
    },

    % When: 通过 hook 处理消息
    {ok, ResultMessage} = emqx_clientid_injector:on_message_publish(Message),

    % Then: 消息不应该被修改
    ?assertEqual(Message, ResultMessage).

%%--------------------------------------------------------------------
%% Test cases - Topic filtering
%%--------------------------------------------------------------------

t_exclude_system_messages(_Config) ->
    % Given: 系统消息
    ClientId = <<"device-001">>,
    SystemTopics = [
        <<"$SYS/broker/stats">>,
        <<"$SYS/broker/version">>,
        <<"$share/group1/topic">>
    ],

    lists:foreach(
        fun(Topic) ->
            Message = #message{
                id = emqx_guid:gen(),
                from = ClientId,
                topic = Topic,
                headers = #{},
                payload = <<"data">>,
                timestamp = erlang:system_time(millisecond)
            },

            % When: 处理系统消息
            {ok, ResultMessage} = emqx_clientid_injector:on_message_publish(Message),

            % Then: 不应该注入 User Properties
            Headers = ResultMessage#message.headers,
            ?assertEqual(undefined, maps:get('User-Property', Headers, undefined))
        end,
        SystemTopics
    ).

t_exclude_custom_prefixes(_Config) ->
    % Given: 配置自定义排除前缀
    Config = default_config(),
    CustomConfig = Config#{exclude_prefixes => [<<"$SYS/">>, <<"$share/">>, <<"debug/">>]},
    application:set_env(emqx_clientid_injector, config, CustomConfig),

    ClientId = <<"device-001">>,

    % When: 处理 debug/ 前缀的消息
    Message = #message{
        id = emqx_guid:gen(),
        from = ClientId,
        topic = <<"debug/test">>,
        headers = #{},
        payload = <<"data">>,
        timestamp = erlang:system_time(millisecond)
    },

    {ok, ResultMessage} = emqx_clientid_injector:on_message_publish(Message),

    % Then: 不应该注入 User Properties
    Headers = ResultMessage#message.headers,
    ?assertEqual(undefined, maps:get('User-Property', Headers, undefined)).

t_include_prefixes(_Config) ->
    % Given: 配置包含前缀
    Config = default_config(),
    CustomConfig = Config#{include_prefixes => [<<"neat/">>, <<"sensor/">>]},
    application:set_env(emqx_clientid_injector, config, CustomConfig),

    ClientId = <<"device-001">>,

    % When: 处理不同前缀的消息
    SensorMessage = #message{
        id = emqx_guid:gen(),
        from = ClientId,
        topic = <<"sensor/data">>,
        headers = #{},
        payload = <<"data">>,
        timestamp = erlang:system_time(millisecond)
    },

    OtherMessage = #message{
        id = emqx_guid:gen(),
        from = ClientId,
        topic = <<"other/topic">>,
        headers = #{},
        payload = <<"data">>,
        timestamp = erlang:system_time(millisecond)
    },

    {ok, SensorResult} = emqx_clientid_injector:on_message_publish(SensorMessage),
    {ok, OtherResult} = emqx_clientid_injector:on_message_publish(OtherMessage),

    % Then: sensor/data 应该被注入，other/topic 不应该
    SensorHeaders = SensorResult#message.headers,
    ?assertNotEqual(undefined, maps:get('User-Property', SensorHeaders)),

    OtherHeaders = OtherResult#message.headers,
    ?assertEqual(undefined, maps:get('User-Property', OtherHeaders, undefined)).

%%--------------------------------------------------------------------
%% Test cases - Optional properties
%%--------------------------------------------------------------------

t_inject_username(_Config) ->
    % Given: 配置注入 username
    Config = default_config(),
    CustomConfig = Config#{inject_username => true},
    application:set_env(emqx_clientid_injector, config, CustomConfig),

    % Mock emqx_cm:get_chan_info
    meck:new(emqx_cm, [passthrough]),
    meck:expect(emqx_cm, get_chan_info, fun(_) ->
        #{username => <<"user1">>}
    end),

    try
        ClientId = <<"device-001">>,
        Message = #message{
            id = emqx_guid:gen(),
            from = ClientId,
            topic = <<"test/topic">>,
            headers = #{},
            payload = <<"hello">>,
            timestamp = erlang:system_time(millisecond)
        },

        % When: 处理消息
        {ok, ResultMessage} = emqx_clientid_injector:on_message_publish(Message),

        % Then: 应该包含 username
        Headers = ResultMessage#message.headers,
        UserProps = maps:get('User-Property', Headers),

        ?assertEqual(2, length(UserProps)),
        ?assert(lists:keymember(<<"x-emqx-username">>, 1, UserProps))
    after
        meck:unload(emqx_cm)
    end.

t_inject_peername(_Config) ->
    % Given: 配置注入 peername
    Config = default_config(),
    CustomConfig = Config#{inject_peername => true},
    application:set_env(emqx_clientid_injector, config, CustomConfig),

    % Mock emqx_cm:get_chan_info
    meck:new(emqx_cm, [passthrough]),
    meck:expect(emqx_cm, get_chan_info, fun(_) ->
        #{peername => {{192, 168, 1, 100}, 12345}}
    end),

    try
        ClientId = <<"device-001">>,
        Message = #message{
            id = emqx_guid:gen(),
            from = ClientId,
            topic = <<"test/topic">>,
            headers = #{},
            payload = <<"hello">>,
            timestamp = erlang:system_time(millisecond)
        },

        % When: 处理消息
        {ok, ResultMessage} = emqx_clientid_injector:on_message_publish(Message),

        % Then: 应该包含 peername
        Headers = ResultMessage#message.headers,
        UserProps = maps:get('User-Property', Headers),

        ?assertEqual(2, length(UserProps)),
        ?assert(lists:keymember(<<"x-emqx-peername">>, 1, UserProps)),
        {_, PeerName} = lists:keyfind(<<"x-emqx-peername">>, 1, UserProps),
        ?assertEqual(<<"192.168.1.100:12345">>, PeerName)
    after
        meck:unload(emqx_cm)
    end.

%%--------------------------------------------------------------------
%% Test cases - Edge cases
%%--------------------------------------------------------------------

t_empty_clientid(_Config) ->
    % Given: 空的 ClientId
    Message = #message{
        id = emqx_guid:gen(),
        from = <<"">>,
        topic = <<"test/topic">>,
        headers = #{},
        payload = <<"hello">>,
        timestamp = erlang:system_time(millisecond)
    },

    % When: 处理消息
    {ok, ResultMessage} = emqx_clientid_injector:on_message_publish(Message),

    % Then: 应该能够处理（不崩溃）
    Headers = ResultMessage#message.headers,
    UserProps = maps:get('User-Property', Headers, undefined),
    ?assertNotEqual(undefined, UserProps).

t_special_characters_clientid(_Config) ->
    % Given: 包含特殊字符的 ClientId
    ClientIds = [
        <<"device+001">>,
        <<"device@domain.com">>,
        <<"device/001">>
    ],

    lists:foreach(
        fun(ClientId) ->
            Message = #message{
                id = emqx_guid:gen(),
                from = ClientId,
                topic = <<"test/topic">>,
                headers = #{},
                payload = <<"hello">>,
                timestamp = erlang:system_time(millisecond)
            },

            % When: 处理消息
            {ok, ResultMessage} = emqx_clientid_injector:on_message_publish(Message),

            % Then: 应该正确处理
            Headers = ResultMessage#message.headers,
            UserProps = maps:get('User-Property', Headers),
            {_, InjectedClientId} = lists:keyfind(<<"x-emqx-clientid">>, 1, UserProps),
            ?assertEqual(ClientId, InjectedClientId)
        end,
        ClientIds
    ).

t_unicode_clientid(_Config) ->
    % Given: Unicode 字符的 ClientId
    ClientIds = [
        <<"设备-001">>,
        <<"device-测试">>
    ],

    lists:foreach(
        fun(ClientId) ->
            Message = #message{
                id = emqx_guid:gen(),
                from = ClientId,
                topic = <<"test/topic">>,
                headers = #{},
                payload = <<"hello">>,
                timestamp = erlang:system_time(millisecond)
            },

            % When: 处理消息
            {ok, ResultMessage} = emqx_clientid_injector:on_message_publish(Message),

            % Then: 应该正确编码
            Headers = ResultMessage#message.headers,
            UserProps = maps:get('User-Property', Headers),
            {_, InjectedClientId} = lists:keyfind(<<"x-emqx-clientid">>, 1, UserProps),
            ?assertEqual(ClientId, InjectedClientId)
        end,
        ClientIds
    ).

%%--------------------------------------------------------------------
%% Helper functions
%%--------------------------------------------------------------------

default_config() ->
    #{
        enable => true,
        clientid_key => <<"x-emqx-clientid">>,
        inject_username => false,
        username_key => <<"x-emqx-username">>,
        inject_peername => false,
        peername_key => <<"x-emqx-peername">>,
        exclude_prefixes => [<<"$SYS/">>, <<"$share/">>],
        include_prefixes => []
    }.
