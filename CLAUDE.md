# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Zenn CLI を使った技術ブログリポジトリ。記事は `articles/` に、本は `books/` に Markdown で管理する。

## Commands

- **プレビュー**: `npx zenn preview` — ローカルでブラウザプレビュー
- **新規記事作成**: `npx zenn new:article --slug <slug>` — slugは半角英数字とハイフン(12〜50文字)
- **新規本作成**: `npx zenn new:book --slug <slug>`
- **textlint**: `npx textlint articles/<file>.md` — 日本語校正チェック

## Linting

textlint で日本語の文章校正を行う。有効なプリセット:
- `preset-ja-technical-writing` — 技術文書向けルール(句読点、漢字の閉じ開き等)
- `@textlint-ja/preset-ai-writing` — AI生成文の品質チェック

`articles/` `books/` の Markdown を Edit/Write すると PostToolUse hook (`.claude/hooks/textlint.sh`) が自動で `--fix` → 再チェックを実行し、自動修正できない指摘が残るとエラーとして報告される(書き込み自体は完了しているので、続けて手で直す)。
- `npx textlint --fix` は自動修正できなかった指摘を報告せず exit 0 を返す。校正漏れの確認は必ず `--fix` なしで実行する
- textlint は `.textlintrc.json` を cwd から探すため、リポジトリルートで実行する(別ディレクトリだとルールが効かないまま無言で成功する)

## 記事執筆フロー

ネタ整理・構成づくりは `blog-brainstorm` スキル、構成メモから本文の清書は `blog-write` スキルを使う。図版は draw.io で作成し `images/` に `.drawio` と書き出し PNG を併置する。

## Zenn 記事のフォーマット

記事ファイルは以下の frontmatter を持つ:
```yaml
---
title: ""
emoji: ""
type: "tech" # tech or idea
topics: []
published: false
---
```
