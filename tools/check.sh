#!/bin/bash
# 取り込み（import）とスクリプトの解析エラーだけを表示する
GP="/c/Users/katom/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")/.."
timeout 300 "$GP" --headless --path . --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|at: |ERROR|WARNING" | grep -v "^$" | head -${1:-40}
