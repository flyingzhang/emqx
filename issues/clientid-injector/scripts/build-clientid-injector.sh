#!/usr/bin/env bash
# EMQX ClientId Injector 插件 - 构建脚本
# 此脚本执行插件的完整构建流程

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装或不在 PATH 中"
        exit 1
    fi

    # 设置 MSYS_NO_PATHCONV 避免 Git Bash 路径转换问题
    export MSYS_NO_PATHCONV=1

    log_info "依赖检查通过"
}

# 格式化代码
format_code() {
    log_info "格式化代码..."

    local BUILDER_IMAGE="ghcr.io/emqx/emqx-builder/5.6-2:1.15.7-26.2.5.14-1-debian13"

    # 检查是否有 .erl 文件变更
    local erl_files
    erl_files=$(git diff --name-only | grep -E '.*\.erl$' || true)
    erl_cached=$(git diff --cached --name-only | grep -E '.*\.erl$' || true)

    if [ -z "$erl_files" ] && [ -z "$erl_cached" ]; then
        log_info "没有 .erl 文件变更，跳过格式化"
        return 0
    fi

    # 在 Docker 容器中运行格式化
    docker run --rm \
        -v "$(pwd):/emqx" \
        -w /emqx \
        "$BUILDER_IMAGE" \
        bash -c "ERLFMT_WRITE=true ./scripts/git-hook-pre-commit.sh" || {
        log_error "代码格式化失败"
        return 1
    }

    log_info "代码格式化完成"
}

# 编译插件
compile_plugin() {
    log_info "编译插件..."

    local BUILDER_IMAGE="ghcr.io/emqx/emqx-builder/5.6-2:1.15.7-26.2.5.14-1-debian13"

    docker run --rm \
        -v "$(pwd):/emqx" \
        -w /emqx/apps/emqx_clientid_injector \
        "$BUILDER_IMAGE" \
        bash -c "rebar3 compile" || {
        log_error "插件编译失败"
        return 1
    }

    log_info "插件编译完成"
}

# 构建 Docker 镜像
build_docker_image() {
    log_info "构建 Docker 镜像..."

    local PROFILE="${PROFILE:-emqx}"

    # 使用 EMQX 的构建脚本
    ./build "$PROFILE" docker || {
        log_error "Docker 镜像构建失败"
        return 1
    }

    log_info "Docker 镜像构建完成"
}

# 启动测试容器
start_test_container() {
    log_info "启动测试容器..."

    # 停止并删除现有容器
    if docker ps -a --format '{{.Names}}' | grep -q '^emqx-test$'; then
        docker stop emqx-test &> /dev/null || true
        docker rm emqx-test &> /dev/null || true
    fi

    # 获取镜像标签
    if [ ! -f .emqx_docker_image_tags ]; then
        log_error "未找到 .emqx_docker_image_tags 文件"
        return 1
    fi

    local IMAGE_TAG
    IMAGE_TAG=$(head -1 .emqx_docker_image_tags)

    # 启动容器
    docker run -d \
        --name emqx-test \
        -p 1883:1883 \
        -p 8083:8083 \
        -p 8883:8883 \
        -p 18083:18083 \
        -e EMQX_CLUSTER__DISCOVERY_STRATEGY=singleton \
        "$IMAGE_TAG" || {
        log_error "容器启动失败"
        return 1
    }

    # 等待 EMQX 启动
    log_info "等待 EMQX 启动..."
    local max_wait=60
    local waited=0

    while [ $waited -lt $max_wait ]; do
        if docker exec emqx-test sh -c "emqx ping" &> /dev/null; then
            log_info "EMQX 已就绪"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done

    log_error "EMQX 启动超时"
    return 1
}

# 运行测试
run_tests() {
    log_info "运行测试..."

    if [ ! -f scripts/test-clientid-injector.sh ]; then
        log_error "测试脚本不存在: scripts/test-clientid-injector.sh"
        return 1
    fi

    bash scripts/test-clientid-injector.sh || {
        log_error "测试失败"
        return 1
    }

    log_info "测试通过"
}

# 清理测试容器
cleanup() {
    log_info "清理测试容器..."
    docker stop emqx-test &> /dev/null || true
    docker rm emqx-test &> /dev/null || true
    log_info "清理完成"
}

# 主函数
main() {
    echo "=================================================="
    echo "  EMQX ClientId Injector 插件构建"
    echo "=================================================="
    echo ""

    # 解析参数
    SKIP_FORMAT=false
    SKIP_COMPILE=false
    SKIP_BUILD=false
    SKIP_START=false
    SKIP_TESTS=false
    NO_CLEANUP=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-format)
                SKIP_FORMAT=true
                shift
                ;;
            --skip-compile)
                SKIP_COMPILE=true
                shift
                ;;
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            --skip-start)
                SKIP_START=true
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --no-cleanup)
                NO_CLEANUP=true
                shift
                ;;
            -h|--help)
                echo "用法: $0 [选项]"
                echo ""
                echo "选项:"
                echo "  --skip-format    跳过代码格式化"
                echo "  --skip-compile   跳过插件编译"
                echo "  --skip-build     跳过 Docker 镜像构建"
                echo "  --skip-start     跳过启动测试容器"
                echo "  --skip-tests     跳过运行测试"
                echo "  --no-cleanup     不清理测试容器"
                echo "  -h, --help       显示帮助信息"
                echo ""
                echo "示例:"
                echo "  $0                  # 完整构建流程"
                echo "  $0 --skip-format    # 跳过格式化"
                echo "  $0 --no-cleanup     # 保留测试容器"
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                exit 1
                ;;
        esac
    done

    # 注册清理函数
    trap cleanup EXIT

    # 执行构建流程
    check_dependencies

    echo ""
    [ "$SKIP_FORMAT" = true ] || format_code || exit 1

    echo ""
    [ "$SKIP_COMPILE" = true ] || compile_plugin || exit 1

    echo ""
    [ "$SKIP_BUILD" = true ] || build_docker_image || exit 1

    echo ""
    [ "$SKIP_START" = true ] || start_test_container || exit 1

    echo ""
    [ "$SKIP_TESTS" = true ] || run_tests || exit 1

    # 如果不清理，取消 trap
    if [ "$NO_CLEANUP" = true ]; then
        trap - EXIT
        log_warn "测试容器保留，请手动清理: docker stop emqx-test && docker rm emqx-test"
    fi

    echo ""
    echo "=================================================="
    log_info "构建完成!"
    echo "=================================================="
}

main "$@"
