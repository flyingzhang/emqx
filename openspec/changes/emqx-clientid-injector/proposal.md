# Proposal: EMQX ClientId Injector 插件

## 1. 目标 (Goal)

设计并实现一个 EMQX Broker 插件，在消息发布时**自动注入**发布者的连接元数据（ClientId、Username、PeerName 等）到 MQTT 5.0 User Properties 中，使平台侧 MQTT 5.0 客户端能够在订阅时获取这些信息，**无需依赖 Topic 解析**来识别设备身份。

## 2. 背景与问题分析 (Background & Problem Analysis)

### 2.1 当前架构限制

在现有的 `MqttClientEndpoint` 实现中，`MqttUpstreamListener.messageArrived` 方法依赖从 Topic 中解析 ClientId：

```java
@Override
public void messageArrived(String topic, MqttMessage message) {
    Optional<String> clientIdOpt = binding.tryParseClientIdFromTopic(topic);
    if (clientIdOpt.isEmpty()) {
        log.warn("Binding [{}] could not parse clientId from topic [{}].", 
                 binding.getProtocolId(), topic);
        return;  // 消息被丢弃！
    }
    // ...
}
```

**问题**：
1. **协议限制**：要求所有协议的 Topic 模板中必须包含设备标识（如 `neat/+/{imei}/+/up`）
2. **第三方协议不兼容**：无法支持使用固定 Topic 结构的第三方设备（如 `sensor/data`）
3. **MQTT 3.x 客户端限制**：Eclipse Paho MQTT 3.1.1 的 `MqttMessage` 只能访问 topic 和 payload

### 2.2 根本原因

**MQTT 3.x 协议设计缺陷**：MQTT 3.1.1 没有提供将连接级元数据（如 ClientId）传递到消息订阅者的机制。MQTT 5.0 通过引入 **User Properties** 解决了这个问题，但需要 Broker 层面的支持。

### 2.3 平台架构约束

```
┌──────────────────────────────────────────────────────────────────┐
│                        IoT 平台接入层                              │
├──────────────────────────────────────────────────────────────────┤
│   [设备]                    [EMQX Broker]              [平台]     │
│   MQTT 3.x/5.0              (需要插件)               MQTT 5.0    │
│      ┃                          ┃                        ┃       │
│      ┃ PUBLISH                  ┃                        ┃       │
│      ┃ topic: neat/xxx/data     ┃                        ┃       │
│      ┃ (无 User Properties)     ┃                        ┃       │
│      ┗━━━━━━━━━━━━━━━━━━━━━━━━━▶┃                        ┃       │
│                                 ┃ [Plugin: 注入 Props]    ┃       │
│                                 ┃ x-emqx-clientid: xxx   ┃       │
│                                 ┃━━━━━━━━━━━━━━━━━━━━━━━▶┃       │
│                                 ┃                 (收到带 Props) │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## 3. 解决方案选型 (Solution Options)

| 方案 | 描述 | 优点 | 缺点 | 推荐 |
|------|------|------|------|------|
| **A. EMQX 插件直接修改** | 在 `message.publish` hook 原地修改消息 | 零额外转发；Topic 不变；性能最优 | 需 Erlang 开发 | ✅ **推荐** |
| B. EMQX Rule Engine Republish | 通过规则引擎重新发布带 Props 的消息 | 无需开发；配置即用 | 额外消息转发；可能需改 Topic | ❌ |
| C. 设备侧改造 | 要求设备升级到 MQTT 5.0 并自带 Props | 最直接 | 不现实；无法改造存量设备 | ❌ |
| D. Webhook 扩展消息 | 每条消息调用 HTTP 接口查询元数据 | 利用现有 webhook 机制 | 性能极差；不适合高频消息 | ❌ |

### 3.1 选择方案 A 的理由

1. **零性能开销**：消息在 Broker 内部直接修改，无额外复制或转发
2. **协议透明**：设备无需任何改造，无论 MQTT 3.x 还是 5.0
3. **Topic 结构不变**：对现有订阅和 ACL 规则完全透明
4. **一次开发，永久受益**：通用能力，可服务于所有协议插件

## 4. 关键问题澄清 (Key Questions & Clarifications)

| 问题 | 澄清 |
|------|------|
| **Q1**: 设备使用 MQTT 3.x 发布消息，能否在接收端看到 User Properties？ | **A**: 可以。EMQX 内部统一使用 `#message{}` record 处理消息，`headers` 字段存放 MQTT 5.0 Properties。当向 MQTT 5.0 订阅者投递时，EMQX 会自动将 `headers` 编码为 User Properties。 |
| **Q2**: 插件对消息的修改会影响其他订阅者吗？ | **A**: 不会影响 MQTT 3.x 订阅者（协议不支持 User Properties，EMQX 会自动忽略）；MQTT 5.0 订阅者会收到注入的 Props。 |
| **Q3**: 是否需要考虑消息转发到其他节点的场景？ | **A**: 是的。EMQX 集群内转发的消息会携带完整的 `#message{}` record，包括修改后的 `headers`。 |
| **Q4**: 对 EMQX Enterprise 和 Open Source 的兼容性？ | **A**: 两者均支持此方案。插件机制在两个版本中一致。 |

## 5. 技术要求 (Technical Requirements)

### 5.1 功能性要求

| ID | 要求 | 优先级 |
|----|------|--------|
| FR-01 | 插件必须在 `message.publish` hook 中注入 User Properties | **必须** |
| FR-02 | 必须注入 `x-emqx-clientid` 属性，值为发布者的 ClientId | **必须** |
| FR-03 | 应支持可选注入 `x-emqx-username` 属性 | 应该 |
| FR-04 | 应支持可选注入 `x-emqx-peername` 属性（客户端 IP:Port）| 应该 |
| FR-05 | 必须跳过系统消息（`$SYS/` 前缀的 Topic）| **必须** |
| FR-06 | 应支持通过配置指定要处理的 Topic 前缀白名单 | 可选 |
| FR-07 | 应保留设备自己设置的 User Properties（追加而非覆盖）| **必须** |

### 5.2 非功能性要求

| ID | 要求 | 指标 |
|----|------|------|
| NFR-01 | 性能影响 | 消息处理延迟增加 < 0.1ms |
| NFR-02 | 内存影响 | 每条消息额外内存 < 100 bytes |
| NFR-03 | EMQX 版本兼容 | 支持 EMQX 5.0+ (目标 5.8.x) |
| NFR-04 | 热加载 | 支持不重启 Broker 加载/卸载插件 |

### 5.3 配置要求

插件应支持以下配置项：

```hocon
clientid_injector {
    # 是否启用注入功能
    enable = true
    
    # 注入的属性配置
    properties {
        # ClientId 属性键名
        clientid_key = "x-emqx-clientid"
        
        # 是否注入 username
        inject_username = false
        username_key = "x-emqx-username"
        
        # 是否注入 peername
        inject_peername = false
        peername_key = "x-emqx-peername"
    }
    
    # Topic 过滤规则
    topic_filter {
        # 排除的 topic 前缀
        exclude_prefixes = ["$SYS/", "$share/"]
        
        # 仅处理的 topic 前缀（为空表示处理所有）
        include_prefixes = []
    }
}
```

## 6. 与平台侧的协同改造 (Platform-Side Integration)

### 6.1 MqttClientEndpoint 改造

**改造前**：依赖 `tryParseClientIdFromTopic(topic)`

**改造后**：优先从 User Properties 获取 ClientId

```java
@Override
public void messageArrived(String topic, MqttMessage message) {
    // 1. 优先从 User Properties 获取
    Optional<String> clientIdOpt = extractClientIdFromUserProperties(message);
    
    // 2. Fallback: 从 Topic 解析
    if (clientIdOpt.isEmpty()) {
        clientIdOpt = binding.tryParseClientIdFromTopic(topic);
    }
    
    if (clientIdOpt.isEmpty()) {
        log.warn("Could not determine clientId from topic [{}] or User Properties.", topic);
        return;
    }
    // ...
}
```

### 6.2 MQTT 客户端升级

**依赖变更**：

```xml
<!-- 从 -->
<dependency>
    <groupId>org.eclipse.paho</groupId>
    <artifactId>org.eclipse.paho.client.mqttv3</artifactId>
</dependency>

<!-- 改为 -->
<dependency>
    <groupId>org.eclipse.paho</groupId>
    <artifactId>org.eclipse.paho.mqttv5.client</artifactId>
</dependency>
```

## 7. 风险与缓解 (Risks & Mitigations)

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| Erlang 开发能力不足 | 插件开发周期延长 | 基于 `emqx-plugin-template` 快速启动；参考官方示例 |
| EMQX 版本升级导致 API 变化 | 插件不兼容 | 锁定 EMQX 5.8.x 版本；关注 EMQX Release Notes |
| 高并发场景性能下降 | 消息延迟增加 | 压测验证；必要时使用 NIF 优化 |
| 配置错误导致消息处理异常 | 服务不可用 | 完善配置校验；提供健康检查 API |

## 8. 验收标准 (Acceptance Criteria)

1. **功能验收**：
   - [ ] MQTT 3.1.1 设备发布消息，MQTT 5.0 平台订阅者收到消息时包含 `x-emqx-clientid` 属性
   - [ ] MQTT 5.0 设备自带 User Properties 不被覆盖
   - [ ] `$SYS/` 系统消息不被处理

2. **性能验收**：
   - [ ] 1万条/秒消息吞吐量下，额外延迟 < 0.1ms

3. **运维验收**：
   - [ ] 插件可通过 Dashboard 安装/卸载
   - [ ] 配置变更实时生效

## 9. 参考资料

- [EMQX 5.x Plugin Development Guide](https://docs.emqx.com/en/emqx/v5.8/extensions/plugins.html)
- [EMQX Hooks Reference](https://docs.emqx.com/en/emqx/v5.8/extensions/hooks.html)
- [EMQX Source Code - emqx_message.hrl](https://github.com/emqx/emqx/blob/master/apps/emqx_utils/include/emqx_message.hrl)
- [MQTT 5.0 User Properties Specification](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html)
