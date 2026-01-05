# Windows 环境下通过 Docker 构建 EMQX 指引

本文档说明如何在 Windows 环境下使用 Docker 构建 EMQX 项目。

## 前置要求

1. **Docker Desktop for Windows** 已安装并运行
2. **Git Bash** 或其他 Unix-like shell（推荐使用 Git Bash）
3. 网络代理配置（如果需要）

## 环境配置

### 1. 检查 Docker 环境

```bash
docker --version
docker info
```

### 2. 配置 Git Bash 环境（推荐）

**禁用路径自动转换**：

在 Git Bash 中，默认会将 Unix 风格路径（如 `/tmp/build`）自动转换为 Windows 路径。为避免这个问题，建议设置以下环境变量：

```bash
export MSYS_NO_PATHCONV=1
```

这样可以直接使用 Unix 风格路径，无需使用双斜杠 `//` 或 `$(pwd -W)` 等变通方法。

**建议**：将此配置添加到 `~/.bashrc` 文件中，使其永久生效：

```bash
echo "export MSYS_NO_PATHCONV=1" >> ~/.bashrc
source ~/.bashrc
```

### 3. 配置网络代理（可选）

如果您的网络环境需要代理访问 GitHub 等外部资源，请配置以下环境变量：

```bash
export http_proxy=http://10.66.66.4:3128
export https_proxy=http://10.66.66.4:3128
```

## 构建步骤

### 方式一：使用 Docker 容器构建（推荐）

#### 1. 创建 Docker 卷（用于缓存，加速后续构建）

> [!TIP]
> **Docker 卷缓存是关键优化**：将 `_build` 和 `deps` 目录挂载到 Docker 卷中，可以在多次构建之间保留已下载的依赖和编译产物。即使构建中断，下次重试也会从上次进度继续，而不是从头开始。

```bash
# 为构建产物创建卷
docker volume create emqx_build_cache

# 为依赖创建卷
docker volume create emqx_deps_cache

# 可选：为 Mix 缓存创建卷
docker volume create emqx_mix_home

# 可选：为通用缓存创建卷
docker volume create emqx_cache_home
```

**环境变量优化**：

```bash
# 跳过 i18n 翻译下载（加速构建）
export DOWNLOAD_I18N_TRANSLATIONS=false
```

#### 2. 检出指定版本（可选）

```bash
# 检出特定版本标签
git fetch --tags
git checkout v5.8.8

# 或者使用当前分支
```

#### 3. 查看当前配置

```bash
# 查看 OTP 和 Elixir 版本配置
cat env.sh
```

对于 v5.8.8，推荐使用 OTP 26（默认配置）：
- `OTP_VSN=26.2.5.14-1`
- `ELIXIR_VSN=1.15.7`
- `EMQX_BUILDER_VSN=5.6-1`

#### 4. 执行构建

**构建社区版（emqx）：**

**方法一：使用 MSYS_NO_PATHCONV=1（推荐）**

```bash
# 设置环境变量禁用路径转换
export MSYS_NO_PATHCONV=1

# 执行构建
docker run --rm \
  -v "$(pwd)":/emqx \
  -v emqx_build_v588_otp26:/emqx/_build \
  -v emqx_deps_v588_otp26:/emqx/deps \
  -v emqx_mix_home:/root/.mix \
  -v emqx_cache_home:/root/.cache \
  -w /emqx \
  -e http_proxy=http://10.66.66.4:3128 \
  -e https_proxy=http://10.66.66.4:3128 \
  ghcr.io/emqx/emqx-builder/5.6-1:1.15.7-26.2.5.14-1-ubuntu22.04 \
  bash -c "git config --global http.proxy http://10.66.66.4:3128; \
           git config --global http.sslVerify false; \
           git config --global --add safe.directory '*'; \
           make emqx"
```

**方法二：使用双斜杠路径（备选）**

如果未设置 `MSYS_NO_PATHCONV=1`，可以使用以下命令：

```bash
docker run --rm \
  -v "$(pwd -W)"://emqx \
  -v emqx_build_v588_otp26://emqx/_build \
  -v emqx_deps_v588_otp26://emqx/deps \
  -v emqx_mix_home://root/.mix \
  -v emqx_cache_home://root/.cache \
  -w //emqx \
  -e http_proxy=http://10.66.66.4:3128 \
  -e https_proxy=http://10.66.66.4:3128 \
  ghcr.io/emqx/emqx-builder/5.6-1:1.15.7-26.2.5.14-1-ubuntu22.04 \
  bash -c "git config --global http.proxy http://10.66.66.4:3128; \
           git config --global http.sslVerify false; \
           git config --global --add safe.directory '*'; \
           make emqx"
```

**构建企业版（emqx-enterprise）：**

将上述命令中的 `make emqx` 替换为 `make emqx-enterprise`。

**注意事项：**
- **推荐使用方法一**：设置 `MSYS_NO_PATHCONV=1` 后可以直接使用标准 Unix 路径，命令更简洁
- 方法二使用 `$(pwd -W)` 获取 Windows 风格路径，容器内路径使用双斜杠 `//` 前缀
- 如果不需要代理，可以移除 `-e http_proxy` 和 `-e https_proxy` 参数
- 如果不需要 SSL 验证绕过，可以移除 `git config --global http.sslVerify false`

#### 5. 提取构建产物

构建完成后，产物位于 Docker 卷中。使用以下命令将其打包到主机：

**方法一：使用 MSYS_NO_PATHCONV=1（推荐）**

```bash
# 确保已设置环境变量
export MSYS_NO_PATHCONV=1

# 创建 _packages 目录
mkdir -p _packages

# 从 Docker 卷中打包并复制到主机
docker run --rm \
  -v emqx_build_v588_otp26:/tmp/build \
  -v "$(pwd)/_packages":/tmp/pkg \
  ubuntu:24.04 \
  tar czf /tmp/pkg/emqx-5.8.8-otp26.tar.gz -C /tmp/build/emqx/rel emqx
```

**方法二：使用双斜杠路径（备选）**

```bash
# 创建 _packages 目录
mkdir -p _packages

# 从 Docker 卷中打包并复制到主机
docker run --rm \
  -v emqx_build_v588_otp26://tmp/build \
  -v "$(pwd -W)/_packages"://tmp/pkg \
  ubuntu:24.04 \
  tar czf //tmp/pkg/emqx-5.8.8-otp26.tar.gz -C //tmp/build/emqx/rel emqx
```

构建产物将保存在 `_packages/emqx-5.8.8-otp26.tar.gz`。

#### 6. 验证构建产物

```bash
# 查看文件大小
ls -lh _packages/

# 查看压缩包内容
tar -tzf _packages/emqx-5.8.8-otp26.tar.gz | head -20
```

### 方式二：使用 Docker 构建镜像

如果您需要构建 Docker 镜像而不是二进制包：

```bash
# 使用项目自带的构建脚本
./build emqx docker

# 或者直接使用 Makefile
make docker
```

## 常见问题

### 1. 路径转换问题

**问题**：Git Bash 会自动将 `/path` 转换为 Windows 路径，导致 Docker 命令中的路径参数错误。

**解决方案（按优先级排序）**：

1. **推荐方法**：设置 `MSYS_NO_PATHCONV=1` 环境变量
   ```bash
   export MSYS_NO_PATHCONV=1
   ```
   设置后可以直接使用标准 Unix 路径（如 `/emqx`、`/tmp/build`），无需任何特殊处理。

2. **备选方法一**：使用双斜杠 `//path`
   ```bash
   docker run -v emqx_build://emqx/_build ...
   ```

3. **备选方法二**：使用 `$(pwd -W)` 获取 Windows 路径
   ```bash
   docker run -v "$(pwd -W)"://emqx ...
   ```

**永久配置**：将 `MSYS_NO_PATHCONV=1` 添加到 `~/.bashrc`：
```bash
echo "export MSYS_NO_PATHCONV=1" >> ~/.bashrc
source ~/.bashrc
```

### 2. 网络超时

**问题**：下载依赖时出现 `gnutls_handshake` 或超时错误。

**解决方案**：
- 配置 HTTP 代理（见上文）
- 添加 `git config --global http.sslVerify false`
- 使用 `-e http_proxy` 和 `-e https_proxy` 环境变量

### 3. OTP 版本不匹配

**问题**：构建时提示 OTP 版本不支持。

**解决方案**：
- 检查 `env.sh` 中的 `OTP_VSN` 配置
- 使用项目推荐的 OTP 版本（v5.8.8 推荐 OTP 26）
- 如果需要使用其他 OTP 版本，需要修改 `scripts/ensure-rebar3.sh` 添加对应版本支持

### 4. 构建失败后如何恢复

由于使用了 Docker 卷缓存，可以直接重新运行构建命令，已下载的依赖和编译产物会被保留。

如果需要完全清理：

```bash
# 删除 Docker 卷
docker volume rm emqx_build_v588_otp26
docker volume rm emqx_deps_v588_otp26

# 重新创建并构建
docker volume create emqx_build_v588_otp26
docker volume create emqx_deps_v588_otp26
# ... 然后重新执行构建命令
```

### 5. 查看 Docker 卷内容

```bash
# 确保已设置环境变量（推荐）
export MSYS_NO_PATHCONV=1

# 列出卷中的文件
docker run --rm -v emqx_build_v588_otp26:/tmp/build ubuntu:24.04 ls -R /tmp/build

# 或使用双斜杠方法（备选）
docker run --rm -v emqx_build_v588_otp26://tmp/build ubuntu:24.04 ls -R //tmp/build
```

## 性能优化建议

1. **使用 Docker 卷**：将 `_build`、`deps`、`.mix`、`.cache` 挂载到 Docker 卷，避免 Windows 文件系统性能问题
2. **增量构建**：保留 Docker 卷，后续构建会更快
3. **网络代理**：配置本地代理加速依赖下载
4. **WSL2 后端**：Docker Desktop 使用 WSL2 后端性能更好

## 参考资源

- [EMQX 官方文档](https://www.emqx.io/docs/)
- [EMQX Builder 镜像](https://github.com/emqx/emqx-builder)
- [Docker Desktop for Windows](https://docs.docker.com/desktop/windows/)

## 版本信息

本指引基于以下版本测试：
- EMQX: v5.8.8
- OTP: 26.2.5.14-1
- Elixir: 1.15.7
- Builder: ghcr.io/emqx/emqx-builder/5.6-1

---

**最后更新**: 2025-12-31
