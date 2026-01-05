# EMQX Kick Session 修复 - 构建与测试指南

## 修复内容总结

本次修改解决了两个关键问题：

### 1. 修复内部状态竞争问题（Race Condition Fix）

**问题根源**：
- 原先的 `kick` 操作在销毁会话时没有加锁
- 当客户端在被踢出的同时重连时，可能出现 `Session Present=True` 但订阅丢失的异常状态

**修复方案**：
- 在 `emqx_persistent_session_ds.erl` 中使用 `emqx_cm_locker:trans()` 包裹会话销毁操作
- 确保会话销毁与会话创建/打开操作互斥且原子化

**修改文件**：
- `apps/emqx/src/emqx_persistent_session_ds.erl`
  - `destroy_session/1` - 添加事务锁
  - `kick_offline_session/1` - 添加事务锁

### 2. 新增保留会话的 Kick 功能（Retain Session Feature）

**功能实现**：
- 支持在踢出客户端时选择保留会话
- 新增 CLI 参数：`--retain-session` 或 `-r`

**使用方法**：
```bash
# 普通 kick（清除会话）
emqx ctl clients kick <ClientID>

# 保留会话的 kick（仅断开连接）
emqx ctl clients kick <ClientID> --retain-session
emqx ctl clients kick <ClientID> -r
```

**修改文件**：
- `apps/emqx/src/emqx_channel.erl` - 处理 `{kick, Opts}` 消息
- `apps/emqx/src/emqx_cm.erl` - 导出 `kick_session/2`，支持选项传递
- `apps/emqx_management/src/emqx_mgmt_cli.erl` - CLI 参数解析

## 相关单元测试

### 测试文件位置

1. **emqx_cm_SUITE.erl** - `apps/emqx/test/emqx_cm_SUITE.erl`
   - 包含多个 `kick_session` 相关测试用例
   - 测试用例：
     - `t_kick_session_kick_normal/1`
     - `t_kick_session_kick_shutdown/1`
     - `t_kick_session_kick_timeout/1`
     - `t_kick_session_kick_noproc/1`
     - 等等

2. **emqx_persistent_session_ds_SUITE.erl** - `apps/emqx/test/emqx_persistent_session_ds_SUITE.erl`
   - 持久化会话相关测试

### 运行测试

**在 Docker 容器中运行测试**：

```bash
# 设置环境变量
export MSYS_NO_PATHCONV=1

# 运行 emqx_cm 相关测试
docker run --rm \
  -v "$(pwd)":/emqx \
  -w /emqx \
  ghcr.io/emqx/emqx-builder/5.6-1:1.15.7-26.2.5.14-1-ubuntu22.04 \
  bash -c "git config --global --add safe.directory '*' && \
           ./rebar3 ct --suite apps/emqx/test/emqx_cm_SUITE.erl"

# 运行持久化会话相关测试
docker run --rm \
  -v "$(pwd)":/emqx \
  -w /emqx \
  ghcr.io/emqx/emqx-builder/5.6-1:1.15.7-26.2.5.14-1-ubuntu22.04 \
  bash -c "git config --global --add safe.directory '*' && \
           ./rebar3 ct --suite apps/emqx/test/emqx_persistent_session_ds_SUITE.erl"
```

## 构建 Docker 镜像

### 方法一：使用便捷脚本（推荐）

```bash
# 执行构建脚本
./build_docker_with_fix.sh
```

### 方法二：手动构建

```bash
# 设置环境变量
export MSYS_NO_PATHCONV=1
export PROFILE=emqx

# 执行构建
./build emqx docker
```

### 构建产物

构建完成后，镜像标签会保存在 `.emqx_docker_image_tags` 文件中。

**查看生成的镜像**：
```bash
cat .emqx_docker_image_tags
```

**运行镜像**：
```bash
docker run -d \
  --name emqx \
  -p 1883:1883 \
  -p 8083:8083 \
  -p 8084:8084 \
  -p 8883:8883 \
  -p 18083:18083 \
  $(head -1 .emqx_docker_image_tags)
```

## 验证修复

### 1. 验证竞态条件修复

使用之前创建的测试脚本验证：

```bash
# 运行测试脚本
python test_kick_subscription_retention.py
```

**预期结果**：
- 客户端被 kick 后重连，`Session Present` 应为 `False`（会话已清除）
- 或者使用 `--retain-session` 参数时，`Session Present` 应为 `True` 且订阅保留

### 2. 验证保留会话功能

```bash
# 启动 EMQX 容器
docker run -d --name emqx-test -p 1883:1883 -p 18083:18083 <image-tag>

# 连接客户端并订阅
# 使用 MQTTX 或其他 MQTT 客户端

# 使用保留会话的 kick
docker exec emqx-test emqx ctl clients kick <ClientID> --retain-session

# 重新连接
# 预期：Session Present=True，订阅仍然存在
```

## 补丁文件

完整的补丁文件位于：`fix_kick.patch`

**应用补丁**：
```bash
git apply fix_kick.patch
```

## 注意事项

1. **Export 声明**：确保 `apps/emqx/src/emqx_cm.erl` 中包含 `kick_session/2` 的导出声明（第 57 行）

2. **编译要求**：
   - OTP 26.2.5.14-1
   - Elixir 1.15.7
   - Builder: ghcr.io/emqx/emqx-builder/5.6-1

3. **测试环境**：
   - 建议在 Docker 容器中运行测试以确保环境一致性
   - 测试可能需要较长时间（需要编译依赖）

## 相关文档

- 补丁详细说明：`fix_kick.patch`
- 最终分析报告：`EMQX_PERSISTENCE_FINAL_REPORT.md`
- 订阅丢失验证：`KICK_SUBSCRIPTION_LOSS_VERIFIED.md`
- 差异分析：`KICK_DIFFERENTIAL_ANALYSIS.md`

---

**创建时间**: 2025-12-31
**EMQX 版本**: 5.8.8
