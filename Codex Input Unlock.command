#!/bin/bash
# Double-clickable launcher for codex-input-unlock (macOS)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$DIR/codex-input-unlock.sh" launch
STATUS=$?
echo ""
read -r -p "按回车关闭窗口..." _
exit $STATUS
