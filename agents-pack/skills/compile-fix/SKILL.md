---
name: compile-fix
description: "Flix のコンパイルエラーを診断し、既知の落とし穴（予約語・import の位置・エフェクト伝播忘れ・Channel API・Java 例外型・パターン網羅性・Float32 サフィックス等）と照合して修正を出す。flix check / flix test / make が失敗したとき、E3138・E5252・E6217 等のエラー番号が出たとき、Unexpected token・Parse error・Unable to unify・Non-exhaustive match・Unresolved type が出たとき、「Expected ',' before '='」のような原因の見えないパースエラーが出たときに使う。"
allowed-tools: Read, Grep, Glob, Bash
sync: 2026-08-12
---

# Flix コンパイルエラー診断

コンパイルエラーが発生した場合、このスキルで原因を特定し修正する。

## 手順

0. **型・引数・名前のエラー (Undefined name / Unexpected type / Unable to unify 等) は、
   まず engine の `docs/api-digest.md`（全 pub 宣言のダイジェスト。`make api Q=<名前>` で
   1 行でも引ける）で正しいシグネチャを確かめる** — ソースの grep や unzip より先。
1. エラーメッセージを確認する（ユーザー提示 or `make check`（型検査だけ・一番速い）/ `make test` を実行）
2. 下記の「既知の落とし穴リスト」と照合する
3. 該当する場合は修正方法を提示する
4. 該当しない場合は、エラー箇所のコードを読んで一般的な診断を行う

補足: `make check` の失敗出力の末尾には `bin/explain-error` が処方箋 1 行を自動で添える。
その対応表の実体は `bin/explain-error` にあり、由来はこのスキルの落とし穴リスト —
落とし穴を足したら両方を更新する。

## 既知の落とし穴リスト（Flix 0.75.1）

### 1. 予約語の使用（パースエラー）

**症状**: `Unexpected token` / `Parse error` が変数名や import 文で発生

**修正**: 予約語（`handler`, `do`, `resume`, `run`, `spawn`, `region`, `inject`, `project`, `solve`）を識別子に使わない。別の単語か 2 単語以上で命名する。変数・関数名だけでなく**レコードのフィールド名**（`{ spawn = Cell }` 等）でもパースエラーになる。ゲームで踏みやすいのは `spawn`（湧き位置）と `run`（走り・実行）— `start` / `walkR` などへ逃がす。詳細は `flix-docs` の「予約語に注意」を参照。

### 2. import の位置（スコープエラー）

**症状**: Java クラスが見つからない / `Unresolved type`

**修正**: Java の import をモジュール直下（関数の外）に移動する。詳細は `flix-docs` の「Java interop」を参照。

### 3. Channel API の引数（型エラー）

**症状**: `Channel.buffered` で型が合わない / Region 関連エラー

**修正**: `Channel.buffered(rc)` → `Channel.buffered(size)`。戻り値は `(Sender[t], Receiver[t])`。詳細は `flix-docs` の「Channel API」を参照。

### 4. try-catch の例外型（型エラー）

**症状**: `##java.io.IOException` が見つからない

**修正**: `##` プレフィックスを外し、`import java.io.IOException` してからクラス名で使う。詳細は `flix-docs` の「try-catch での Java 例外」を参照。

### 5. レコード更新の構文（型エラー）

**症状**: レコードのフィールド更新で型が合わない

**原因**: Flix のレコード更新は `{field = newValue | record}` だが、型が異なると動かない

**修正**: レコード更新構文のパイプ右側がレコード変数であること、型が一致することを確認。

### 6. エフェクトの伝播忘れ（型エラー）

**症状**: 関数の戻り値型でエフェクトが合わない

**原因**: 呼び出し先のエフェクトを関数シグネチャに含めていない

**修正**: 関数の型注釈にエフェクトを追加する（`\ IO + ef` など）。不明なら型注釈を外して推論に任せる。

### 7. パターンマッチの網羅性（警告/エラー）

**症状**: `Non-exhaustive match`

**原因**: enum の全ケースを網羅していない

**修正**: 不足している case を追加するか、`case _ =>` を追加。

### 8. List/Set/Map リテラルの型推論失敗

**症状**: `Unable to unify` / 空リテラルで型が決まらない

**原因**: `Nil` や `Set.empty()` だけでは型が推論できないことがある

**修正**: 型注釈を付ける（例: `(Nil: List[Int32])`）、または要素付きで初期化。

### 9. Float32 リテラルのサフィックス忘れ

**症状**: `Expected Float32 but got Float64`

**原因**: `1.0` は Float64。Float32 が必要な箇所では `1.0f32` と書く必要がある。

**修正**: 全ての浮動小数点リテラルに `f32` サフィックスを付ける。

## 一般的な診断フロー

上記に該当しない場合:

1. エラーメッセージの行番号から該当ファイルを `Read` で確認
2. 型エラーの場合 → 関連する型定義を `Grep` で探す
3. 未解決シンボルの場合 → `Glob` + `Grep` で定義箇所を探す
4. 修正案を提示し、`/verify` で確認する
