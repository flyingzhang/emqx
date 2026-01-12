# EMQX ClientId Injector - 开发指南

本文档说明 EMQX ClientId Injector 插件的开发流程和验证方法。

## 插件概述

ClientId Injector 是一个 EMQX 内部应用插件，通过 Hook 机制自动将发布者的 ClientId 注入到 MQTT 5.0 User Properties 中，便于订阅者识别消息来源。

## 项目结构

```
apps/emqx_clientid_injector/
├── src/                      # 源代码
│   ├── emqx_clientid_injector_app.erl    # OTP 应用入口
│   ├── emqx_clientid_injector_sup.erl     # Supervisor
│   ├── emqx_clientid_injector.erl         # Hook 处理主逻辑
│   └── emqx_clientid_injector_config.erl  # 配置管理
├── test/                     # 测试代码
│   └── emqx_clientid_injector_SUITE.erl   # 单元测试
└── etc/                      # 配置文件
    └── emqx_clientid_injector.hocon      # 默认配置
```

## 开发环境配置

### 环境要求

- **操作系统**: Windows 10/11 + Git Bash
- **Docker**: Docker Desktop for Windows
- **Erlang**: OTP 26.2.5.14-1（通过 Docker 容器）
- **Python**: 3.x（用于 MQTT 测试）

### 相关文档

通用开发环境配置请参考：
- **Windows + Docker 构建**: [docs/dev/BUILD_WITH_DOCKER_WINDOWS.md](../../../../../docs/dev/BUILD_WITH_DOCKER_WINDOWS.md)
- **调试最佳实践**: [docs/dev/BUILD_DEBUG_BEST_PRACTICES.md](../../../../../docs/dev/BUILD_DEBUG_BEST_PRACTICES.md)

## 开发流程

### 1. 代码开发

在 `apps/emqx_clientid_injector/src/` 中编写或修改 Erlang 代码。

**编码注意事项**：
- Map 更新语法分两行写（避免 erlfmt 解析问题）
- Case 表达式保持一致的缩进风格
- 详见 [BUILD_DEBUG_BEST_PRACTICES.md](../../../../../docs/dev/BUILD_DEBUG_BEST_PRACTICES.md) 第 6 节

### 2. 代码格式化

```bash
export MSYS_NO_PATHCONV=1
docker run --rm -v "$(pwd)":/emqx -w /emqx \
  ghcr.io/emqx/emqx-builder/5.6-2:1.15.7-26.2.5.14-1-debian13 \
  bash -c "ERLFMT_WRITE=true ./scripts/git-hook-pre-commit.sh"
```

### 3. Git 提交

```bash
# 暂存变更
git add .

# 提交（跳过版本检查）
FORCE=true git commit -m "your message"
```

### 4. 构建 Docker 镜像

```bash
export MSYS_NO_PATHCONV=1
export PROFILE=emqx
./build emqx docker
```

## 测试验证

### 单元测试

```bash
cd apps/emqx_clientid_injector
ct
```

### 功能测试（MQTT 5.0）

```bash
# 启动 EMQX 容器
docker run -d --name emqx -p 1883:1883 -p 18083:18083 \
  -e EMQX_CLUSTER__DISCOVERY_STRATEGY=singleton \
  emqx/emqx:5.8.9-g2ea5ffc7

# 运行测试脚本
bash issues/clientid-injector/scripts/test-clientid-injector.sh
```

### 测试脚本位置

- **完整测试**: `issues/clientid-injector/scripts/test-clientid-injector.sh`
- **MQTT 5.0 测试**: `issues/clientid-injector/tests/test_clientid_injector.py`
- **跨版本测试**: `issues/clientid-injector/tests/test_mqtt3_to_mqtt5.py`

## 工作流程脚本

### 快捷脚本

```bash
# 从项目根目录运行
bash issues/clientid-injector/scripts/test-clientid-injector.sh    # 测试插件
bash issues/clientid-injector/scripts/commit-clientid-injector.sh   # Git 提交
bash issues/clientid-injector/scripts/build-clientid-injector.sh    # 构建镜像
```

### 脚本说明

| 脚本 | 功能 |
|------|------|
| `scripts/test-clientid-injector.sh` | 依赖检查 → 插件验证 → MQTT 测试 |
| `scripts/commit-clientid-injector.sh` | 格式化 → 暂存 → 提交 |
| `scripts/build-clientid-injector.sh` | 格式化 → 编译 → 构建 → 测试 |

## 集成到 EMQX

### 修改 reboot_lists.eterm

将插件添加到 `apps/emqx_machine/priv/reboot_lists.eterm` 的 `common_business_apps` 列表中：

```erlang
common_business_apps =>
    [
        ...
        emqx_plugins,
        emqx_clientid_injector,  % 添加此行
        quicer,
        bcrypt
    ],
```

### 验证插件加载

```bash
# 检查应用是否加载
docker exec emqx emqx eval 'application:which_applications().' | grep clientid

# 检查 Hook 是否注册
docker exec emqx emqx eval 'ets:tab2list(emqx_hooks).' | grep message.publish
```

## 功能验证

### 验证点 1: MQTT 5.0 消息

发布者和订阅者都使用 MQTT 5.0 协议，验证 User Properties 中包含 ClientId。

### 验证点 2: 跨版本消息

MQTT 3.x 发布者发布消息，MQTT 5.0 订阅者接收，验证 ClientId 被正确注入。

### 验证点 3: 系统消息过滤

验证 `$SYS/` 和 `$share/` 主题的消息不会被注入 ClientId。

## 常见问题

### Q: 插件未加载？

**A**: 检查 `apps/emqx_machine/priv/reboot_lists.eterm` 中是否包含插件，并重新构建镜像。

### Q: User Properties 未注入？

**A**: 检查订阅者是否使用 MQTT 5.0 协议，只有 MQTT 5.0 支持 User Properties。

### Q: 格式化失败？

**A**:
1. 检查 map 更新语法是否分两行写
2. 确保在 Docker 容器中运行格式化
3. 参考 [BUILD_WITH_DOCKER_WINDOWS.md](../../../../../docs/dev/BUILD_WITH_DOCKER_WINDOWS.md) 第 5 节

### Q: Pre-commit hook 版本检查失败？

**A**: 使用 `FORCE=true git commit` 跳过版本检查（仅适用于功能分支）。

## 参考资源

- **EMQX Hooks 文档**: [EMQX Hook 指南](https://www.emqx.io/docs/en/latest/design/hook/)
- **MQTT 5.0 规范**: [MQTT 5.0 规范](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html)
- **Paho MQTT Python**: [Paho 客户端库](https://www.eclipse.org/paho/index.php?page=client/python/overview.php)

---

**最后更新**: 2026-01-12
