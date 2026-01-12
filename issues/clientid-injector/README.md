# EMQX ClientId Injector - Issue 资源

本目录包含 EMQX ClientId Injector 插件开发过程中创建的工作流程脚本、文档和测试工具。

## 目录结构

```
issues/clientid-injector/
├── README.md                           # 本文件
├── scripts/                            # 工作流程脚本
│   ├── build-clientid-injector.sh     # 构建脚本
│   ├── commit-clientid-injector.sh    # Git 提交脚本
│   └── test-clientid-injector.sh      # 测试脚本
├── docs/                               # 文档
│   └── DEVELOPMENT_GUIDE.md           # 开发规则与工作流程指南
└── tests/                              # 功能测试脚本
    ├── test_clientid_injector.py      # MQTT 5.0 测试
    └── test_mqtt3_to_mqtt5.py         # 跨版本测试
```

## 快速开始

### 运行测试

```bash
# 从项目根目录运行
bash issues/clientid-injector/scripts/test-clientid-injector.sh
```

### Git 提交

```bash
# 从项目根目录运行
bash issues/clientid-injector/scripts/commit-clientid-injector.sh -m "your message"
```

### 构建 Docker 镜像

```bash
# 从项目根目录运行
bash issues/clientid-injector/scripts/build-clientid-injector.sh
```

## 开发规则

详见 [docs/DEVELOPMENT_GUIDE.md](docs/DEVELOPMENT_GUIDE.md)

## 适用范围

这些脚本专门为 EMQX ClientId Injector 插件开发创建，包含：

- **环境兼容性处理**: Git Bash + Docker Desktop
- **代码格式化**: 使用 EMQX builder 容器运行 erlfmt
- **测试验证**: MQTT 5.0 User Properties 注入测试

对于其他 EMQX 插件开发，可参考这些脚本进行调整。

## 相关资源

- 插件代码: `apps/emqx_clientid_injector/`
- OpenSpec 文档: `openspec/changes/emqx-clientid-injector/`
- 测试案例: `apps/emqx_clientid_injector/TEST_CASES.md`
