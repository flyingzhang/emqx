# EMQX Kick 操作差异性分析报告：在线 vs 离线

## 核心发现

通过对比测试证实：**Kick 操作对订阅的影响完全取决于客户端当前的连接状态。**

- **在线状态 (Active Connection)**：执行 Kick 会导致**订阅丢失**，尽管会话被保留 (`Session Present: True`)。
- **离线状态 (Inactive Connection)**：执行 Kick **不会影响订阅**，会话和订阅都完好无损。

这表明 EMQX 在处理"在线客户端 Kick"时触发了一个特定的代码执行路径，该路径存在副作用：破坏了持久化会话的订阅数据。

## 测试证据

使用测试脚本 `test_kick_state_comparison.py` 进行验证，结果如下：

```
==================================================
测试结果汇总
==================================================
场景 A (在线 Kick): Session Present=True, 收到消息=False  ❌ 订阅丢失
场景 B (离线 Kick): Session Present=True, 收到消息=True   ✅ 订阅保留
```

### 场景 A：在线 Kick 流程分析

1.  Client 连接并订阅。
2.  Client 保持 TCP 连接激活。
3.  执行 `emqx ctl clients kick`。
4.  **推测内部行为**：
    *   查找到对应的 Channel 进程。
    *   发送关闭信号。
    *   **副作用发生点**：Channel 在关闭清理过程中，可能调用了清除订阅的逻辑，并且错误地同步到了持久化存储中，删除了该 Session 的订阅列表。
5.  Client 重连。
    *   Server 发现 Session 记录还在（Client ID 存在）。
    *   返回 `Session Present: True`。
    *   但订阅列表已空，导致依然收不到消息。

### 场景 B：离线 Kick 流程分析

1.  Client 连接并订阅。
2.  Client 主动断开（TCP 关闭），Session 进入持久化存储（Offline 状态）。
3.  执行 `emqx ctl clients kick`。
4.  **推测内部行为**：
    *   查找 Channel 进程 -> 未找到。
    *   对于 `builtin_local` 后端，可能仅尝试查找并标记，或者因为目标不存在而跳过清理逻辑。
    *   或者调用了 `kick_offline_session`，该函数实现正确，没有副作用。
5.  Client 重连。
    *   Session 和订阅都从持久化存储中完整加载。
    *   收到消息。

## 结论与建议

### 结论
这是一个软件缺陷（Bug）或未记录的行为差异。在线 Kick 不应导致持久化订阅丢失，特别是当 `durable_sessions` 明确启用时。

### 建议
1.  **运维规避**：不要对在线的持久化会话客户端使用 `kick` 命令，除非意图是重置其订阅。
2.  **开发修复**：需要检查 `emqx_channel:process_kick` 或相关清理路径，确保在 `durable_sessions` 启用时，不要删除订阅数据。
3.  **客户端防御**：客户端应由应用层逻辑保证订阅完整性，或者在被踢下线后（收到非正常 Disconnect），选择重新订阅。
