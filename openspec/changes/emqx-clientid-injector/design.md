# Design: EMQX ClientId Injector Plugin

## 1. Architecture Overview

### 1.1 系统架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              EMQX Broker Cluster                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────┐     ┌──────────────────────┐     ┌─────────────────────┐  │
│   │   Device    │     │   Hook Chain         │     │   Subscriber        │  │
│   │  (MQTT 3/5) │     │                      │     │   (MQTT 5.0)        │  │
│   └──────┬──────┘     │  ┌────────────────┐  │     └─────────┬───────────┘  │
│          │            │  │ clientid_inj   │  │               │              │
│          │ PUBLISH    │  │ on_msg_publish │  │               │ SUBSCRIBE    │
│          │            │  └───────┬────────┘  │               │              │
│          ▼            │          │           │               ▼              │
│   ┌──────────────┐    │          ▼           │    ┌──────────────────────┐  │
│   │ message.pub  │───▶│  Inject User Props   │───▶│  Dispatch to Sub     │  │
│   │ hook point   │    │  {x-emqx-clientid:   │    │  (with User Props)   │  │
│   └──────────────┘    │   "device-001"}      │    └──────────────────────┘  │
│                       │                      │                              │
│                       └──────────────────────┘                              │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 核心组件

| 组件 | 职责 | 实现模块 |
|------|------|----------|
| **Hook Handler** | 拦截 `message.publish` 事件，注入 User Properties | `emqx_clientid_injector.erl` |
| **Config Manager** | 管理插件配置，支持热更新 | `emqx_clientid_injector_config.erl` |
| **App Supervisor** | OTP 应用生命周期管理 | `emqx_clientid_injector_app.erl` |

### 1.3 消息流转详解

```
Step 1: Device Publish
========================
Device (MQTT 3.1.1) ──PUBLISH──▶ EMQX Listener
                                     │
                                     ▼
                           Parse MQTT Packet
                                     │
                                     ▼
                           Create #message{} record
                           ┌─────────────────────────┐
                           │ #message{              │
                           │   id = <<...>>,        │
                           │   from = <<"dev-001">>,│  ◀── ClientId 已存在
                           │   topic = <<"neat/...">>,
                           │   headers = #{},       │  ◀── 空（MQTT 3.x）
                           │   payload = <<...>>   │
                           │ }                      │
                           └─────────────────────────┘

Step 2: Hook Chain Execution
===========================
                                     │
                                     ▼
                           'message.publish' hook
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
                    ▼                ▼                ▼
               AuthZ Check    ClientId Injector   Rule Engine
                              (OUR PLUGIN)
                                     │
                                     ▼
                           ┌─────────────────────────┐
                           │ Inject User Properties: │
                           │ headers = #{            │
                           │   'User-Property' => [  │
                           │     {<<"x-emqx-clientid">>, <<"dev-001">>}
                           │   ]                     │
                           │ }                       │
                           └─────────────────────────┘
                                     │
                                     ▼
                           Return {ok, ModifiedMessage}

Step 3: Dispatch to Subscribers
===============================
                                     │
                                     ▼
                           Route to Subscribers
                                     │
                    ┌────────────────┴────────────────┐
                    │                                 │
                    ▼                                 ▼
           MQTT 3.x Subscriber              MQTT 5.0 Subscriber
           (Props ignored)                  (Props included)
                                                     │
                                                     ▼
                                           ┌─────────────────────────┐
                                           │ PUBLISH Packet:         │
                                           │ Topic: neat/dev-001/up  │
                                           │ User Properties:        │
                                           │   x-emqx-clientid=dev-001
                                           │ Payload: {...}          │
                                           └─────────────────────────┘
```

## 2. 详细设计

### 2.1 EMQX Message Record 结构

```erlang
%% emqx_message.hrl
-record(message, {
    %% 全局唯一消息 ID
    id :: binary(),
    %% QoS 等级
    qos = 0,
    %% 发布者标识 (ClientId)  <-- 我们需要的值
    from :: atom() | binary(),
    %% 消息标志
    flags = #{} :: map(),
    %% 消息头 (包含 MQTT 5.0 Properties)  <-- 我们要修改的字段
    headers = #{} :: map(),
    %% Topic
    topic :: binary(),
    %% Payload
    payload :: iodata(),
    %% 时间戳
    timestamp :: integer(),
    %% 扩展字段
    extra = #{} :: term()
}).
```

**关键字段说明**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `from` | `binary()` | 发布者的 ClientId，即使是 MQTT 3.x 客户端也有此值 |
| `headers` | `map()` | MQTT 5.0 Properties 存放位置，包括 `'User-Property'` |

### 2.2 Headers 中 User-Property 格式

```erlang
%% User Properties 在 headers 中的存储格式
headers = #{
    'User-Property' => [
        {<<"key1">>, <<"value1">>},
        {<<"key2">>, <<"value2">>}
    ],
    %% 其他 MQTT 5.0 Properties...
    'Content-Type' => <<"application/json">>,
    'Response-Topic' => <<"response/topic">>
}.
```

### 2.3 模块设计

#### 2.3.1 主模块 `emqx_clientid_injector.erl`

```erlang
-module(emqx_clientid_injector).

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/emqx_hooks.hrl").

%%--------------------------------------------------------------------
%% Exports
%%--------------------------------------------------------------------
-export([load/1, unload/0]).
-export([on_message_publish/1]).

%%--------------------------------------------------------------------
%% 常量定义
%%--------------------------------------------------------------------
-define(DEFAULT_CLIENTID_KEY, <<"x-emqx-clientid">>).
-define(DEFAULT_USERNAME_KEY, <<"x-emqx-username">>).
-define(DEFAULT_PEERNAME_KEY, <<"x-emqx-peername">>).

%%--------------------------------------------------------------------
%% Load/Unload
%%--------------------------------------------------------------------

%% @doc 插件加载时调用，注册 hook
load(_Env) ->
    emqx:hook('message.publish', {?MODULE, on_message_publish, []}).

%% @doc 插件卸载时调用，注销 hook
unload() ->
    emqx:unhook('message.publish', {?MODULE, on_message_publish}).

%%--------------------------------------------------------------------
%% Hook Implementation
%%--------------------------------------------------------------------

%% @doc 消息发布时的 hook 回调
%% @param Message 原始消息
%% @returns {ok, Message} | {ok, NewMessage}
-spec on_message_publish(emqx_types:message()) -> {ok, emqx_types:message()}.
on_message_publish(Message = #message{from = ClientId, topic = Topic, headers = Headers}) ->
    %% 1. 检查是否应该处理此消息
    case should_process(Topic) of
        false ->
            {ok, Message};
        true ->
            %% 2. 读取配置
            Config = emqx_clientid_injector_config:get_config(),
            
            %% 3. 注入 User Properties
            NewHeaders = inject_properties(Headers, ClientId, Config),
            
            %% 4. 返回修改后的消息
            {ok, Message#message{headers = NewHeaders}}
    end.

%%--------------------------------------------------------------------
%% Internal Functions
%%--------------------------------------------------------------------

%% @doc 判断是否应该处理此消息
should_process(<<"$SYS/", _/binary>>) ->
    false;
should_process(<<"$share/", _/binary>>) ->
    false;
should_process(_Topic) ->
    true.

%% @doc 注入 User Properties
inject_properties(Headers, ClientId, Config) ->
    %% 获取现有的 User Properties
    ExistingProps = maps:get('User-Property', Headers, []),
    
    %% 构建新的 Properties 列表
    NewProps = build_properties(ClientId, Config),
    
    %% 合并（新属性追加到前面，保留设备原有属性）
    MergedProps = NewProps ++ ExistingProps,
    
    %% 更新 headers
    maps:put('User-Property', MergedProps, Headers).

%% @doc 根据配置构建要注入的属性列表
build_properties(ClientId, Config) ->
    Props0 = [],
    
    %% 注入 ClientId（始终启用）
    ClientIdKey = maps:get(clientid_key, Config, ?DEFAULT_CLIENTID_KEY),
    Props1 = [{ClientIdKey, ensure_binary(ClientId)} | Props0],
    
    %% 可选：注入 Username
    Props2 = case maps:get(inject_username, Config, false) of
        true ->
            UsernameKey = maps:get(username_key, Config, ?DEFAULT_USERNAME_KEY),
            Username = get_client_username(ClientId),
            [{UsernameKey, Username} | Props1];
        false ->
            Props1
    end,
    
    %% 可选：注入 PeerName
    Props3 = case maps:get(inject_peername, Config, false) of
        true ->
            PeernameKey = maps:get(peername_key, Config, ?DEFAULT_PEERNAME_KEY),
            Peername = get_client_peername(ClientId),
            [{PeernameKey, Peername} | Props2];
        false ->
            Props2
    end,
    
    Props3.

%% @doc 确保值为 binary
ensure_binary(Value) when is_binary(Value) -> Value;
ensure_binary(Value) when is_atom(Value) -> atom_to_binary(Value, utf8);
ensure_binary(Value) when is_list(Value) -> list_to_binary(Value).

%% @doc 获取客户端的 Username
get_client_username(ClientId) ->
    case emqx_cm:get_chan_info(ClientId) of
        undefined -> <<"">>;
        ChanInfo -> maps:get(username, ChanInfo, <<"">>)
    end.

%% @doc 获取客户端的连接地址
get_client_peername(ClientId) ->
    case emqx_cm:get_chan_info(ClientId) of
        undefined -> <<"">>;
        ChanInfo ->
            case maps:get(peername, ChanInfo, undefined) of
                undefined -> <<"">>;
                {IP, Port} ->
                    iolist_to_binary([inet:ntoa(IP), ":", integer_to_list(Port)])
            end
    end.
```

#### 2.3.2 配置模块 `emqx_clientid_injector_config.erl`

```erlang
-module(emqx_clientid_injector_config).

-export([get_config/0, update_config/1]).

%% @doc 获取当前配置
get_config() ->
    application:get_env(emqx_clientid_injector, config, default_config()).

%% @doc 更新配置
update_config(NewConfig) ->
    application:set_env(emqx_clientid_injector, config, NewConfig).

%% @doc 默认配置
default_config() ->
    #{
        enable => true,
        clientid_key => <<"x-emqx-clientid">>,
        inject_username => false,
        username_key => <<"x-emqx-username">>,
        inject_peername => false,
        peername_key => <<"x-emqx-peername">>,
        exclude_prefixes => [<<"$SYS/">>, <<"$share/">>]
    }.
```

#### 2.3.3 应用模块 `emqx_clientid_injector_app.erl`

```erlang
-module(emqx_clientid_injector_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    {ok, Sup} = emqx_clientid_injector_sup:start_link(),
    emqx_clientid_injector:load([]),
    {ok, Sup}.

stop(_State) ->
    emqx_clientid_injector:unload(),
    ok.
```

### 2.4 项目结构

```
emqx-clientid-injector/
├── src/
│   ├── emqx_clientid_injector.erl           # 主模块（hook 处理）
│   ├── emqx_clientid_injector_app.erl       # OTP 应用入口
│   ├── emqx_clientid_injector_sup.erl       # Supervisor
│   └── emqx_clientid_injector_config.erl    # 配置管理
├── include/
│   └── emqx_clientid_injector.hrl           # 头文件
├── priv/
│   ├── config.hocon                          # 默认配置
│   └── config_schema.avsc                    # Avro Schema（可选）
├── rebar.config                              # 构建配置
├── Makefile                                  # 构建脚本
└── README.md                                 # 说明文档
```

### 2.5 rebar.config 配置

```erlang
{erl_opts, [debug_info]}.

{deps, []}.

{relx, [
    {release, {emqx_clientid_injector, "1.0.0"}, [
        emqx_clientid_injector
    ]},
    {dev_mode, false},
    {include_erts, false}
]}.

{emqx_plugrel, [
    {authors, ["Guhe Cloud IoT Team"]},
    {builder, [
        {name, "Guhe Cloud"},
        {contact, "dev@guhecloud.com"},
        {website, "https://www.guhecloud.com"}
    ]},
    {repo, "https://github.com/guhecloud/emqx-clientid-injector"},
    {functionality, ["Message Processing"]},
    {compatibility, [
        {emqx, "~> 5.0"}
    ]},
    {description, "Inject ClientId and connection metadata into MQTT 5.0 User Properties"}
]}.
```

## 3. 配置详细说明

### 3.1 HOCON 配置格式

```hocon
## priv/config.hocon

clientid_injector {
    ## 是否启用插件功能
    ## 类型: boolean
    ## 默认值: true
    enable = true
    
    ## ClientId 属性配置
    properties {
        ## ClientId 的 User Property 键名
        ## 类型: string
        ## 默认值: "x-emqx-clientid"
        clientid_key = "x-emqx-clientid"
        
        ## 是否注入 username
        ## 类型: boolean
        ## 默认值: false
        inject_username = false
        
        ## Username 的 User Property 键名
        ## 类型: string
        ## 默认值: "x-emqx-username"
        username_key = "x-emqx-username"
        
        ## 是否注入 peername (客户端 IP:Port)
        ## 类型: boolean
        ## 默认值: false
        inject_peername = false
        
        ## PeerName 的 User Property 键名
        ## 类型: string
        ## 默认值: "x-emqx-peername"
        peername_key = "x-emqx-peername"
    }
    
    ## Topic 过滤配置
    topic_filter {
        ## 排除的 topic 前缀列表
        ## 匹配这些前缀的消息不会被处理
        ## 类型: array of string
        ## 默认值: ["$SYS/", "$share/"]
        exclude_prefixes = ["$SYS/", "$share/"]
        
        ## 仅处理的 topic 前缀列表
        ## 为空表示处理所有不在排除列表中的 topic
        ## 不为空时，只处理匹配这些前缀的消息
        ## 类型: array of string
        ## 默认值: []
        include_prefixes = []
    }
}
```

### 3.2 配置示例

**场景 1：仅注入 ClientId（最简配置）**

```hocon
clientid_injector {
    enable = true
}
```

**场景 2：完整元数据注入**

```hocon
clientid_injector {
    enable = true
    properties {
        clientid_key = "x-emqx-clientid"
        inject_username = true
        username_key = "x-emqx-username"
        inject_peername = true
        peername_key = "x-emqx-peername"
    }
}
```

**场景 3：仅处理特定协议的 Topic**

```hocon
clientid_injector {
    enable = true
    topic_filter {
        include_prefixes = ["neat/", "guhe/", "nit/"]
    }
}
```

## 4. 平台侧集成指南

### 4.1 升级 Paho MQTT 客户端至 v5

**Maven 依赖变更**:

```xml
<!-- 移除 MQTT 3.x 依赖 -->
<!-- 
<dependency>
    <groupId>org.eclipse.paho</groupId>
    <artifactId>org.eclipse.paho.client.mqttv3</artifactId>
    <version>1.2.5</version>
</dependency>
-->

<!-- 添加 MQTT 5.0 依赖 -->
<dependency>
    <groupId>org.eclipse.paho</groupId>
    <artifactId>org.eclipse.paho.mqttv5.client</artifactId>
    <version>1.2.5</version>
</dependency>
```

### 4.2 MqttClientEndpoint 改造示例

```java
package com.guhecloud.cube.iot.access.runtime.provider.mqtt;

import org.eclipse.paho.mqttv5.client.*;
import org.eclipse.paho.mqttv5.common.MqttMessage;
import org.eclipse.paho.mqttv5.common.packet.MqttProperties;
import org.eclipse.paho.mqttv5.common.packet.UserProperty;

import java.util.List;
import java.util.Optional;

public class MqttClientEndpoint implements Endpoint, Transport {

    // ... 其他代码保持不变 ...

    private class MqttUpstreamListener implements IMqttMessageListener {
        private final MqttClientProtocolBinding binding;

        public MqttUpstreamListener(MqttClientProtocolBinding binding) {
            this.binding = binding;
        }

        @Override
        public void messageArrived(String topic, MqttMessage message) {
            try {
                // 1. 优先从 User Properties 获取 ClientId
                Optional<String> clientIdOpt = extractClientIdFromUserProperties(message);
                
                // 2. Fallback: 从 Topic 解析（向后兼容）
                if (clientIdOpt.isEmpty()) {
                    clientIdOpt = binding.tryParseClientIdFromTopic(topic);
                }

                if (clientIdOpt.isEmpty()) {
                    log.warn("Binding [{}] could not determine clientId from topic [{}] or User Properties.",
                             binding.getProtocolId(), topic);
                    return;
                }

                String clientId = clientIdOpt.get();
                Optional<ConnectionContext> contextOpt = connectionContextManager.queryContext(clientId);

                if (contextOpt.isEmpty()) {
                    log.warn("No context found for client [{}] on upstream message from topic [{}].",
                             clientId, topic);
                    return;
                }

                accessLayerManager.handleUpstream(contextOpt.get(), new MqttUpstreamMessageImpl(topic, message));

            } catch (Exception e) {
                log.error("Error processing message by binding [{}] from topic [{}] on endpoint [{}]",
                          binding.getProtocolId(), topic, getId(), e);
            }
        }

        /**
         * 从 MQTT 5.0 User Properties 中提取 ClientId
         */
        private Optional<String> extractClientIdFromUserProperties(MqttMessage message) {
            MqttProperties props = message.getProperties();
            if (props == null) {
                return Optional.empty();
            }

            List<UserProperty> userProps = props.getUserProperties();
            if (userProps == null || userProps.isEmpty()) {
                return Optional.empty();
            }

            return userProps.stream()
                .filter(up -> "x-emqx-clientid".equals(up.getKey()))
                .map(UserProperty::getValue)
                .findFirst();
        }
    }
}
```

### 4.3 MqttUpstreamMessage 接口扩展（可选）

为了让 ProtocolBinding 能够访问 User Properties，可以扩展上行消息接口：

```java
public interface MqttUpstreamMessage {
    String topic();
    byte[] payload();
    int qos();
    
    // 新增方法
    default Optional<String> getUserProperty(String key) {
        return Optional.empty();
    }
    
    default Map<String, String> getAllUserProperties() {
        return Collections.emptyMap();
    }
}
```

## 5. 测试计划

### 5.1 单元测试

| 测试用例 | 输入 | 期望输出 |
|----------|------|----------|
| TC-01: MQTT 3.x 消息注入 | Message without User Props | Message with `x-emqx-clientid` |
| TC-02: MQTT 5.0 消息追加 | Message with existing User Props | Message with original + injected Props |
| TC-03: 系统消息跳过 | Message with topic `$SYS/...` | Message unchanged |
| TC-04: 配置禁用 | Config `enable = false` | Message unchanged |

### 5.2 集成测试

```bash
# 1. 启动 EMQX 并加载插件
$ docker run -d --name emqx -p 1883:1883 -p 18083:18083 emqx/emqx:5.8.0
$ docker cp emqx_clientid_injector-1.0.0.tar.gz emqx:/opt/emqx/plugins/
$ docker exec emqx emqx ctl plugins install emqx_clientid_injector-1.0.0.tar.gz
$ docker exec emqx emqx ctl plugins start emqx_clientid_injector

# 2. 使用 MQTT 3.x 客户端发布消息
$ mosquitto_pub -h localhost -p 1883 -i "test-device-001" -t "neat/test/data" -m "hello"

# 3. 使用 MQTT 5.0 客户端订阅并验证 User Properties
$ python3 -c "
import paho.mqtt.client as mqtt

def on_message(client, userdata, msg):
    print(f'Topic: {msg.topic}')
    if hasattr(msg.properties, 'UserProperty'):
        for k, v in msg.properties.UserProperty:
            print(f'User Property: {k}={v}')
    # 期望输出: User Property: x-emqx-clientid=test-device-001

client = mqtt.Client(protocol=mqtt.MQTTv5)
client.on_message = on_message
client.connect('localhost', 1883)
client.subscribe('neat/#')
client.loop_forever()
"
```

### 5.3 性能测试

```bash
# 使用 emqtt_bench 进行压测
$ emqtt_bench pub -c 1000 -I 100 -t "bench/%c/data" -s 256 -h localhost

# 监控指标
# - 消息延迟增加 < 0.1ms
# - CPU 使用率增加 < 5%
# - 内存使用量增加 < 50MB
```

## 6. 部署指南

### 6.1 构建插件

```bash
# 克隆项目
$ git clone https://github.com/guhecloud/emqx-clientid-injector.git
$ cd emqx-clientid-injector

# 下载依赖（确保 rebar3 已安装）
$ rebar3 deps

# 构建 release
$ make rel

# 生成插件包
$ ls _build/default/emqx_plugrel/
emqx_clientid_injector-1.0.0.tar.gz
```

### 6.2 安装插件

**方式一：通过 Dashboard**

1. 登录 EMQX Dashboard (http://localhost:18083)
2. 导航到 `Management` → `Plugins`
3. 点击 `Install Plugin`，上传 `emqx_clientid_injector-1.0.0.tar.gz`
4. 点击 `Start` 启动插件

**方式二：通过 CLI**

```bash
$ emqx ctl plugins install emqx_clientid_injector-1.0.0.tar.gz
$ emqx ctl plugins start emqx_clientid_injector
```

**方式三：通过 REST API**

```bash
# 上传并安装
$ curl -X POST -F "plugin=@emqx_clientid_injector-1.0.0.tar.gz" \
    "http://admin:public@localhost:18083/api/v5/plugins/install"

# 启动
$ curl -X PUT "http://admin:public@localhost:18083/api/v5/plugins/emqx_clientid_injector/start"
```

### 6.3 验证安装

```bash
$ emqx ctl plugins list
Plugin(emqx_clientid_injector, version=1.0.0, running=true)
```

## 7. 监控与运维

### 7.1 日志配置

```hocon
log.file.level = debug  # 调试时开启
```

插件日志示例：

```
2026-01-08T12:00:00.123456+08:00 [debug] [clientid_injector] 
  Injected properties for client "device-001": [{<<"x-emqx-clientid">>,<<"device-001">>}]
```

### 7.2 健康检查

可通过 EMQX REST API 检查插件状态：

```bash
$ curl "http://admin:public@localhost:18083/api/v5/plugins/emqx_clientid_injector"
{
  "name": "emqx_clientid_injector",
  "version": "1.0.0",
  "running": true,
  "config": {
    "enable": true,
    ...
  }
}
```

## 8. 版本兼容性

| EMQX 版本 | 插件版本 | 兼容性 |
|-----------|----------|--------|
| 5.0.x | 1.0.0 | ✅ 支持 |
| 5.1.x | 1.0.0 | ✅ 支持 |
| 5.8.x | 1.0.0 | ✅ 支持（主要目标版本）|
| 4.x | - | ❌ 不支持（Hook API 不兼容）|
