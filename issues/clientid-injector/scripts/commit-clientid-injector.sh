#!/usr/bin/env bash
# EMQX ClientId Injector 插件 - Git 提交脚本
# 此脚本处理代码格式化和 Git 提交，遵循项目开发规则

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

    if ! command -v git &> /dev/null; then
        log_error "Git 未安装或不在 PATH 中"
        exit 1
    fi

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

    # 获取有变更的 .erl 文件
    local erl_files
    erl_files=$(git diff --name-only | grep -E '.*\.erl$' || true)
    erl_cached=$(git diff --cached --name-only | grep -E '.*\.erl$' || true)

    if [ -z "$erl_files" ] && [ -z "$erl_cached" ]; then
        log_info "没有 .erl 文件需要格式化"
        return 0
    fi

    log_info "发现以下 .erl 文件需要格式化:"
    echo "$erl_files" | sed 's/^/  - /'
    echo "$erl_cached" | sed 's/^/  - /'

    # 在 Docker 容器中运行格式化
    docker run --rm \
        -v "$(pwd):/emqx" \
        -w /emqx \
        "$BUILDER_IMAGE" \
        bash -c "ERLFMT_WRITE=true ./scripts/git-hook-pre-commit.sh" || {
        log_error "代码格式化失败"
        return 1
    }

    # 检查是否有文件被格式化
    local formatted_files
    formatted_files=$(git diff --name-only | grep -E '.*\.erl$' || true)

    if [ -n "$formatted_files" ]; then
        log_warn "以下文件已被格式化，请重新检查:"
        echo "$formatted_files" | sed 's/^/  - /'
        echo ""
        log_warn "请暂存格式化后的变更后重试"
        return 1
    fi

    log_info "代码格式化完成"
}

# 暂存变更
stage_changes() {
    log_info "暂存变更..."

    # 显示未暂存的变更
    local unstaged
    unstaged=$(git diff --name-only)
    if [ -n "$unstaged" ]; then
        log_info "未暂存的文件:"
        echo "$unstaged" | sed 's/^/  - /'
        echo ""
        read -p "是否暂存所有变更? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git add .
            log_info "已暂存所有变更"
        else
            log_warn "请手动暂存需要的文件"
            return 1
        fi
    else
        log_info "没有未暂存的变更"
    fi
}

# 提交变更
commit_changes() {
    log_info "提交变更..."

    # 获取 commit message
    local commit_msg=""
    if [ -n "${1:-}" ]; then
        commit_msg="$1"
    else
        echo "请输入 commit message (留空取消):"
        read -r commit_msg
    fi

    if [ -z "$commit_msg" ]; then
        log_warn "提交已取消"
        return 1
    fi

    # 使用 FORCE=true 跳过版本检查
    FORCE=true git commit -m "$commit_msg" || {
        log_error "提交失败"
        return 1
    }

    log_info "提交成功"

    # 显示提交信息
    echo ""
    git log -1 --stat
}

# 主函数
main() {
    echo "=================================================="
    echo "  EMQX ClientId Injector Git 提交"
    echo "=================================================="
    echo ""

    # 解析参数
    SKIP_FORMAT=false
    SKIP_STAGE=false
    COMMIT_MSG=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-format)
                SKIP_FORMAT=true
                shift
                ;;
            --skip-stage)
                SKIP_STAGE=true
                shift
                ;;
            -m|--message)
                COMMIT_MSG="$2"
                shift 2
                ;;
            -h|--help)
                echo "用法: $0 [选项] [commit-message]"
                echo ""
                echo "选项:"
                echo "  --skip-format    跳过代码格式化"
                echo "  --skip-stage     跳过暂存变更"
                echo "  -m, --message    指定 commit message"
                echo "  -h, --help       显示帮助信息"
                echo ""
                echo "示例:"
                echo "  $0                                    # 交互式提交"
                echo "  $0 -m \"feat: add new feature\"       # 指定消息提交"
                echo "  $0 --skip-format \"fix: bug\"         # 跳过格式化提交"
                exit 0
                ;;
            *)
                # 剩余参数作为 commit message
                COMMIT_MSG="$*"
                break
                ;;
        esac
    done

    # 执行提交流程
    check_dependencies

    echo ""
    [ "$SKIP_FORMAT" = true ] || format_code || exit 1

    echo ""
    [ "$SKIP_STAGE" = true ] || stage_changes || exit 1

    echo ""
    commit_changes "$COMMIT_MSG" || exit 1

    echo ""
    echo "=================================================="
    log_info "提交流程完成!"
    echo "=================================================="
    echo ""
    echo "下一步:"
    echo "  - 查看提交: git log -1"
    echo "  - 推送到远程: git push"
}

main "$@"
