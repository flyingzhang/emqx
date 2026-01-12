# EMQX ClientId Injector - 测试案例定义

## 测试目标

验证 `emqx_clientid_injector` 插件能够正确地在 MQTT 消息中注入 ClientId 等 User Properties。

## 测试案例分类

### 1. 功能测试

#### TC-01: 基本功能 - ClientId 注入
**测试目标**: 验证插件能够正确注入 ClientId 到 User Properties

**前置条件**:
- 插件已加载并启用
- 使用默认配置

**测试步骤**:
1. 使用 MQTT 3.1.1 客户端发布消息，ClientId = "test-device-001"
2. 使用 MQTT 5.0 客户端订阅该消息
3. 检查接收到的消息 User Properties

**预期结果**:
- 消息成功投递到订阅者
- User Properties 包含 `x-emqx-clientid = "test-device-001"`

**测试数据**:
```erlang
Message = #message{
    id = <<"msg1">>,
    from = <<"test-device-001">>,
    topic = <<"test/topic">>,
    headers = #{},
    payload = <<"hello">>,
    timestamp = 1641234567890
}
```

#### TC-02: 可选属性 - Username 注入
**测试目标**: 验证可选的 Username 注入功能

**前置条件**:
- 插件已加载
- 配置 `inject_username = true`

**测试步骤**:
1. 客户端以 Username="user1" 连接
2. 发布消息
3. 检查 User Properties

**预期结果**:
- User Properties 包含 `x-emqx-username = "user1"`

#### TC-03: 可选属性 - PeerName 注入
**测试目标**: 验证可选的 PeerName 注入功能

**前置条件**:
- 插件已加载
- 配置 `inject_peername = true`

**测试步骤**:
1. 从 IP 192.168.1.100:12345 的客户端连接
2. 发布消息
3. 检查 User Properties

**预期结果**:
- User Properties 包含 `x-emqx-peername = "192.168.1.100:12345"`

#### TC-04: Topic 过滤 - 排除系统消息
**测试目标**: 验证系统消息不被处理

**前置条件**:
- 插件已加载
- 默认配置

**测试步骤**:
1. 发布消息到 `$SYS/broker/stats`

**预期结果**:
- 消息未被修改，不包含 User Properties

#### TC-05: Topic 过滤 - 排除前缀
**测试目标**: 验证 exclude_prefixes 配置生效

**前置条件**:
- 配置 `exclude_prefixes = [<<"$SYS/">>, <<"$share/">>, <<"debug/">>]`

**测试步骤**:
1. 发布消息到 `debug/test`

**预期结果**:
- 消息未被修改

#### TC-06: Topic 过滤 - 包含前缀
**测试目标**: 验证 include_prefixes 配置生效

**前置条件**:
- 配置 `include_prefixes = [<<"neat/">>, <<"sensor/">>]`

**测试步骤**:
1. 发布消息到 `sensor/data`
2. 发布消息到 `other/topic`

**预期结果**:
- `sensor/data` 消息被注入 ClientId
- `other/topic` 消息未被修改

#### TC-07: 保留原有 User Properties
**测试目标**: 验证设备自带的 User Properties 不被覆盖

**前置条件**:
- 插件已加载
- 使用 MQTT 5.0 客户端

**测试步骤**:
1. MQTT 5.0 客户端发布消息，自带 User Property: `custom-key = custom-value`
2. 订阅者接收消息

**预期结果**:
- User Properties 同时包含:
  - `x-emqx-clientid = "device-001"`
  - `custom-key = "custom-value"`

#### TC-08: 配置禁用
**测试目标**: 验证 enable=false 时插件不工作

**前置条件**:
- 配置 `enable = false`

**测试步骤**:
1. 发布任意消息

**预期结果**:
- 消息未被修改

### 2. 边界测试

#### TC-09: 空ClientId 处理
**测试目标**: 验证 ClientId 为空时的行为

**测试步骤**:
1. 使用空 ClientId 的客户端发布消息

**预期结果**:
- 能够正确处理，注入空字符串或跳过

#### TC-10: 特殊字符 ClientId
**测试目标**: 验证包含特殊字符的 ClientId

**测试数据**:
- `device+001`
- `device@domain.com`
- `device/001`

**预期结果**:
- 能够正确转义和处理

#### TC-11: Unicode ClientId
**测试目标**: 验证 Unicode 字符的 ClientId

**测试数据**:
- `设备-001`
- `device-测试`

**预期结果**:
- 能够正确编码为 UTF-8 binary

### 3. 性能测试

#### TC-12: 消息吞吐量测试
**测试目标**: 验证插件对性能的影响

**测试步骤**:
1. 使用 emqtt_bench 发送 10,000 条/秒
2. 测量消息延迟

**预期结果**:
- 额外延迟 < 0.1ms

#### TC-13: 内存占用测试
**测试目标**: 验证内存开销

**测试步骤**:
1. 发送大量消息
2. 监控内存使用

**预期结果**:
- 每条消息额外内存 < 100 bytes

### 4. 集成测试

#### TC-14: MQTT 3.x → MQTT 5.0
**测试目标**: 验证跨协议版本场景

**测试步骤**:
1. MQTT 3.1.1 客户端发布消息
2. MQTT 5.0 客户端订阅

**预期结果**:
- MQTT 5.0 订阅者能收到 User Properties

#### TC-15: 多订阅者场景
**测试目标**: 验证多个订阅者的场景

**测试步骤**:
1. 一个 MQTT 3.x 订阅者
2. 一个 MQTT 5.0 订阅者
3. 发布消息

**预期结果**:
- 两个订阅者都能收到消息
- MQTT 5.0 订阅者收到 User Properties

#### TC-16: 集群环境
**测试目标**: 验证集群中消息转发

**测试步骤**:
1. 部署 3 节点 EMQX 集群
2. 节点1 的客户端发布消息
3. 节点2 的订阅者接收

**预期结果**:
- 消息包含正确的 User Properties

### 5. 错误处理测试

#### TC-17: 客户端信息不存在
**测试目标**: 验证客户端已断开时的行为

**测试步骤**:
1. 客户端发布后立即断开
2. Hook 尝试获取客户端信息

**预期结果**:
- 不抛出异常
- 注入默认值或跳过

#### TC-18: 配置错误处理
**测试目标**: 验证错误配置的处理

**测试步骤**:
1. 设置无效的配置值

**预期结果**:
- 使用默认值
- 插件正常工作

## 测试优先级

| 优先级 | 测试案例 |
|--------|----------|
| P0 (必须) | TC-01, TC-04, TC-07, TC-08, TC-14 |
| P1 (重要) | TC-02, TC-03, TC-05, TC-06, TC-15 |
| P2 (一般) | TC-09, TC-10, TC-11, TC-16, TC-17 |
| P3 (可选) | TC-12, TC-13, TC-18 |

## 测试工具

- **单元测试**: Common Test / EUnit
- **集成测试**: emqtt/ mosquitto_clients
- **性能测试**: emqtt_bench
