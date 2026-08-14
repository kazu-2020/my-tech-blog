#!/bin/sh
# PostToolUse (Edit|Write) hook: articles/ books/ 配下の Markdown を textlint で校正する。
#
# stdin から Claude Code のツール呼び出し JSON を受け取る。
# ファイルパスは環境変数ではなく、この JSON の中にしか無い点に注意。
#
# textlint --fix は「修正できなかった指摘」を報告せず exit 0 を返すため、
# --fix だけでは校正漏れを検知できない。よって
#   1. --fix で自動修正（出力は捨てる）
#   2. --fix なしで再チェックし、残った指摘を報告して exit 1
# の 2 段構えにしている。
#
# 対象外のファイル、パスが取れない場合、JSON が壊れている場合は何もせず exit 0。

set -u

# textlint は .textlintrc.json を cwd から探すため、
# 呼び出し元の cwd に依存しないよう自身の位置からプロジェクトルートへ移動する。
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd) || exit 0
cd "$root" || exit 0

f=$(jq -r '.tool_response.filePath // .tool_input.file_path // empty') || exit 0
[ -n "$f" ] || exit 0

case "$f" in
  *articles/*.md | *books/*.md) ;;
  *) exit 0 ;;
esac

# 削除済み・未作成のファイルで textlint を落とさない
[ -f "$f" ] || exit 0

npx textlint --fix "$f" >/dev/null 2>&1

if ! out=$(npx textlint "$f" 2>&1); then
  printf '%s\n' \
    "textlint: 自動修正できない指摘があります。手動で修正してください。" \
    "---" \
    "$out"
  exit 1
fi
