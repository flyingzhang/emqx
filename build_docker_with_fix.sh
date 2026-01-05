#!/usr/bin/env bash

# EMQX Community Edition Docker 镜像构建脚本
# 包含我们的 kick_session 修复补丁

set -euo pipefail

echo "=== 开始构建 EMQX Community Edition Docker 镜像 ==="
echo "包含 kick_session 修复补丁"
echo ""

# 设置环境变量
export MSYS_NO_PATHCONV=1
export PROFILE=emqx

# 可选：如果需要代理，取消下面的注释
# export http_proxy=http://10.66.66.4:3128
# export https_proxy=http://10.66.66.4:3128

# 构建 Docker 镜像
echo "执行构建命令..."
./build emqx docker

echo ""
echo "=== 构建完成 ==="
echo "生成的镜像标签保存在: .emqx_docker_image_tags"
echo ""
echo "查看生成的镜像："
cat .emqx_docker_image_tags
echo ""
echo "运行镜像示例："
echo "docker run -d --name emqx -p 1883:1883 -p 8083:8083 -p 8084:8084 -p 8883:8883 -p 18083:18083 \$(head -1 .emqx_docker_image_tags)"
