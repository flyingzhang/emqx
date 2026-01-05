# EMQX Build and Debug Best Practices

This document captures optimized workflows for building and debugging EMQX, especially in complex scenarios like hot-patching and Docker-based development.

## 1. Docker-Based Build with Persistent Caching

Using Docker volumes for build caches dramatically speeds up incremental builds.

### Prerequisites
- Docker with sufficient resources
- Proxy configuration (if behind corporate firewall)

### Build Command
```bash
export MSYS_NO_PATHCONV=1  # Windows Git Bash only
docker run --rm \
  -v "$(pwd)":/emqx \
  -v emqx_build_cache:/emqx/_build \
  -v emqx_deps_cache:/emqx/deps \
  -w /emqx \
  -e DOWNLOAD_I18N_TRANSLATIONS=false \
  -e PROFILE=emqx \
  ghcr.io/emqx/emqx-builder/5.6-1:1.15.7-26.2.5.14-1-ubuntu22.04 \
  make emqx
```

### Key Environment Variables
| Variable | Purpose |
|----------|---------|
| `PROFILE=emqx` | Community Edition build |
| `DOWNLOAD_I18N_TRANSLATIONS=false` | Skip i18n (faster) |
| `HTTP_PROXY`, `HTTPS_PROXY` | Network proxy |

## 2. Hot-Patching Beam Files (Without Full Rebuild)

For quick iteration during debugging, patch compiled `.beam` files directly into a running container.

### Step 1: Extract Compiled Beam
```bash
docker run --rm \
  -v emqx_build_cache:/build \
  -v "$(pwd)":/host \
  busybox cp /build/emqx/lib/emqx/ebin/emqx_channel.beam /host/
```

### Step 2: Find Correct Library Path in Container
```bash
docker exec <container> find /opt/emqx/lib -name emqx_channel.beam
```

> **Important**: Multiple versions may exist (e.g., `emqx-5.5.4` and `emqx-5.8.8`). Check which one is loaded:
> ```bash
> docker exec <container> emqx eval "code:which(emqx_channel)."
> ```

### Step 3: Mount Patched Beam
```bash
docker run -d --name emqx-verify \
  -v "$(pwd)/emqx_channel.beam":/opt/emqx/lib/emqx-5.5.4/ebin/emqx_channel.beam \
  emqx/emqx:verify
```

## 3. Debugging with SLOG Logs

Add `?SLOG` statements for runtime debugging:

```erlang
?SLOG(warning, #{msg => "DEBUG_MY_FUNCTION", var1 => Var1, var2 => Var2}),
```

View logs:
```bash
docker logs <container> | grep DEBUG
```

> **Note**: Debug logs won't appear if the patched `.beam` wasn't loaded. Always verify the loaded path first.

## 4. Durable Sessions Testing

For testing session persistence features, enable Durable Sessions via environment:

```bash
docker run -d --name emqx-test \
  -p 1883:1883 \
  -e EMQX_DURABLE_SESSIONS__ENABLE=true \
  -e EMQX_DURABLE_STORAGE__MESSAGES__BACKEND=builtin_local \
  -e EMQX_CLUSTER__DISCOVERY_STRATEGY=singleton \
  emqx/emqx:5.8.8
```

## 5. Common Issues

### CRLF Line Endings (Windows)
Docker containers may fail due to CRLF in shell scripts. Use `dos2unix`:
```dockerfile
RUN find /opt/emqx/bin -type f -exec dos2unix {} \;
```

### Module Load Errors
If `code:load_file` returns `{error, not_purged}`, restart the container.

### Config Validation Errors
Check schema with:
```bash
docker exec <container> emqx eval "emqx_config:get([path, to, key])."
```
