#!/bin/bash
# Extra Ruleset Generator
# 从 v2ray-rules-dat 的 geosite.dat 中提取特定规则

set -e

# 工作目录
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="/tmp/extra-ruleset-$(date +%s)"
mkdir -p "$TMPDIR"

# 日志输出（移除颜色代码避免干扰）
log_info() {
    echo "[INFO] $1"
}

log_warn() {
    echo "[WARN] $1"
}

log_error() {
    echo "[ERROR] $1"
}

# 清理函数
cleanup() {
    log_info "清理临时文件..."
    rm -rf "$TMPDIR"
}

# 注册清理函数
trap cleanup EXIT

# 获取最新版本的工具和规则
download_latest() {
    local url="$1"
    local output="$2"
    
    log_info "下载: $url"
    if command -v curl &> /dev/null; then
        curl -sSL -o "$output" "$url"
    elif command -v wget &> /dev/null; then
        wget -q -O "$output" "$url"
    else
        log_error "需要 curl 或 wget"
        exit 1
    fi
}

# 获取 geoview 最新版本
get_geoview_latest() {
    # 从 GitHub API 获取最新版本
    local api_url="https://api.github.com/repos/snowie2000/geoview/releases/latest"
    local download_url
    
    if command -v jq &> /dev/null; then
        download_url=$(curl -s "$api_url" | jq -r '.assets[] | select(.name | contains("geoview-linux-amd64")) | .browser_download_url')
    else
        # 如果没有 jq，使用 grep 提取
        download_url=$(curl -s "$api_url" | grep -o 'https://[^"]*geoview-linux-amd64[^"]*' | head -1)
    fi
    
    if [ -z "$download_url" ]; then
        log_error "无法获取 geoview 下载链接"
        exit 1
    fi
    
    echo "$download_url"
}

# 获取 v2ray-rules-dat 最新版本
get_rules_latest() {
    local api_url="https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases/latest"
    local download_url
    
    if command -v jq &> /dev/null; then
        download_url=$(curl -s "$api_url" | jq -r '.assets[] | select(.name == "geosite.dat") | .browser_download_url')
    else
        download_url=$(curl -s "$api_url" | grep -o 'https://[^"]*geosite.dat[^"]*' | head -1)
    fi
    
    if [ -z "$download_url" ]; then
        log_error "无法获取 geosite.dat 下载链接"
        exit 1
    fi
    
    echo "$download_url"
}

# 主函数
main() {
    log_info "开始生成规则..."
    log_info "工作目录: $WORKDIR"
    log_info "临时目录: $TMPDIR"
    
    # 1. 下载 geoview
    log_info "=== 步骤 1: 下载 geoview ==="
    local geoview_url=$(get_geoview_latest)
    local geoview_path="$TMPDIR/geoview"
    download_latest "$geoview_url" "$geoview_path"
    chmod +x "$geoview_path"
    
    # 验证 geoview
    if [ ! -x "$geoview_path" ]; then
        log_error "geoview 下载失败或不可执行"
        exit 1
    fi
    
    log_info "geoview 版本: $("$geoview_path" --version 2>/dev/null || echo "未知版本")"
    
    # 2. 下载 geosite.dat
    log_info "=== 步骤 2: 下载 geosite.dat ==="
    local rules_url=$(get_rules_latest)
    local geosite_path="$TMPDIR/geosite.dat"
    download_latest "$rules_url" "$geosite_path"
    
    if [ ! -s "$geosite_path" ]; then
        log_error "geosite.dat 下载失败或为空"
        exit 1
    fi
    
    log_info "geosite.dat 大小: $(du -h "$geosite_path" | cut -f1)"
    
    # 3. 提取规则
    log_info "=== 步骤 3: 提取规则 ==="
    
    # 提取 AI 规则 (category-ai-!cn)
    log_info "提取 AI 规则 (category-ai-!cn)..."
    "$geoview_path" -type geosite -input "$geosite_path" -list "category-ai-!cn" -output "$TMPDIR/ai_rules.txt" 2>/dev/null || {
        log_warn "geoview 提取失败，尝试备用方法..."
        # 备用方法：如果 geoview 不支持直接提取，尝试其他方式
        echo "geosite:category-ai-!cn" > "$TMPDIR/ai_rules.txt"
    }
    
    # 提取游戏规则
    log_info "提取游戏规则..."
    
    # 创建临时文件用于合并
    local game_temp="$TMPDIR/game_all.txt"
    > "$game_temp"
    
    # 提取三个游戏相关的规则
    for rule in "category-game-platforms-download@cn" "category-games@cn" "steam@cn"; do
        log_info "提取规则: $rule"
        local temp_file="$TMPDIR/game_${rule//[@:\/]/-}.txt"
        "$geoview_path" -type geosite -input "$geosite_path" -list "$rule" -output "$temp_file" 2>/dev/null || {
            log_warn "规则 $rule 提取失败，跳过..."
            continue
        }
        
        if [ -s "$temp_file" ]; then
            cat "$temp_file" >> "$game_temp"
            echo "" >> "$game_temp"  # 添加换行分隔
        fi
    done
    
    # 4. 处理提取的规则
    log_info "=== 步骤 4: 处理规则 ==="
    
    # 处理 AI 规则
    if [ -s "$TMPDIR/ai_rules.txt" ]; then
        log_info "处理 AI 规则..."
        # 移除空行和重复项，排序，并添加"."前缀
        grep -v '^$' "$TMPDIR/ai_rules.txt" | sort -u | sed 's/^/./' > "$WORKDIR/proxy-ai.list"
        log_info "AI 规则数量: $(wc -l < "$WORKDIR/proxy-ai.list")"
    else
        log_warn "未提取到 AI 规则，创建空文件"
        > "$WORKDIR/proxy-ai.list"
    fi
    
    # 处理游戏规则
    if [ -s "$game_temp" ]; then
        log_info "处理游戏规则..."
        # 移除空行、重复项，排序，并添加"."前缀
        grep -v '^$' "$game_temp" | sort -u | sed 's/^/./' > "$WORKDIR/proxy-game.list"
        log_info "游戏规则数量: $(wc -l < "$WORKDIR/proxy-game.list")"
    else
        log_warn "未提取到游戏规则，创建空文件"
        > "$WORKDIR/proxy-game.list"
    fi
    
    # 5. 验证生成的文件
    log_info "=== 步骤 5: 验证结果 ==="
    
    for file in "proxy-ai.list" "proxy-game.list"; do
        if [ -f "$WORKDIR/$file" ]; then
            local line_count=$(wc -l < "$WORKDIR/$file")
            local file_size=$(du -h "$WORKDIR/$file" | cut -f1)
            log_info "$file: $line_count 行, 大小: $file_size"
            
            # 显示前5行作为示例
            if [ "$line_count" -gt 0 ]; then
                log_info "前5行示例:"
                head -5 "$WORKDIR/$file" | sed 's/^/  /'
            fi
        else
            log_error "$file 未生成"
        fi
    done
    
    log_info "=== 完成 ==="
    log_info "规则文件已生成到: $WORKDIR/"
    log_info "- proxy-ai.list"
    log_info "- proxy-game.list"
}

# 运行主函数
main "$@"