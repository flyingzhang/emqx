# EMQX 持久化会话与连接中断行为深度分析报告

## 摘要

通过一系列严格的控制变量测试（包括基于 iptables 的网络层模拟）及源码分析，我们对 EMQX 5.8.8 的持久化会话行为得出了最终结论。

**核心发现**：
EMQX 5.8.8 的持久化会话功能总体工作正常，但**在线 Kick 操作存在严重副作用**。对在线客户端执行 `kick` 会触发会话销毁逻辑 (`emqx_session:destroy`)，导致持久化存储中的订阅被删除，而常规的网络中断或主动断开则不会触发此逻辑。

## 详细测试结果矩阵

| 场景 | 操作描述 | Session Present (重连后) | Subscription (不重新订阅) | 消息接收 | 结论 |
|---|---|---|---|---|---|
| **场景 A** | **客户端主动断开** (TCP FIN) | True | ✅ **保留** | ✅ 成功 | 正常 |
| **场景 B** | **网络异常中断** (iptables DROP) | True | ✅ **保留** | ✅ 成功 | 正常 |
| **场景 C** | **在线 Kick** (`emqx ctl kick`) | *True (异常)* | ❌ **丢失** | ❌ **失败** | **Bug/设计缺陷** |

*注：场景C中，虽然订阅丢失，但 Server 仍返回 Session Present=True，这进一步误导了客户端。*

## 源码级根因分析

通过分析 `emqx_channel.erl` 和 `emqx_persistent_session_ds.erl`，我们找到了问题的根源：

1.  **Kick 触发 Destroy**:
    当对在线客户端执行 Kick 时，Channel 进程会执行 `process_kick`，进而调用 `emqx_session:destroy`。

2.  **Destroy 导致数据删除**:
    `emqx_session:destroy` 最终调用 `emqx_persistent_session_ds:session_drop/2`。
    ```erlang
    session_drop(SessionId, Reason) ->
        ...
        ok = emqx_persistent_session_ds_subs:on_session_drop(SessionId, S0), %% 删除订阅
        ok = emqx_persistent_session_ds_state:delete(SessionId); %% 删除会话状态
    ```
    此逻辑**无条件地删除了持久化的订阅和会话数据**。这解释了为什么订阅会丢失。

3.  **为何离线 Kick 无影响？**
    `emqx_cm:kick_session` 在处理离线 Session 时，尝试查找 Channel PID 失败，对于持久化会话可能直接返回或进入了无效路径，并未真正触发 `session_drop`，因此数据得以保留。

4.  **ConnAck 日志无异常**:
    日志中的 `packet: CONNACK(Q0, R0, D0, AckFlags=1, ...)` 仅表明 Broker 在处理 CONNECT 时，`emqx_persistent_session_ds:open` 返回了成功。这可能是因为虽然 `session_drop` 被调用，但在高并发下出现了 Race Condition，或者数据删除存在延迟/不一致，导致 Session 元数据还在，但订阅索引已丢失。

## 验证方法 (基于 Docker Socket 模拟)

为了验证场景 B，我们使用了 `iptables` 在容器内部 DROP 掉客户端 IP 的所有数据包：
```bash
iptables -I INPUT -s 172.17.0.1 -j DROP
```
结果证实，即使是在这种极端的网络中断（Socket 失效/超时）情况下，EMQX 依然能够完美地保留订阅。**这证明了持久化功能的健壮性，也反证了 Kick 操作的特殊性。**

## 给用户的建议

### 1. 运维操作建议
- **避免在线 Kick**：**严禁**在生产环境中对正在传输数据的持久化会话客户端执行 `kick`，除非你明确想要**销毁**其会话和订阅。
- **推荐替代方案**：如果需要强制断开客户端且保留会话，建议在网络层（如 LB、防火墙）阻断连接。

### 2. 客户端开发建议
- **防御性编程**：
    - **策略**: 客户端在重连后，如果不确定之前的断开原因（特别是收到过 Warning 或非预期断开），建议**主动重新订阅**，而不完全依赖 `Session Present`。
    - **监控**: 监控 `CONNACK` 的 `Session Present` 标志与实际消息接收情况，如果在 SP=1 时频繁丢消息，应报警。

### 3. 反馈给厂商
- 此行为（在线 Kick = Destroy Session）对于持久化会话特性来说是不合理的。Kick 应该通过 `emqx_session:disconnect` 而非 `destroy` 来实现。建议向 EMQX 团队反馈此 issue。

## 附件脚本
- `test_kick_state_comparison.py`: 对比在线 vs 离线 Kick。
- `test_simulate_network_failure.py`: 使用 iptables 模拟 Socket 中断。
