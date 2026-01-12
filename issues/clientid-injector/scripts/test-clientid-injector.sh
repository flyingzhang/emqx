#!/usr/bin/env bash
# EMQX ClientId Injector 插件 - 完整测试流程
# 此脚本执行插件的所有验证步骤
# 使用方法: 从项目根目录运行 bash issues/clientid-injector/scripts/test-clientid-injector.sh

set -euo pipefail

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 测试文件目录（相对于脚本目录）
TESTS_DIR="$(dirname "$SCRIPT_DIR")/tests"
# 项目根目录
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

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

    if ! command -v python &> /dev/null && ! command -v python3 &> /dev/null; then
        log_error "Python 未安装或不在 PATH 中"
        exit 1
    fi

    log_info "依赖检查通过"
}

# 检查 EMQX 容器状态
check_emqx_running() {
    if ! docker ps --format '{{.Names}}' | grep -q '^emqx$'; then
        log_warn "EMQX 容器未运行，请先启动："
        echo "docker run -d --name emqx -p 1883:1883 -p 18083:18083 \\"
        echo "  -e EMQX_CLUSTER__DISCOVERY_STRATEGY=singleton \\"
        echo "  emqx/emqx:5.8.9-g2ea5ffc7"
        exit 1
    fi
    log_info "EMQX 容器正在运行"
}

# 验证插件已加载
verify_plugin_loaded() {
    log_info "验证插件加载状态..."

    local result
    result=$(docker exec emqx sh -c "emqx eval 'lists:filter(fun({App, _, _}) -> string:find(atom_to_list(App), \"clientid\") /= nomatch end, application:which_applications()).' 2>&1 || echo error")

    if echo "$result" | grep -q "emqx_clientid_injector"; then
        log_info "插件已加载: emqx_clientid_injector"
        return 0
    else
        log_error "插件未加载"
        return 1
    fi
}

# 验证 Hook 已注册
verify_hook_registered() {
    log_info "验证 Hook 注册状态..."

    # 简化的检查：查看 ETS 表中是否有 message.publish hook
    local result
    result=$(docker exec emqx sh -c "emqx eval 'case ets:lookup(emqx_hooks, {{emqx, message.publish}}) of [{_, _, Callbacks}] -> lists:any(fun({callback,{Mod,_,_},_,_}) -> Mod =:= emqx_clientid_injector; (_) -> false end, Callbacks); _ -> false end.' 2>&1")

    if echo "$result" | grep -q "true"; then
        log_info "Hook 已注册: emqx_clientid_injector:on_message_publish"
        return 0
    else
        log_error "Hook 未注册"
        return 1
    fi
}

# 运行 MQTT 5.0 测试
run_mqtt5_test() {
    log_info "运行 MQTT 5.0 测试..."

    local python_cmd="python"
    if ! command -v python &> /dev/null; then
        python_cmd="python3"
    fi

    cd "$PROJECT_ROOT"
    if $python_cmd "$TESTS_DIR/test_clientid_injector.py"; then
        log_info "MQTT 5.0 测试通过"
        return 0
    else
        log_error "MQTT 5.0 测试失败"
        return 1
    fi
}

# 运行跨版本测试
run_cross_version_test() {
    log_info "运行 MQTT 3.x -> MQTT 5.0 跨版本测试..."

    local python_cmd="python"
    if ! command -v python &> /dev/null; then
        python_cmd="python3"
    fi

    cd "$PROJECT_ROOT"
    if $python_cmd "$TESTS_DIR/test_mqtt3_to_mqtt5.py"; then
        log_info "跨版本测试通过"
        return 0
    else
        log_error "跨版本测试失败"
        return 1
    fi
}

# 主函数
main() {
    echo "=================================================="
    echo "  EMQX ClientId Injector 插件测试"
    echo "=================================================="
    echo ""

    # 解析参数
    SKIP_MQTT5=false
    SKIP_CROSS=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-mqtt5)
                SKIP_MQTT5=true
                shift
                ;;
            --skip-cross)
                SKIP_CROSS=true
                shift
                ;;
            -h|--help)
                echo "用法: $0 [选项]"
                echo ""
                echo "选项:"
                echo "  --skip-mqtt5    跳过 MQTT 5.0 测试"
                echo "  --skip-cross    跳过跨版本测试"
                echo "  -h, --help      显示帮助信息"
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                exit 1
                ;;
        esac
    done

    # 执行测试
    check_dependencies

    echo ""
    check_emqx_running

    echo ""
    verify_plugin_loaded || exit 1

    echo ""
    if [ "$SKIP_MQTT5" = false ]; then
        run_mqtt5_test || exit 1
    else
        log_warn "跳过 MQTT 5.0 测试"
    fi

    echo ""
    if [ "$SKIP_CROSS" = false ]; then
        run_cross_version_test || exit 1
    else
        log_warn "跳过跨版本测试"
    fi

    echo ""
    echo "=================================================="
    log_info "所有测试通过!"
    echo "=================================================="
}

main "$@"
