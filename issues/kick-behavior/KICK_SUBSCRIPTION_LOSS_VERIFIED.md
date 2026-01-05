# EMQX 在线 Kick 导致持久化订阅丢失问题验证报告

## 核心结论

**确认存在 Bug/特性限制**：即使启用了持久化会话 (`durable_sessions`)，如果在客户端**在线（Connected）**状态下执行 `kick` 操作，该客户端的**订阅（Subscription）会丢失**，尽管**会话（Session）本身被保留**。

这意味着客户端重连后，虽然服务器返回 `Session Present: True`，但如果不重新发起 `SUBSCRIBE`，客户端将无法收到之前订阅主题的消息。

## 验证场景对比

我们对比了三种不同的断开场景：

| 场景 | 初始状态 | 触发动作 | Kick 结果 | 重连后 Session Present | 重连后订阅状态 | 消息接收 |
|---|---|---|---|---|---|---|
| **场景 A** | 在线 | 客户端主动断开, 然后 Kick | `unknown_session` (无效) | True | ✅ 保留 | ✅ 成功 |
| **场景 B** | 在线 | 模拟网络中断, 然后 Kick | `unknown_session` (无效) | True | ✅ 保留 | ✅ 成功 |
| **场景 C** | **在线** | **直接对在线客户端执行 Kick** | `ok` (成功) | **True** | ❌ **丢失** | ❌ **失败** |

## 验证过程 (场景 C)

使用脚本 `test_kick_subscription_retention.py` 进行了自动化测试：

1. **Setup**: 客户端使用全新 ID 连接，QoS 1 订阅主题 `test/kick/subscription`。
2. **Hold**: 客户端保持在线。
3. **Kick**: 通过 `emqx ctl clients kick` 强制踢掉该在线客户端。
   - EMQX 日志显示 kick 成功。
   - 客户端收到断开通知（Reason: Normal disconnection）。
4. **Reconnect**: 客户端重新连接（设置 `clean_start=False`）。
   - 服务器返回 `CONNACK`，**`Session Present: True`**。
   - **关键步骤**：客户端**不**发送 `SUBSCRIBE` 包（期望服务器恢复订阅）。
5. **Verify**: 向主题发布 QoS 1 消息。
   - **结果：客户端未收到消息**。

## 问题分析

### 现象
- `Session Present: True` 误导了客户端，让客户端认为会话（包括订阅）已完全恢复。
- 实际上，在线 Kick 操作似乎**清除了订阅数据**，或者导致持久化存储中的订阅与会话断开关联。
- 这解释了为什么用户在 EMQX 控制台 Kick 客户端后，发现重连的客户端丢失了订阅。

### 与正常断开的区别
- 当客户端先断开（场景 A/B）时，Session 进入 "offline" 状态，订阅被安全地保存在持久化存储中。
- 当客户端在线被 Kick 时，EMQX 执行了清理操作（`kick_session` -> `emqx_session:destroy`），这个路径在持久化会话的实现中，虽然设计上应该只标记为离线，但在处理"在线"状态的会话时，似乎发生了额外的清理（可能是为了处理会话冲突或强制重置），导致订阅丢失。

## 解决方案与建议

### 1. 避免对在线客户端执行 Kick
如果目的是测试或管理，尽量避免对正在传输数据的在线客户端执行 Kick，除非你希望它重置状态。

### 2. 客户端必须重新订阅 (Workaround)
鉴于 `Session Present: True` 在这种情况下不可信（订阅已丢失），建议客户端采取防御性策略：
- **方案 A**：无视 `Session Present`，每次连接都重新订阅（即使会增加一点开销）。
- **方案 B**：如果业务逻辑依赖 Kick 操作来重置连接，请确保客户端有机制检测订阅丢失并恢复。

### 3. 使用 API 检查订阅
在 Kick 操作后，可以通过 EMQX HTTP API (`GET /clients/{clientid}/subscriptions`) 检查订阅是否还存在，以验证系统行为。

## 涉及文件
- 测试脚本: `e:\workspaces\oss\emqx\test_kick_subscription_retention.py`
- 对比分析: `e:\workspaces\oss\emqx\KICK_VS_DISCONNECT_ANALYSIS.md`
