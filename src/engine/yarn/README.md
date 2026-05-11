# `src/engine/yarn/` — Yarn Spinner bytecode VM

このディレクトリは **Yarn Spinner** [^1] というゲーム用の会話スクリプト言語を実行する VM。
ゲームエンジン本体 (= ホスト) から呼び出され、yarn ソースをコンパイルしたバイトコード
(`output.json`) を 1 命令ずつ進めて、行表示・選択肢・コマンド発火をホストに依頼する。
Yarn を全く知らない場合は §0 から読むのが早い。

設計上の特徴:

- **外部依存ゼロ** (Flix 標準ライブラリ以外には何にも依存しない)
- 外部との結合面は `Yarn.BuiltinExtension.Access` effect ただ 1 点
- VM の可変状態はすべて region `r` 内 (`Ref` / `MutDeque` / `MutMap`) に閉じる

全体の流れ:

```
yarn ソース (story.yarn)
    │  ysc compile           (公式コンパイラ。ビルド時)
    ▼
output.json (bytecode + 文字列テーブル + 初期変数)
    │  Yarn.Loader.parseProject   (実行時)
    ▼
YarnProject ── Yarn.VM.init ──► VM[r] ── step ──► StepResult
                                            ▲
                                            │ next / selectChoice / commandComplete
                                        (ホストが呼ぶ)
```

[^1]: 公式仕様・チュートリアル: https://docs.yarnspinner.dev/

---

## 0. Yarn とは何か / VM は何をするか

### Yarn が扱うもの: 分岐ストーリーと副作用発火の DSL

Yarn は「**分岐とイベント発火を持つ語り**」を書くための小さなスクリプト言語。

```yarn
title: drawer
---
<<if not inv_has("key")>>
    引き出しに かぎが あった。
    <<inv add key>>
<<else>>
    引き出しは からっぽだ。
<<endif>>
===
```

Yarn ノードを構成する 3 要素:

| 要素 | 例 | 役割 |
|---|---|---|
| **行 (Line)** | `引き出しに かぎが あった。` | そのまま画面に出すテキスト |
| **選択肢 (Choice)** | `-> はい` `-> いいえ` | ユーザに選ばせ、結果に応じてジャンプ先を決める |
| **コマンド (Command)** | `<<inv add key>>` `<<bgm play foo>>` | 外部 (ホスト) に副作用を依頼する任意文字列 |

状態は `$var` 変数で持ち、`<<if>>` で分岐。ノード間は `<<jump>>` `<<detour>>` で渡り歩く。
書き手 (シナリオライター) は **プログラムを触らずに分岐とテキストだけ書ける** のが Yarn の設計目標。プログラマは `<<command>>` 名と yarn 関数 (`inv_has` 等) を「装備品」として用意するだけで物語が動く。

### 実行時に扱うもの: バイトコード化された JSON

このモジュールが直接読むのは yarn ソースではなく、公式コンパイラ `ysc` が出力した `output.json` (バイトコード命令列 + 文字列テーブル + 初期変数値)。**スタック機械方式の 16 命令** が定義されており (§4)、`<<if>>` `<<jump>>` `-> 選択肢` などはコンパイル時にこの命令列に展開済み。

### VM の性質

| 性質 | 内容 |
|---|---|
| **スタック機械** | `Push*` / `Pop` / `CallFunc` で値を積み降ろし、命令はスタック top を入出力に使う。汎用レジスタなし |
| **ホスト駆動 (pull)** | VM は自走しない。**ホスト (ゲームエンジン) が `step` を必要なだけ呼ぶ**。1 step = 1 命令進む |
| **Pause-and-resume** | 「行表示」「選択待ち」「コマンド実行中」の 3 種で **必ず外に制御を返す**。ホストが完了通知 (`next` / `selectChoice` / `commandComplete`) を呼ぶまで再開しない |
| **副作用ゼロ** | VM 自身は文字を表示しない・音を鳴らさない。すべて「これをして」とホストに依頼するだけ |
| **拡張可能** | 同梱関数 (`Number.*` / `String.*` / `visited` 等) に加え、外部 effect 経由でゲーム固有関数 (`inv_has` 等) を増やせる |
| **シングルセッション** | 1 つの VM = 1 つの会話。並行実行は VM を 2 つ作る |

### できること

条件分岐 / 選択肢 / 変数 / 訪問カウント / ノード間ジャンプ / 副作用コマンド発火 / 関数呼び出し。

### **やらないこと (意図的)**

- **描画・音声・UI** はすべてホスト側の責任 (yarn は「何をすべきか」だけ伝える)
- **汎用関数定義 / ループ構文** は持たない (yarn は会話の DSL であって完全な汎用言語ではない)
- **並行実行** はサポートしない (必要なら VM を複数立てる)

このディレクトリのコードはすべて、上の 6 つの「できること」を実現するためのもの。

### 用語

このあとよく出てくる言葉。

| 用語 | 意味 |
|---|---|
| **ホスト (host)** | この VM を呼び出す側のプログラム。本プロジェクトでは `Game.flix` / Scene 群などゲームエンジン本体を指す。VM は自走しないので、ホストが `step` / `next` 等を能動的に呼んで進める |
| **ノード (node)** | yarn の 1 単位。`title: foo` 〜 `===` で囲まれた塊。1 つの会話シーンに対応 |
| **行 (line)** | 1 セリフ。`line:xxxxxx` のような ID で参照され、表示テキストは別の文字列テーブルに住む |
| **bytecode** | yarn ソースを `ysc` がコンパイルして得られる命令列。本モジュールが実行する対象 (テキストの yarn ソースは扱わない) |
| **命令 / instruction** | bytecode の 1 ステップ単位。16 種ある (§4) |
| **IP (instruction pointer)** | ノード内で「次に実行する命令」の番号 (0 始まり)。1 命令進むごとに +1 |
| **スタック (stack)** | 計算の作業領域。後入れ先出し。命令はここに値を積む / 取り出す / 覗く |
| **push / pop / peek** | スタック操作: 積む / 取り出す / 取らずに覗くだけ |
| **callStack** | スタックとは別の「ノード間ジャンプ用の戻り先列」。`<<detour>>` で積み、`Return` で取り出す |
| **`$var` (yarn 変数)** | 永続的な値の置き場。`<<set $hp = 10>>` で書き、`<<if $hp > 0>>` で読む |
| **builtin (組み込み関数)** | yarn の `<<if>>` などから呼べる関数 (`Number.Add` `String.EqualTo` 等) |
| **region** | Flix の仕組み。可変状態を 1 つのスコープ `r` に閉じ込め、スコープを抜けると参照不可になる (Rust のライフタイムに近い)。`VM[r]` の `r` がこの region |
| **effect / handler** | Flix の仕組み。関数シグネチャに「この副作用が必要」と宣言だけ書き、実体は呼び出し側が `with handler { ... }` で後付けで注入する。Java の interface + 依存性注入に近い (例: `Yarn.BuiltinExtension.Access` を被せて `inv_has` の実装を渡す) |

---

## 1. ファイル一覧

| ファイル | 役割 |
|---|---|
| `YarnTypes.flix` | 純粋データ型 (`Value` / `Instruction` / `Program` / `YarnNode` / `ChoiceEntry` / `CallFrame`) |
| `YarnLoader.flix` | `output.json` を `YarnProject` に変換。`parseProject(jsonText)` を提供 |
| `YarnVariableStorage.flix` | `$var` の region 内ストレージ。`init` / `get` / `set` / `incrementFloat` / `toMap` |
| `YarnVM.flix` | VM 本体。`init` / `step` / `next` / `selectChoice` / `commandComplete` |
| `YarnBuiltins.flix` | 組み込み関数 (`visited` / `Number.*` / `String.*` / `Bool.*` / `has_item`) の実装 |
| `YarnBuiltinExtension.flix` | 外部拡張フック (`Access` effect + `LookupResult`) |
| `YarnStringTable.flix` | `line:xxxx` → 表示テキスト解決 + `{0}` `{1}` 置換 |
| `YarnMarkup.flix` | Yarn のマークアップ → BBCode (`[color=#fff]...[/color]` 等) 変換 |
| `Yarn.flix` | 公開ファサード。`overrideInitialFloat` と `VariableAccess` effect の宣言 |

---

## 2. 外向き API

このモジュールが外部に提供する関数 / effect の一覧。

### ロード

| シンボル | 用途 |
|---|---|
| `Yarn.Loader.parseProject(jsonText): Result[YarnLoadError, YarnProject]` | `output.json` の文字列を `YarnProject` に変換 |
| `Yarn.overrideInitialFloat(name, value, project): YarnProject` | 起動時に `$hp` などの初期値を上書き (純粋) |

### VM 操作

| シンボル | 用途 |
|---|---|
| `Yarn.VM.init(rc, project, startNode): VM[r]` | `startNode` から実行開始する VM を作る。訪問カウンタ +1 |
| `Yarn.VM.step(vm): StepResult \ r + Yarn.BuiltinExtension.Access` | 1 命令進める。Waiting* 状態のときは同じ結果を返し続ける (二重実行しない) |
| `Yarn.VM.next(vm): Unit \ r` | `WaitingLine` を解除して次の step から再開 |
| `Yarn.VM.selectChoice(idx, vm): Unit \ r` | `WaitingChoice` を解除し、選択結果をスタックに push |
| `Yarn.VM.commandComplete(vm): Unit \ r` | `WaitingCommand` を解除して再開 |

### 変数アクセス (effect 越し)

| effect / シンボル | 用途 |
|---|---|
| `Yarn.VariableAccess` (eff) | `setBool` / `getBool` / `currentNode` / `variableSnapshot`。実体は handler を被せる外側で注入する想定 |

### 外部拡張点

| effect / シンボル | 用途 |
|---|---|
| `Yarn.BuiltinExtension.Access` (eff) | `lookup(name, args): LookupResult`。VM の `callFunc` で未対応名を解決するためのフック |
| `Yarn.BuiltinExtension.LookupResult` | `Found(Value)` / `NotFound` |
| `Yarn.BuiltinExtension.withNoExtension` | テスト用。常に `NotFound` |

### 文字列・マークアップ

| シンボル | 用途 |
|---|---|
| `Yarn.StringTable.resolve(lineId, substitutions, table): Result[String, String]` | `line:xxxx` をテキストに解決し `{0}` `{1}` を置換 |
| `Yarn.StringTable.applySubstitutions(raw, substitutions): String` | `{i}` の置換だけ単発実行 |
| `Yarn.Markup.toBBCode(yarnText): String` | Yarn 表記の `[color=...]...[/color]` を BBCode 形式に変換 |

---

## 3. データ型

```
YarnProject
  ├── program: Program
  │     ├── name: String
  │     ├── nodes: Map[String, YarnNode]
  │     │           └── 各ノードは name / headers / instructions: Vector[Instruction]
  │     ├── initialValues: Map[String, Value]   ← `<<declare>>` 由来の初期値
  │     └── languageVersion: Int32
  └── strings: Map[LineRef, String]              ← line:xxxx → 表示テキスト
```

**Value** は VM スタック・変数・引数・戻り値で共通に使う 3 値型 (`YarnTypes.flix:16`):

```
Value = BoolV(Bool) | FloatV(Float64) | StringV(String)
```

整数は存在せず、**整数値も `FloatV(n)` として保持**される (Yarn 仕様)。

**ChoiceEntry** = 蓄積された選択肢 1 件 (`AddChoice` で追加、`ShowChoices` で外へ流す):

```
ChoiceEntry { lineId, substitutions, destination, available }
```

**CallFrame** = `Detour` 時の戻り先情報 (`RunNode` は積まない):

```
CallFrame { nodeName, returnInstructionPointer }
```

---

## 4. 命令一覧 (16 種)

`YarnTypes.flix:43-84` 定義。各命令は `executeInstruction` (`YarnVM.flix:140`) で評価される。

> **JSON との対応**: `output.json` のキーは Yarn Spinner 仕様で固定 (`"addOption"` / `"showOptions"`)。Flix 側型名はわかりやすさを優先して `AddChoice` / `ShowChoices` にしてある。`YarnLoader` が境界で変換。

| 命令 | 引数 | スタック効果 | IP 効果 | 副作用 |
|---|---|---|---|---|
| `RunLine(lineRef, subCount)` | 行 ID, 置換個数 | top から `subCount` pop | +1 | `WaitingLine` 状態へ。`next()` まで停止 |
| `AddChoice(lineRef, dest, subCount, hasCond)` | 行 ID, ジャンプ先, 置換個数, 条件付きフラグ | `subCount` + (`hasCond` なら 1) pop | +1 | `pendingChoices` に push |
| `ShowChoices` | — | — | +1 | `WaitingChoice` 状態へ。`selectChoice(idx)` まで停止 |
| `JumpIfFalse(dest)` | ジャンプ先 IP | top を **peek** (pop しない) | top が `BoolV(false)` なら → dest、それ以外は +1 | — |
| `JumpTo(dest)` | ジャンプ先 IP | — | → dest | — |
| `PeekAndJump` | — | top を **peek** (Float) | → top の値 (Int に変換) | — |
| `Pop` | — | top 1 個 pop | +1 | — |
| `Return` | — | — | callStack ありなら復帰、空なら `DialogueComplete` | callStack pop |
| `Stop` | — | — | `DialogueComplete` | callStack 全消去 |
| `PushString(s)` | 文字列 | push `StringV(s)` | +1 | — |
| `PushFloat(f)` | 数値 | push `FloatV(f)` | +1 | — |
| `PushBool(b)` | 真偽値 | push `BoolV(b)` | +1 | — |
| `PushVariable(name)` | 変数名 | push 変数値 | +1 | 変数未設定なら `Failed` |
| `StoreVariable(name)` | 変数名 | top を **peek** | +1 | `variables[name] = top` |
| `CallFunc(name)` | 関数名 | 1 個 pop して引数個数取得、さらに N 個 pop して引数列、結果 1 個 push | +1 | 内部で `Yarn.Builtins.call` 経由 |
| `RunCommand(text, subCount)` | コマンド文字列, 置換個数 | top から `subCount` pop | +1 | `WaitingCommand` 状態へ。`commandComplete()` まで停止 |
| `RunNode(name)` | ノード名 | — | → 対象ノードの IP=0 | `currentNode` 置換 + 訪問カウンタ +1 (`<<jump>>` 由来) |
| `Detour(name)` | ノード名 | — | → 対象ノードの IP=0 | callStack に戻り先 push + 訪問カウンタ +1 (`<<detour>>` 由来) |

**スタック慣例**:
- top = MutDeque の **末尾** (`pushBack` / `popBack`)
- 引数や置換はスタックに **下から順** に積まれている前提で、pop して `List.reverse` した順で渡される (`YarnVM.flix:314-320`)

---

## 5. VM 内部状態

`VM[r]` は region `r` に閉じた可変フィールドの集まり (`YarnVM.flix:39-48`)。
**何を持っていて、どの命令が触るか** で整理する。

### 実行位置を表す 2 フィールド

| フィールド | 役割 | 値の例 |
|---|---|---|
| `currentNode` | 今いるノード名 (`None` = 対話完了) | `Some("Hotspot_door")` |
| `instructionPointer` (IP) | ノード内で次に実行する命令の番号 | `7` |

毎 step、`instructionPointer` を +1 して `currentNode` のノードからその位置の命令を取り出す → 実行する。`Return` / `Stop` で `currentNode` を `None` にすると対話終了。

### 計算用の 2 つのスタック

| フィールド | 役割 | 触る命令 |
|---|---|---|
| `stack` | 計算の作業領域 (値の積み下ろし) | `Push*` / `Pop` / `CallFunc` / `JumpIfFalse` (peek) / `StoreVariable` (peek) |
| `callStack` | `<<detour>>` で積まれた戻り先 | `Detour` (push) / `Return` (pop) |

### 永続値と一時バッファ

| フィールド | 役割 | 触る命令 |
|---|---|---|
| `variables` | yarn 変数 (`$inv_key` 等) を保持 | `PushVariable` (read) / `StoreVariable` (write) / `CallFunc` 内で参照 |
| `pendingChoices` | 表示前の選択肢を蓄積するバッファ | `AddChoice` (push) / `ShowChoices` (まとめて取り出す) |

### 一時停止マーカー

| フィールド | 役割 |
|---|---|
| `waitingState` | `None` = 走行中 / `Some(...)` = 行/選択肢/コマンドのいずれかで停止中 |

`RunLine` / `ShowChoices` / `RunCommand` を実行した瞬間に `Some` がセットされ、VM はそこで停止する。`step` を再度呼んでも、`Some` の間は **同じ `StepResult` を返し続ける** (二重実行しない、`YarnVM.flix:69-73`)。`next` / `selectChoice` / `commandComplete` が呼ばれると `None` に戻り、次の命令から再開する。

---

## 6. StepResult の 7 状態

`YarnVM.flix:28-36` 定義。`step` が返す型。

| 状態 | 到達する命令 | 解除条件 | 意味 |
|---|---|---|---|
| `Running` | Push* / Pop / Jump* / Store / CallFunc / Return (callStack 復帰) / RunNode / Detour / AddChoice | (即次の step で解除) | 続行可能。連続して `step` を呼んでよい |
| `WaitingLine(lineRef, subs)` | `RunLine` | `Yarn.VM.next(vm)` | 行表示中。view が表示完了するまで停止 |
| `WaitingChoice(entries)` | `ShowChoices` | `Yarn.VM.selectChoice(idx, vm)` | 選択肢提示中。ユーザ選択待ち |
| `WaitingCommand(text)` | `RunCommand` | `Yarn.VM.commandComplete(vm)` | コマンド実行中。外部が完了通知するまで停止 |
| `NodeComplete` | `Return` (callStack 復帰時のみ) | (即次の step で先へ) | Detour から復帰した直後 (1 step だけ通る) |
| `DialogueComplete` | `Return` (callStack 空時) / `Stop` | — | 対話終端。`currentNode = None` になり以後 `step` は同じ `DialogueComplete` を返す |
| `Failed(msg)` | 任意の異常 (IP 範囲外、未登録ノード、変数未定義 等) | — | 終端。msg にエラー詳細 |

### 状態遷移

```
            ┌─ RunLine ────────► WaitingLine    ── next ────────────┐
            │                                                       │
   Running ─┼─ ShowChoices ────► WaitingChoice  ── selectChoice ────┼─► Running (続行)
            │                                                       │
            ├─ RunCommand ─────► WaitingCommand ── commandComplete ─┘
            │
            ├─ Return (callStack 空) / Stop ─► DialogueComplete  (終端)
            ├─ Return (Detour 復帰) ─────────► NodeComplete  (1 step だけ通る経由)
            └─ 任意の異常 (IP 範囲外 等) ──────► Failed(msg)  (終端)
```

`Waiting*` 状態の間は `step` を再度呼んでも同じ `StepResult` を返し続ける (二重実行しない)。
ホスト側の解除関数 (`next` / `selectChoice` / `commandComplete`) を呼ぶと `Running` に戻り、
次の命令から再開する。

---

## 7. 具体例 1: drawer ノードを step ごとに追う

題材は `yarn/story.yarn` の以下:

```yarn
title: Hotspot_demo_room_drawer
---
<<if not inv_has("demo_key")>>
    引き出しの 中に かぎが あった。
    <<inv add demo_key>>
<<else>>
    引き出しは からっぽだ。
<<endif>>
===
```

これを Yarn Spinner コンパイラ (`ysc`) が `yarn/output.json` の以下 13 命令にコンパイルしている (実物コピー):

```
IP=0   pushString "demo_key"
IP=1   pushFloat 1
IP=2   callFunc inv_has
IP=3   pushFloat 1
IP=4   callFunc Bool.Not
IP=5   jumpIfFalse 9
IP=6   runLine "line:ee8e9af4"   // "引き出しの 中に かぎが あった。"
IP=7   runCommand "inv add demo_key"
IP=8   jumpTo 12
IP=9   pop
IP=10  runLine "line:78be9d83"   // "引き出しは からっぽだ。"
IP=11  jumpTo 12
IP=12  return
```

### 鍵を未所持で起動した場合の step 列

`inv_has("demo_key") = false` なので、then 分岐 (line:ee8e9af4) を通る:

```
step 1   PushString "demo_key"           → stack: ["demo_key"]                 IP: 1
step 2   PushFloat 1                     → stack: ["demo_key", 1]              IP: 2
step 3   CallFunc inv_has                → 引数個数 1 を pop し、引数 ["demo_key"] を作成
                                           Yarn.Builtins.call("inv_has", ["demo_key"])
                                           → ハードコード builtin に該当なし → Access.lookup
                                           → 外部実装で false を返す
                                         → stack: [false]                      IP: 3
step 4   PushFloat 1                     → stack: [false, 1]                   IP: 4
step 5   CallFunc Bool.Not               → 引数個数 1 pop, 引数 [false]
                                           Builtins.call("Bool.Not", [false]) → true
                                         → stack: [true]                       IP: 5
step 6   JumpIfFalse 9                   → top は true なので跳ばない          IP: 6
                                         (top は peek なので stack: [true] のまま)
step 7   RunLine "line:ee8e9af4"         → StepResult.WaitingLine 返却         IP: 7
         ━━ ホストが Yarn.VM.next(vm) を呼ぶ ━━

step 8   RunCommand "inv add demo_key"   → StepResult.WaitingCommand 返却      IP: 8
         ━━ ホストがコマンドを実行して commandComplete(vm) を呼ぶ ━━

step 9   JumpTo 12                       → IP を 12 に書き換え                 IP: 12
step 10  Return                          → callStack 空 → currentNode = None
                                         → StepResult.DialogueComplete
```

**`stack: [true]` に注目**: `JumpIfFalse` は **peek** (pop しない) なので、命令 5 終了時もスタックには true が残る。else 側 (IP=9) の `Pop` でこの値を捨てる。これが Yarn コンパイラの定型パターン。

### 鍵を所持中に起動した場合 (else 分岐)

`inv_has("demo_key") = true` だと:

```
step 3' CallFunc inv_has              → stack: [true]
step 4' PushFloat 1
step 5' CallFunc Bool.Not             → stack: [false]
step 6' JumpIfFalse 9                 → top は false → IP を 9 に    IP: 9
step 7' Pop                           → stack: []                    IP: 10
step 8' RunLine "line:78be9d83"       → "引き出しは からっぽだ。"
        ...
```

---

## 8. 具体例 2: 文字列等価判定 `inv_selected() == "demo_key"`

`Hotspot_demo_room_door` ノードの中の以下部分:

```yarn
<<elseif inv_selected() == "demo_key">>
```

これは bytecode で 5 命令にコンパイルされる (`output.json` 抜粋):

```
IP=9    pushFloat 0
IP=10   callFunc inv_selected
IP=11   pushString "demo_key"
IP=12   pushFloat 2
IP=13   callFunc String.EqualTo
IP=14   jumpIfFalse 19
```

スタック遷移:

```
                                           stack
init                                       []
IP=9   PushFloat 0                         [0]
IP=10  CallFunc inv_selected                                ← 引数個数 0 を pop
                                                              引数なし → Access.lookup("inv_selected", [])
                                                              → 外部実装で "demo_key" を返す
                                           ["demo_key"]
IP=11  PushString "demo_key"               ["demo_key", "demo_key"]
IP=12  PushFloat 2                         ["demo_key", "demo_key", 2]
IP=13  CallFunc String.EqualTo                              ← 引数個数 2 pop
                                                              引数 ["demo_key", "demo_key"]
                                                              Builtins.call → Ok(BoolV(true))
                                           [true]
IP=14  JumpIfFalse 19                                       ← top peek = true → 跳ばない
                                           [true]           ← peek なので true 残る
                                           (続いて IP=15 が Pop で掃除する)
```

引数個数を `pushFloat N` で渡してから `callFunc` を呼ぶのが Yarn の流儀 (0 引数でも `pushFloat 0` を必ず置く)。`JumpIfFalse` は peek なので、結果の `true` は次の `Pop` (IP=15) で掃除される。

---

## 9. Builtin 拡張点

`CallFunc(name)` の名前解決は 2 段。同梱 → なければ外部 → なければ `StepResult.Failed`。

```
CallFunc(name) → Yarn.Builtins.call(name, args)
                  ├ 同梱関数表に名前あり → Ok(value)
                  └ なし → Yarn.BuiltinExtension.Access.lookup(name, args)
                            ├ Found(value)  → Ok(value)
                            └ NotFound      → Err("unknown builtin: ...") → Failed
```

### 同梱 builtin (`YarnBuiltins.flix`)

| 関数 | 引数 | 戻り | 用途 |
|---|---|---|---|
| `visited(nodeName)` | String | Bool | `$Yarn.Internal.Visiting.<name>` > 0 か |
| `visited_count(nodeName)` | String | Float | 上記カウンタの値 |
| `Number.Add` / `Minus` / `EqualTo` / `NotEqualTo` / `GreaterThan` / `GreaterThanOrEqualTo` / `LessThan` / `LessThanOrEqualTo` | Float, Float | Float または Bool | 数値演算 |
| `String.EqualTo` / `NotEqualTo` / `Add` | String, String | Bool / String | 文字列比較・連結 |
| `Bool.EqualTo` / `NotEqualTo` / `And` / `Or` / `Not` | Bool, Bool / Bool | Bool | 論理演算 |
| `has_item(itemId)` | String | Bool | `$inv_<itemId>` 変数を Bool として読む |

### 外部拡張

`Yarn.BuiltinExtension.Access.lookup` を実装する handler を被せれば、ここに無い関数名 (例: `inv_has` `current_room`) を増やせる。yarn 側は **名前と引数の形だけ** 知っていて、実装はこの effect の handler 側に閉じる。**yarn モジュールは外部 effect を一切 import しない**。

---

## 10. Visiting カウンタ

`$Yarn.Internal.Visiting.<NodeName>` という変数を VM が自動メンテし、`visited` / `visited_count` builtin が読む。

| タイミング | 動作 |
|---|---|
| `VM.init(rc, project, "Start")` | `$Yarn.Internal.Visiting.Start` を +1 (`YarnVM.flix:54`) |
| `RunNode(targetName)` 命令 | `$Yarn.Internal.Visiting.<targetName>` を +1 (`YarnVM.flix:263`) |
| `Detour(targetName)` 命令 | `$Yarn.Internal.Visiting.<targetName>` を +1 (`YarnVM.flix:281`) |

実装は `Yarn.VariableStorage.incrementFloat` (Float64 型として読み込み、未設定なら `0.0` から +1)。

`variableSnapshot()` で取得すれば外部からも読める。スナップショットに含まれるので、シリアライズ・復元時もそのまま保たれる。

---

## 11. テスト時の使い方

VM はホスト駆動なので、テストでは region を開いて `step` を回すだけで raw 駆動できる:

```flix
region rc {
    let vm = Yarn.VM.init(rc, project, "Hotspot_demo_room_drawer");
    let result = run { Yarn.VM.step(vm) }
                   with Yarn.BuiltinExtension.withNoExtension;   // 拡張ゼロ
}
```

`inv_has` 等を固定値で返したいテストでは `Yarn.BuiltinExtension.Access` の handler を独自実装:

戻り値の effect 型 `ef - Yarn.BuiltinExtension.Access` は「呼び出し元が要求する effect セット `ef` から、この handler が処理する `Access` を差し引く」の意 (= ここで `Access` を消費したので、外側は `Access` を要求しなくてよくなる)。

```flix
def withTestBuiltins(thunk: Unit -> a \ ef): a \ (ef - Yarn.BuiltinExtension.Access) =
    run thunk() with handler Yarn.BuiltinExtension.Access {
        def lookup(name, _args, k) = k(match name {
            case "inv_has"      => Yarn.BuiltinExtension.LookupResult.Found(Yarn.Types.Value.BoolV(true))
            case "inv_selected" => Yarn.BuiltinExtension.LookupResult.Found(Yarn.Types.Value.StringV(""))
            case _              => Yarn.BuiltinExtension.LookupResult.NotFound
        })
    }
```

実例は `test/engine/yarn/*.flix`。

---

## 12. yarn ソース → bytecode の対応 (補足)

`<<if cond>>...<<elseif cond2>>...<<else>>...<<endif>>` の典型コンパイルパターン:

```
yarn:                              bytecode (概略):
  <<if cond1>>                       ... cond1 を評価する命令列 ...
                                     jumpIfFalse <to_elseif_or_else>
    body1                            ... body1 命令列 ...
                                     jumpTo <end>
  <<elseif cond2>>                 <to_elseif_or_else>:
                                     pop                          ← peek 残骸を捨てる
                                     ... cond2 を評価 ...
                                     jumpIfFalse <to_else>
    body2                            ... body2 ...
                                     jumpTo <end>
  <<else>>                         <to_else>:
                                     pop
    body3                            ... body3 ...
                                     jumpTo <end>
  <<endif>>                        <end>:
                                     return
```

`pop` が必要な理由: `jumpIfFalse` は **peek** で値を残すため、ジャンプ先で必ず明示的に捨てる。

`<<set $x = expr>>` は:

```
... expr の評価命令 ...
storeVariable $x        ← peek なので stack に値が残る
pop                     ← 残った値を捨てる
```

`<<jump SomeNode>>` は単に `runNode SomeNode`、`<<detour SomeNode>>` は `detour SomeNode` (戻り先を callStack に積む)。

実際のコンパイル結果は `yarn/.bin/ysc compile yarn/story.yarn --stdout` で確認できる。
