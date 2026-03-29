#!/bin/bash
set -e

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTDIR="$WORKDIR/ruleset"
TMPDIR="/tmp/extra-ruleset-$(date +%s)"

mkdir -p "$TMPDIR"
mkdir -p "$OUTDIR"

cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

download_latest() {
    local url="$1"
    local output="$2"
    if command -v curl &> /dev/null; then
        curl -sSL -o "$output" "$url"
    elif command -v wget &> /dev/null; then
        wget -q -O "$output" "$url"
    else
        exit 1
    fi
}

get_geoview_latest() {
    local api_url="https://api.github.com/repos/snowie2000/geoview/releases/latest"
    local download_url
    if command -v jq &> /dev/null; then
        download_url=$(curl -s "$api_url" | jq -r '.assets[] | select(.name | contains("geoview-linux-amd64")) | .browser_download_url')
    else
        download_url=$(curl -s "$api_url" | grep -o 'https://[^"]*geoview-linux-amd64[^"]*' | head -1)
    fi
    echo "$download_url"
}

get_rules_latest() {
    local api_url="https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases/latest"
    local download_url
    if command -v jq &> /dev/null; then
        download_url=$(curl -s "$api_url" | jq -r '.assets[] | select(.name == "geosite.dat") | .browser_download_url')
    else
        download_url=$(curl -s "$api_url" | grep -o 'https://[^"]*geosite.dat[^"]*' | head -1)
    fi
    echo "$download_url"
}

main() {
    local geoview_url=$(get_geoview_latest)
    local geoview_path="$TMPDIR/geoview"
    download_latest "$geoview_url" "$geoview_path"
    chmod +x "$geoview_path"
    
    local rules_url=$(get_rules_latest)
    local geosite_path="$TMPDIR/geosite.dat"
    download_latest "$rules_url" "$geosite_path"
    
    "$geoview_path" -type geosite -input "$geosite_path" -list "category-ai-!cn" -output "$TMPDIR/ai_rules.txt" 2>/dev/null || echo "geosite:category-ai-!cn" > "$TMPDIR/ai_rules.txt"
    "$geoview_path" -type geosite -input "$geosite_path" -list "category-cdn-cn" -output "$TMPDIR/cdn_rules.txt" 2>/dev/null || echo "geosite:category-cdn-cn" > "$TMPDIR/cdn_rules.txt"
    
    local game_temp="$TMPDIR/game_all.txt"
    > "$game_temp"
    
    for rule in "category-game-platforms-download@cn" "category-games@cn" "steam@cn"; do
        local temp_file="$TMPDIR/game_${rule//[@:\/]/-}.txt"
        "$geoview_path" -type geosite -input "$geosite_path" -list "$rule" -output "$temp_file" 2>/dev/null || continue
        if[ -s "$temp_file" ]; then
            cat "$temp_file" >> "$game_temp"
            echo "" >> "$game_temp"
        fi
    done
    
    if[ -s "$TMPDIR/ai_rules.txt" ]; then
        grep -v '^$' "$TMPDIR/ai_rules.txt" | sort -u | sed 's/^/./' > "$OUTDIR/proxy-ai.list"
    else
        > "$OUTDIR/proxy-ai.list"
    fi
    
    if [ -s "$TMPDIR/cdn_rules.txt" ]; then
        grep -v '^$' "$TMPDIR/cdn_rules.txt" | sort -u | sed 's/^/./' > "$OUTDIR/direct-cdn.list"
    else
        > "$OUTDIR/direct-cdn.list"
    fi
    
    if [ -s "$game_temp" ]; then
        grep -v '^$' "$game_temp" | sort -u | sed 's/^/./' > "$OUTDIR/direct-game.list"
    else
        > "$OUTDIR/direct-game.list"
    fi
}

main "$@"