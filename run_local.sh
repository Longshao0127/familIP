#!/bin/bash
# ════════════════════════════════════════════════════════════════════
# 一键启动脚本: 中国大陆本地运行节点测活
# 原理: 通过本地代理 (v2rayN/Clash/sing-box) 链出海, 模拟 GitHub Actions 海外视角
# ════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── 1. 自动检测本地代理端口 ──────────────────────────────────────────
detect_proxy() {
    # 优先级: 用户指定 > 环境变量 > 自动检测常见端口
    local front_proxy="${1:-}"
    if [ -z "$front_proxy" ]; then
        front_proxy="${FRONT_PROXY:-}"
    fi
    if [ -z "$front_proxy" ]; then
        echo "[*] 未指定 FRONT_PROXY, 自动检测本地代理端口 ..."
        # 常见 socks5 端口: v2rayN=10808, sing-box=1080, Clash=7891
        local socks_ports=(10808 1080 7891 2080 1086)
        for port in "${socks_ports[@]}"; do
            # 检测端口是否在监听 (macOS)
            if lsof -iTCP:$port -sTCP:LISTEN &>/dev/null 2>&1; then
                front_proxy="socks5h://127.0.0.1:${port}"
                echo "[+] 检测到本地 socks5 代理: ${front_proxy}"
                break
            fi
        done
    fi
    if [ -z "$front_proxy" ]; then
        echo ""
        echo "⚠  未检测到本地代理!"
        echo "请先启动你的代理客户端 (v2rayN / Clash / sing-box), 然后:"
        echo ""
        echo "  方式 A: 手动指定"
        echo "    export FRONT_PROXY='socks5h://127.0.0.1:你的端口'"
        echo "    bash run_local.sh"
        echo ""
        echo "  方式 B: 用 HTTP 代理"
        echo "    export FRONT_PROXY='http://127.0.0.1:7890'"
        echo "    bash run_local.sh"
        echo ""
        exit 1
    fi
    echo "$front_proxy"
}

FRONT_PROXY="$(detect_proxy "${1:-}")"
export FRONT_PROXY

# ── 2. 设置 DIRECT_SESSION 的环境代理 (抓订阅源需要过墙) ──────────────
# DIRECT_SESSION.trust_env=True, 所以这里设置 HTTP_PROXY 就会生效
if echo "$FRONT_PROXY" | grep -q "^socks5h\?://"; then
    # socks5:// 不能直接用作 HTTP 代理, 需要用户同时有 HTTP 代理
    http_proxy="${HTTP_PROXY:-}"
    if [ -z "$http_proxy" ]; then
        # 自动检测常见 HTTP 代理端口
        for port in 7890 10809 1087; do
            if lsof -iTCP:$port -sTCP:LISTEN &>/dev/null 2>&1; then
                http_proxy="http://127.0.0.1:${port}"
                echo "[+] 检测到本地 HTTP 代理: ${http_proxy} (用于抓 GitHub 订阅源)"
                break
            fi
        done
    fi
    if [ -z "$http_proxy" ]; then
        echo "[*] 未检测到 HTTP 代理, DIRECT_SESSION 可能无法抓 GitHub 订阅源"
        echo "    (GitHub raw 在大陆直连会被重置, 建议开启 HTTP 代理)"
    else
        export HTTP_PROXY="$http_proxy"
        export HTTPS_PROXY="$http_proxy"
        export http_proxy="$http_proxy"
        export https_proxy="$http_proxy"
    fi
else
    # FRONT_PROXY 本身就是 HTTP
    export HTTP_PROXY="$FRONT_PROXY"
    export HTTPS_PROXY="$FRONT_PROXY"
    export http_proxy="$FRONT_PROXY"
    export https_proxy="$FRONT_PROXY"
fi

# ── 3. 准备 Python 环境 ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -d ".venv" ]; then
    echo "[*] 创建 Python 虚拟环境 ..."
    python3 -m venv .venv
fi
source .venv/bin/activate

if ! python -c "import requests, yaml, maxminddb" 2>/dev/null; then
    echo "[*] 安装依赖 ..."
    pip install requests pyyaml maxminddb --quiet
fi

# ── 4. 清理旧的 sing-box 临时配置文件 ───────────────────────────────
rm -f runtime/sb_*.json

# ── 5. 运行主脚本 ────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  前置代理:  ${FRONT_PROXY}"
echo "  工作目录:  ${SCRIPT_DIR}"
echo "  Python:    $(which python) ($(python --version 2>&1))"
echo "═══════════════════════════════════════════════════════════════"
echo ""

python main_v2.py "$@"

echo ""
echo "[+] 完成! 订阅文件在 output/ 目录下:"
ls -lh output/*.txt output/*.yaml output/*.json 2>/dev/null | awk '{print "    " $NF " (" $5 ")"}'
