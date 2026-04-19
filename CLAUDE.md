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
