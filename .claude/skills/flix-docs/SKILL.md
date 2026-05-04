---
name: flix-docs
description: "Flixの公式ドキュメントとプロジェクト固有のコーディングスタイルを確認する。パイプスタイル、エフェクト構文、テストの書き方、0.71.0固有の注意点を含む - Flixコードを新規作成・修正するとき、テストを書くとき、Flix構文を確認したいとき"
---

# Flix ドキュメント参照

Flixコードを書く・修正する前に、公式LLM向けドキュメントと本プロジェクトのルールを確認してください。

## 手順

1. **WebFetch** で `https://doc.flix.dev/for-llms.html` を取得する
2. 以下の項目を特に確認する：
   - 型システムとエフェクト構文
   - モジュール規約
   - パターンマッチの書き方
   - パイプ演算子 `|>` の使い方

3. 取得したドキュメントの要点を簡潔に提示し、これからの作業に関連する部分をハイライトすること

4. 以下のプロジェクト固有ルールを必ずリマインドすること

---

## Flix コーディングスタイル

### 全般

- **変数名は省略せず、意味が伝わる名前にすること**
  - 型がある場合は、まず型名と揃えられないかを検討する
  - `p` → `player`、`scn` → `scene`、`btn` → `button` のように省略しない

```flix
// NG: 略しすぎて意味が伝わらない
def update(p: Player, scn: Scene): Scene = ...

// OK: 型名と揃えて明確にする
def update(player: Player, scene: Scene): Scene = ...
```

- 関数には必ずドキュメントコメントを書くこと。何の処理をしているか、意図が読み手に明確に伝わること
- ドキュメントコメントは、汎用的なものを除いて、専門用語を避けて、平易な言葉で説明すること
- type alias でレコード定義、enum、struct は、全体のコメントと各フィールドの役割のコメントを書くこと
- 関数の引数にプリミティブな引数が並ぶ場合は、named-parameters と syntax sugar を採用すること
  - https://doc.flix.dev/records.html?highlight=name#named-parameters
  - 特に **同じ型・似た型が連続するとき**（例: `Float64, Float64`）は取り違えバグの温床になるので必ずレコード化すること
  - **4 つ以上の引数**で意味の単位が混在しているときも検討する
  - 一緒に使われ続けるパラメータセットは型エイリアスにして再利用する
    - 例: `(rootJsonIndex, scene)` → `EditableNode.LookupCtx`、`(mousePos, mouseLeft)` → `DragInput.MouseSnapshot`
  - **同じ形のレコードを複数の関数で使うときは、シグネチャにインライン定義せず `type alias` を共有する**（フィールド追加時の修正漏れを防ぐ）

```flix
// NG: 同じ形を複数の関数で繰り返す
def hitTest(input: {pos = Vec2, button = MouseButton}, scene: Scene): ...
def startDrag(input: {pos = Vec2, button = MouseButton}, scene: Scene): ...

// OK: 1 か所で type alias 定義
type alias MouseSnapshot = {pos = Vec2, button = MouseButton}
def hitTest(input: MouseSnapshot, scene: Scene): ...
def startDrag(input: MouseSnapshot, scene: Scene): ...
```

```flix
// NG: Float64 連続 / 4 引数で取り違え危険
def makeLine(pos: Vec2.Vec2, width: Float64, height: Float64, color: Color): ColorRect

// OK: size を Vec2 にしてレコードで束ねる
def makeLine(line: {pos = Vec2.Vec2, size = Vec2.Vec2}, color: Color): ColorRect
```

### パイプスタイル

- なるべくパイプスタイルを使い `|>` で一時変数を作らないこと
- インラインで書ける場合は、インラインで書いて、一時変数を作らないこと
- `|>` で書きやすいように、レシーバとなる変数を最後の引数として関数を作ること

### 高階関数

- パターンマッチがネストしないように、高階関数をなるべく利用すること
- `map`, `flatMap` などが続いたら、`forM` が使えないか検討すること
- `map`, `filter` などが続いたら、`filterMap` 等の関数が使えないか検討すること

### Algebraic Effect の扱い方

- **エフェクトはすぐに `run` せず、呼び出し元へ伝播させること**
  - その場で `run` すると IO に変換され、関数シグネチャが `IO` だらけになる
  - IO が伝播すると「何の副作用が起きているか」が型から読み取れなくなる
  - エフェクトを具体的に残すことで、関数の副作用が明示的になる

```flix
// NG: その場で run して IO に変換してしまう
def getTimestamp(): Int64 \ IO =
    run Clock.currentTime(TimeUnit.Milliseconds) with Clock.runWithIO

// OK: エフェクトを伝播させる（run は呼び出し元に任せる）
def getTimestamp(): Int64 \ Clock =
    Clock.currentTime(TimeUnit.Milliseconds)
```

- **ハンドラの選択は以下の優先順位に従うこと**
  1. **DefaultHandler（何も指定しない）** — `main` や `@Test` ではコンパイラが `@DefaultHandler` を自動挿入するので、明示的なハンドラは不要
  2. **組み込みハンドラを `with` で指定** — ライブラリが提供する `runWithIO` 等を使う
  3. **`with handler` で手書き** — カスタムの振る舞いが必要な場合の最終手段

```flix
// 優先度1: DefaultHandler に任せる（推奨）
// main や @Test ではエフェクトをシグネチャに書くだけでよい
def main(): Unit \ {Clock, Logger} =
    let ts = Clock.currentTime(TimeUnit.Milliseconds);
    Logger.info("Timestamp: ${ts}")

// 優先度2: 組み込みハンドラを with で指定
def example(): Unit \ IO =
    run someEffectfulWork() with Clock.runWithIO

// 優先度3: 手書き handler（最終手段）
def example2(): Unit \ IO =
    run someEffectfulWork() with handler Clock {
        def currentTime(u, k) = k(0i64)
    }
```

- 参考: https://doc.flix.dev/default-handlers.html

- **`run` はネストしないこと** — 複数のエフェクトを 1 ブロックで剥がすときは `run { } with X with Y with Z` の連結構文を使う

```flix
// NG: run の入れ子
run {
    run f() with handler X { ... }
} with handler Y { ... }

// OK: 1 つの run に with を連結
run {
    f()
} with handler X { ... }
  with handler Y { ... }
```

### ライブラリ選択（Java interop より標準ライブラリを優先）

Java の API を直接使う前に、Flix 標準ライブラリに同等の機能がないか必ず確認すること。
API リファレンス: https://api.flix.dev/

- **Random**: `Math.Random`, `Math.Shuffle` を使う。うまくいかない場合は RandomUtil を拡張
- **ファイル読み書き**: `Fs` モジュールを使う（Java の `Files` / `FileInputStream` 等は使わない）
  - `Fs.readFile`, `Fs.writeFile`, `Fs.readLines`, `Fs.writeLines`
  - `Fs.appendFile`, `Fs.appendLines`
  - `Fs.fileExists`, `Fs.fileSize`, `Fs.deleteFile`, `Fs.copyFile`, `Fs.moveFile`
- **ストリーム処理 / バッファ読み込み**: `BufReader` を使う
  - `BufReader.withDefaultCapacity(rc, reader)` で生成
  - `BufReader.readWhile`, `BufReader.peek`, `BufReader.read`, `BufReader.skip`
- **数値型変換**: 各型のモジュールにある変換関数を使う（Java の `Integer.parseInt` 等は使わない）
  - 安全な縮小変換: `Int32.tryToInt8`, `Int32.tryToInt16` → `Option` を返す
  - 拡大変換: `Int32.toInt64`, `Int32.toFloat64` → 精度を保つ
  - 文字列変換: `Int32.fromString` → `Option[Int32]`, `Int32.toString`
  - Float も同様: `Float64.fromString`, `Float32.toFloat64` など
  - `truncateToXxx` は精度が落ちるので意図的な場合のみ使用

---

## テストコードスタイル

- テストケースは、意図がわかるように必ずコメントを丁寧に書くこと
- 複雑なテストの場合のコメントは、アスキーアートを書くこと
- テストは、なるべく 1 assert で書くこと。複数の値は、List やタプルで比較すること
- テストで、パターンマッチなどの分岐は書かないこと。分岐がそもそも生じないような書き方を検討すること
  - もし分岐がどうしても生じる場合は、来てはいけない分岐で `bug!` を使用すること
- 責務を意識して、テストを書くこと。なるべく、対象となるモジュールのデータやイニシャライズ関数を使うこと
- テストはグルーピングと順序に気をつけること。describe は Flix にはないため、グルーピングできるものは大きめのコメントで区切ること

### @Test 関数の戻り値

- `@Test` 関数は必ず `Unit` を返す必要がある
- Assert モジュールを使って assertion をする

```flix
@Test
def testFoo(): Unit \ Assert =
    Assert.assertTrue(someCondition)
```

---

## Flix 0.71.0 固有の注意点（公式ドキュメントに載っていない）

### 予約語に注意

- `handler` は予約語（エフェクトハンドラで使用）
- import 文、変数名として使うとパースエラーになる
- 代わりの英単語を使うか、2単語以上で命名する

```flix
// NG: handler は予約語
case Some((handler, params)) => ...

// OK: 別の単語を使う
case Some((action, params)) => ...
```

### Channel API

- Java の atomic 変数を使いたくなったら見ること
- `Channel.buffered(size)` — Region を受け取らない、サイズのみ
- 戻り値は `(Sender[t], Receiver[t])` のタプル
- エフェクトは `Chan` と `NonDet`
- 参考: https://doc.flix.dev/concurrency.html?highlight=Channel#communicating-with-channels

### try-catch での Java 例外

- import してから使う（`##java.io.IOException` ではなく `IOException`）

### Java interop

- Java の import をするときは、モジュールのトップレベルに書く必要がある
- import を書かずに `java.Math.abs()` のようには呼び出せない
