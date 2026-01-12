# EMQX ClientId Injector Plugin

自动将发布者的 ClientId 注入到 MQTT 5.0 User Properties 中的 EMQX 插件。

## 功能

- 在消息发布时自动注入 `ClientId` 到 MQTT 5.0 User Properties
- 可选注入 `Username` 和 `PeerName`(客户端 IP:Port)
- 支持配置 Topic 过滤规则(排除/包含前缀)
- 保留设备自带的 User Properties(追加而非覆盖)
- 跳过系统消息(`$SYS/` 前缀)

## 应用场景

此插件解决了平台侧 MQTT 5.0 客户端需要获取发布者 ClientId 但依赖 Topic 解析的问题:

1. **协议无关性**: 设备可以使用固定 Topic 结构(如 `sensor/data`)而不必包含设备标识
2. **向后兼容**: 平台侧可优先从 User Properties 获取 ClientId,fallback 到 Topic 解析
3. **MQTT 3.x 兼容**: 设备使用 MQTT 3.x 发布,平台使用 MQTT 5.0 订阅,仍能获取 ClientId

## 架构

```
Device (MQTT 3/5) ──PUBLISH──▶ EMQX ──▶ Subscriber (MQTT 5.0)
                               │
                               └─ Hook: Inject x-emqx-clientid
```

## 配置

### 基本配置

```hocon
clientid_injector {
    enable = true
}
```

### 完整配置

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

    topic_filter {
        exclude_prefixes = ["$SYS/", "$share/"]
        include_prefixes = []
    }
}
```

### 配置说明

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `enable` | boolean | true | 是否启用插件 |
| `properties.clientid_key` | string | "x-emqx-clientid" | ClientId 的属性键名 |
| `properties.inject_username` | boolean | false | 是否注入用户名 |
| `properties.username_key` | string | "x-emqx-username" | 用户名的属性键名 |
| `properties.inject_peername` | boolean | false | 是否注入客户端地址 |
| `properties.peername_key` | string | "x-emqx-peername" | 客户端地址的属性键名 |
| `topic_filter.exclude_prefixes` | array | ["$SYS/", "$share/"] | 排除的 Topic 前缀 |
| `topic_filter.include_prefixes` | array | [] | 仅处理的 Topic 前缀 |

## 使用示例

### 设备端(任意 MQTT 版本)

```bash
mosquitto_pub -h localhost -i "device-001" -t "sensor/data" -m "hello"
```

### 订阅端(MQTT 5.0)

使用 Python Paho MQTT 5.0 客户端:

```python
import paho.mqtt.client as mqtt

def on_message(client, userdata, msg):
    print(f'Topic: {msg.topic}')
    if hasattr(msg.properties, 'UserProperty'):
        for key, value in msg.properties.UserProperty:
            print(f'{key} = {value}')
    # 输出: x-emqx-clientid = device-001

client = mqtt.Client(protocol=mqtt.MQTTv5)
client.on_message = on_message
client.connect('localhost', 1883)
client.subscribe('sensor/#')
client.loop_forever()
```

## 安装

### 方式一: 放入 EMQX 插件目录

```bash
cp -r emqx_clientid_injector /path/to/emqx/lib/
```

### 方式二: 通过 Dashboard

1. 登录 EMQX Dashboard
2. 导航到 `Management` → `Plugins`
3. 启动 `emqx_clientid_injector`

### 方式三: 通过 CLI

```bash
emqx ctl plugins start emqx_clientid_injector
```

## 性能影响

- 额外延迟: < 0.1ms
- 额外内存: < 100 bytes/消息

## 许可证

Apache License 2.0
