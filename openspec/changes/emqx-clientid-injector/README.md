# EMQX ClientId Injector Plugin

## 概述

EMQX ClientId Injector 是一个 EMQX 5.x 插件，用于在消息发布时自动注入发布者的连接元数据（ClientId、Username、PeerName 等）到 MQTT 5.0 User Properties 中。

## 问题背景

在 IoT 平台接入层中，`MqttClientEndpoint` 需要从上行消息中识别设备身份。当前实现依赖从 Topic 中解析 ClientId，这限制了协议的灵活性，无法支持使用固定 Topic 结构的第三方设备。

## 解决方案

通过 EMQX 插件在 `message.publish` hook 中直接修改消息，将 ClientId 注入到 MQTT 5.0 User Properties，使平台侧 MQTT 5.0 客户端能够获取这些信息，无需依赖 Topic 解析。

## 文档结构

| 文档 | 描述 |
|------|------|
| [proposal.md](proposal.md) | 提案文档：问题分析、解决方案选型、技术要求 |
| [design.md](design.md) | 设计文档：架构设计、模块详细设计、配置说明 |
| [specs/spec.md](specs/spec.md) | 规格说明书：详细需求场景定义 |
| [tasks.md](tasks.md) | 任务清单：开发任务分解 |

## 快速参考

### 核心功能

1. **ClientId 注入**：将发布者 ClientId 注入到 `x-emqx-clientid` User Property
2. **可选属性注入**：支持 Username 和 PeerName 注入
3. **Topic 过滤**：支持基于前缀的 include/exclude 过滤规则
4. **热加载**：支持不重启 EMQX 安装/卸载插件

### 配置示例

```hocon
clientid_injector {
    enable = true
    properties {
        clientid_key = "x-emqx-clientid"
        inject_username = false
        inject_peername = false
    }
    topic_filter {
        exclude_prefixes = ["$SYS/", "$share/"]
    }
}
```

### 消息流转

```
[设备 MQTT 3.x]          [EMQX + Plugin]           [平台 MQTT 5.0]
      │                        │                         │
      │ PUBLISH                │                         │
      │ topic: neat/xxx/data   │                         │
      ├───────────────────────▶│                         │
      │                        │ Inject User Props       │
      │                        │ x-emqx-clientid: xxx    │
      │                        ├────────────────────────▶│
      │                        │                    (收到带 Props)
```

## 相关模块

### EMQX 插件 (在单独工作区开发)
- `emqx_clientid_injector.erl` - Hook 处理主逻辑
- `emqx_clientid_injector_config.erl` - 配置管理

### IoT 平台 (本工作区)
- `MqttClientEndpoint.java` - 需改造以支持从 User Properties 获取 ClientId
- `MqttUpstreamMessage.java` - 可选扩展接口

## 版本兼容性

| 组件 | 版本要求 |
|------|----------|
| EMQX | 5.0+ (目标 5.8.x) |
| Eclipse Paho (平台侧) | mqttv5.client 1.2.5+ |

## 状态

- [x] 提案文档
- [x] 设计文档
- [x] 规格说明书
- [x] 任务清单
- [ ] 插件实现 (待在 EMQX 工作区完成)
- [ ] 平台侧集成 (待完成)
