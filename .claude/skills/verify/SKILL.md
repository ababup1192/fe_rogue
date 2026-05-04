---
name: verify
description: "コード変更後にflix testとflix runの2段階検証を順番に行う"
disable-model-invocation: true
allowed-tools:
  - "Bash(devbox run -- java -jar bin/flix.jar *)"
---

# 変更後の検証実行

コード変更後に `flix test` と `flix run` の2段階検証を順番に行います。

## 手順

### ステップ 1: テスト実行

`flix test` を実行する。

- **成功した場合**: ステップ2に進む
- **失敗した場合**: 失敗したテストの詳細を報告して**停止**する。`flix run` は実行しない

### ステップ 2: 動作確認

テストが全て通過した後、`flix run` を開発者に実行してもらい、以下を確認する：

- ビルドエラーや動作確認に問題がないことを確認しもらう。


## 注意事項

- `flix test` が失敗した場合は絶対に `flix run` を実行しないこと
- エラーメッセージは省略せず、ユーザーが修正に必要な情報を全て含めること
