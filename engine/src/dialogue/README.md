# `src/engine/dialogue/` — 対話ドライバ層

このディレクトリは **Yarn VM (バイトコード実行) と Scene (描画) の間に立つ対話ドライバ層**。
ゲームロジックは `Dialogue.Session.start("Hotspot_demo_room_drawer")` のように
effect を 1 つ呼ぶだけで対話を開始でき、Scene 側は 1 フレームに 1 回 `Inbox.takeAll`
で view イベント列を取り出して `Dialogue.applyFrame` で描画状態に畳み込む。

このモジュールを **読む前に / 並行して** Yarn VM の挙動 (`step` / `Waiting*` /
`commandComplete` の関係) を知っておくと理解が早い。詳細は
[`src/engine/yarn/README.md`](../yarn/README.md) を参照。

設計上の特徴:

- **Yarn を 2 つの effect で隠蔽する** — `Session` (ゲーム側 → 対話) / `DialogueView` (対話 → 表示)。`<<command>>` の同期/非同期は `withRunner` の boolean 引数で静的に決まる
- **Scene は 1 フレームに 1 回 pull** — `DialogueView` 受信は queue に積むだけ。Scene の `process` で `Dialogue.processFrame` 1 関数で纏めて消化
- **描画ロジックは `UIState` の純粋遷移に閉じる** — `applyEvent` / `tick` / `formatBody` は副作用なし。差し替え可能
- **JRPG / VN の表現差は `DialogueProfile` の値で吸収** — `applyEvent` 等の純粋関数はジャンルを知らない
- **facade `withDialog` 1 行で 2 段 handler を被せる** — Runner / SceneView をまとめて適用。テストは `Dialogue.Test.withTestDialog` で対称な 1 行 facade
- **確定キー入力は `confirmAction(state)` で 4 状態に分類** — Scene 側は `match` 1 個で決定。低水準述語 (`isPanelFullyRevealed` 等) を覚えなくて済む

---

## 0. 何をする層か / 何をしないか

### 何をするか

```
ゲームロジック ──► Session.start("Foo")
                       │
                       ▼
                   Runner (= Yarn VM 駆動)
                       │  WaitingLine / WaitingChoice / WaitingCommand
                       ▼
                   DialogueView.presentLine(...) など
                       │
                       ▼
                  SceneView handler (queue に push)
                       │  (1 フレーム後)
                       ▼
                  Scene.process: Inbox.takeAll → applyFrame → UIState 更新
                       │
                       ▼
                   formatBody → Scene 描画
```

役割:

- **VM のラッパ**: `Yarn.VM.step` の Waiting/Complete を `DialogueView` 操作に翻訳
- **入力ルータ**: ゲーム側 (`Session.submitNext` / `submitSelect` 等) を VM 入力 (`Yarn.VM.next` / `selectChoice` 等) に翻訳
- **画面用論理状態の維持**: `UIState` で typewriter 進捗・パネル切替・選択カーソル・点滅を持つ
- **ジャンル吸収**: JRPG (蓄積パネル + 自動送り) / VN (1 行ごと確定) を `DialogueProfile` で切替

### やらないこと (意図的)

- **描画自体** — 描画は Scene 側 (本プロジェクトでは `DialogueScene.flix`)。本層は `formatBody` で文字列を組み立てるところまで
- **Yarn 命令の解釈** — それは `src/engine/yarn/`。本層は `step` を呼んで結果を翻訳するだけ
- **入力デバイスの抽象化** — キー入力の解釈は Scene 側 (`process` で `Session.submit*` を呼ぶ)
- **`<<command>>` の実処理** — `runCommand` 文字列は Inbox に流すだけ。実処理は `Game.CommandRouter.processCommands` (本プロジェクト固有)

### 用語

| 用語 | 意味 |
|---|---|
| **ホスト (host)** | この層を使う側のプログラム。本プロジェクトでは `Game.flix` (`gameLoop`) と `DialogueScene.flix` (`process` / `handleInput`) |
| **VM** | `Yarn.VM.VM[r]`。本層が中で 1 つだけ持って駆動する。詳細は [`yarn/README.md` §5](../yarn/README.md#5-vm-内部状態) |
| **Runner** | `DialogueRunner.flix` の `withRunner` handler。`Session` effect の実装。VM を持って `Waiting*` まで step する |
| **SceneView** | `SceneView.flix` の `withSceneView` handler。`DialogueView` の本番実装 (queue に push) |
| **Inbox** | SceneView が貯めた `ViewEvent` を 1 フレーム単位で取り出す effect。Scene の `process` で drain する |
| **CommandInbox** | `runCommand` 由来のコマンド文字列だけを取り出す effect。view 系とは別キュー (混ぜると別 consumer が読めない) |
| **panel** | 画面に同時表示する 1 ブロックの行群。JRPG なら 3 行、VN なら 1 行 |
| **transition** | パネル切替のスクロールアウト演出。完了するまで次の行を出さないゲートでもある |
| **typewriter** | 1 文字ずつ出すアニメーション。`revealProgress` (Float64 の文字数累積) で進める |
| **profile** | `DialogueProfile`。ジャンルごとのリズム (パネル行数・自動送り可否・速度・点滅周期) |
| **継続行 (continuation line)** | 名前 prefix なしの Line。直前の発話に追記する扱い |
| **`pendingEvent`** | transition 中に届いた次イベントを保留しておく場所。完了フレームで `applyEventInner` に流す |
| **effect / handler** | Flix の仕組み。詳細は [`yarn/README.md` の用語集](../yarn/README.md#用語) を参照 |
| **region** | Flix の仕組み。本層では Runner / SceneView の MutDeque / Ref を閉じ込めるのに使う。詳細は同上 |

---

## 1. クイックスタート: Scene に対話を組み込む最小手順

「対話を表示する Scene を新しく書きたい」だけなら、まず以下の 4 ステップだけ覚えれば
動かせる。詳細は §3 以降をリファレンスとして引きながら埋めていけばよい。

### Step 1. ホスト (`Game.flix` 等) で `withDialog` を被せる

```flix
run gameLoop()
    with Dialogue.withDialog(yarnProject)
```

これだけで `Session` / `DialogueView` / `Inbox` / `CommandInbox` が body 内で全部使える
状態になる。3 段 handler の中身は §13 を参照。

### Step 2. 対話を開始する

ゲームロジック側 (Hotspot 押下時など) で 1 行:

```flix
Dialogue.Session.start("Hotspot_demo_room_drawer")
```

### Step 3. Scene の `process` で view イベントを畳み込む

```flix
// Inbox.takeAll → applyFrame → 必要なら自動 submitNext を 1 関数で
let (state', addedLines) = Dialogue.processFrame(delta, state);
// state' を保持して、formatBody(state') を描画に渡す
// addedLines > 0 は新行が出たフレーム（トーク SE のトリガなど演出用）
```

### Step 4. Scene の `handleInput` で入力を Session に流す

```flix
// 確定キー（▼ 確定 / typewriter 一気出し / 選択肢確定）は 1 個の match で決まる
match Dialogue.confirmAction(state) {
    case Dialogue.ConfirmAction.Ignore           => /* 無視 */
    case Dialogue.ConfirmAction.SelectChoice(i)  => Dialogue.Session.submitSelect(i)
    case Dialogue.ConfirmAction.ForceFullReveal  => /* mapState forceFullReveal */
    case Dialogue.ConfirmAction.AdvanceLine      => Dialogue.Session.submitNext()
}

// 選択肢中: カーソル移動は純粋関数で
let state' = Dialogue.moveCursor(1, state);
```

これで「行表示 → 選択肢 → コマンド発火 → 完了」まで一通り動く。

### Scene 側の責務マップ

「Scene のどのメソッドで何を呼べばよいか」を 1 表で:

| Scene のメソッド | 呼ぶ API | 用途 |
|---|---|---|
| 初期化 | `Dialogue.emptyState(Dialogue.jrpgProfile())` | `UIState` の初期値 |
| `process(delta)` | `Dialogue.processFrame(delta, state)` | `Inbox.takeAll` → `applyFrame` → 必要なら `submitNext` を一括。戻り値は `(newState, addedLines)` |
| `handleInput` (決定) | `match Dialogue.confirmAction(state)` | 確定キー時の遷移を 4 ケースで分類（Ignore / SelectChoice / ForceFullReveal / AdvanceLine） |
| `handleInput` (上下) | `moveCursor(±1, state)` (純粋) | 選択肢カーソル移動 |
| `render` | `formatBody(state)` | パネル本文 (typewriter 反映済み) |
| `render` | `transitionView(state)` | スクロール演出があれば取り出す |
| `render` | `shouldShowNextIndicator(state)` + `isBlinkOn(state)` | "▼" の表示判定と点滅 |

実コード例は [`src/scenes/DialogueScene.flix`](../../scenes/DialogueScene.flix) を参照。

### この先の読み進め方

- フレーム単位で動きを追いたい → §9 (具体例)
- なぜ transition でゲートされるか → §8 (UIState ライフサイクル)
- 全 API リファレンス → §3 (外向き API)
- `withDialog` の中身 → §13 (本番統合)
- Yarn VM の挙動 (`Waiting*` の意味) → [`yarn/README.md`](../yarn/README.md)

---

## 2. ファイル一覧

| ファイル | 役割 |
|---|---|
| `Dialogue.flix` | effect 2 種 (`Session` / `DialogueView`) + view 整形済み型 + `UIState` の純粋遷移 + `confirmAction` / `processFrame` ヘルパ + `DialogueProfile` + facade `withDialog` |
| `DialogueRunner.flix` | `Session` effect の実装 (`withRunner`)。VM を保持し `runUntilWaiting` で次の `Waiting*` まで step を回す。`syncCommands` で `<<command>>` の同期/非同期を切替 |
| `SceneView.flix` | `DialogueView` の本番 handler (`withSceneView`) と `Inbox` / `CommandInbox` effect。view 系と command 系を別キューに分離 |
| `StubView.flix` | テスト用 `DialogueView` (`withRecordingView`)。受け取った操作を `ViewEvent` ログに蓄積して返す。テスト facade `Dialogue.Test.withTestDialog` も同居 |
| `CommandParser.flix` | `<<wait 0.5>>` 等の引数列を空白分解する純粋関数 (`parse`) |

---

## 3. 外向き API

### facade (これだけ覚えれば 9 割回る)

| シンボル | 用途 |
|---|---|
| `Dialogue.withDialog(yarnProject, body): a \ ...` | Runner + SceneView を 1 行で被せる本番用 facade。`body` の中で `Session.start` 等が使える。`<<command>>` は非同期扱い |
| `Dialogue.Test.withTestDialog(rc, project, body): (a, List[ViewEvent]) \ ...` | テスト用 facade。Stub view + sync runner + no-extension を 1 行で被せ、view イベントログを返す |

### effects

| effect | 提供メソッド | 提供方向 | 実装場所 |
|---|---|---|---|
| `Dialogue.Session` | `start` / `stop` / `isActive` / `submitNext` / `submitSelect(idx)` / `submitCommandDone` / `restart(node, vars)` | ゲーム側 → 対話 | `withRunner` (本番) |
| `Dialogue.DialogueView` | `presentLine` / `presentChoices` / `dismissLine` / `runCommand` / `dialogueComplete` | 対話 → 表示 | `withSceneView` (本番) / `withRecordingView` (テスト) |
| `Dialogue.SceneView.Inbox` | `takeAll(): List[ViewEvent]` | Scene の `process` で消化 | `withSceneView` |
| `Dialogue.SceneView.CommandInbox` | `takeAllCommands(): List[CommandText]` | コマンドルータが消化 | `withSceneView` |
| `Yarn.VariableAccess` | `setBool` / `getBool` / `currentNode` / `variableSnapshot` | ゲーム側 → 変数 | `withRunner` が VM 経由で実装 |

`<<command>>` の同期/非同期切替は `Dialogue.Runner.withRunner` の `syncCommands: Bool`
引数で静的に決まる。本番 (`withDialog`) は `false`（外部完了通知を待つ）、
テスト (`withTestDialog`) は `true`（即完了で次の命令へ）。

### 純粋関数 (副作用なし。Scene 側で使う)

| シンボル | 用途 |
|---|---|
| `Dialogue.emptyState(profile): UIState` | 初期状態 (未開始 = 非表示) |
| `Dialogue.applyEvent(event, state): UIState` | 1 件の `ViewEvent` を反映 |
| `Dialogue.applyFrame(delta, events, state): UIState` | 1 フレーム分のイベント列 + tick の標準パイプライン |
| `Dialogue.tick(delta, state): UIState` | typewriter / transition / 経過時間を `delta` だけ進める |
| `Dialogue.moveCursor(delta, state): UIState` | 選択肢カーソルを動かす (wrap-around) |
| `Dialogue.formatBody(state): String` | パネル本文を文字列で組み立てる (typewriter 反映済み) |
| `Dialogue.confirmAction(state): ConfirmAction` | 確定キー時の遷移を 4 ケースに分類（Ignore / SelectChoice / ForceFullReveal / AdvanceLine） |
| `Dialogue.isPanelFullyRevealed(state): Bool` | typewriter 完了したか |
| `Dialogue.forceFullReveal(state): UIState` | typewriter を即座に完了 |
| `Dialogue.shouldShowNextIndicator(state): Bool` | "▼" を出すべきか |
| `Dialogue.shouldAutoNext(state): Bool` | 自動で次行に進むべきか (JRPG) |
| `Dialogue.isBlinkOn(state): Bool` | "▼" 点滅の ON/OFF |
| `Dialogue.transitionView(state): Option[Transition]` | スクロール演出の進捗 |
| `Dialogue.extractSpeaker(text): Option[SpeakerName]` | `"おう: ..."` から `"おう"` を取り出す |
| `Dialogue.jrpgProfile() / visualNovelProfile()` | 既製プロファイル |

### 副作用ヘルパ (Scene の `process` で使う)

| シンボル | 用途 |
|---|---|
| `Dialogue.processFrame(delta, state): (UIState, Int32)` | `Inbox.takeAll → applyFrame → 必要なら submitNext` を 1 関数で。戻り値の `Int32` は新しく追加された行数（SE トリガに使える） |

### コマンドパーサ

| シンボル | 用途 |
|---|---|
| `Dialogue.CommandParser.parse(line): (String, List[String])` | `"bgm play title loop"` → `("bgm", ["play","title","loop"])` |

---

## 4. データ型

```
UIState
  ├── speaker: Option[String]          現パネルの話者
  ├── lines: List[String]              蓄積中の発話 (古→新)
  ├── choices: List[String]            選択肢中なら non-empty
  ├── cursor: Int32                    choices 内の選択 index
  ├── visible: Bool                    完了後 / 未開始は false
  ├── revealProgress: Float64          panel 全体の typewriter 進捗 (文字数累積)
  ├── elapsed: Duration                表示中の経過時間 (点滅用)
  ├── lastLineHadName: Bool            最新 line に名前 prefix が付いていたか
  ├── transition: Option[Transition]   直前パネルの演出 + 完了時に流す保留イベント
  └── profile: DialogueProfile         ジャンル設定
```

**ViewEvent** = 1 フレームで queue に積む単位 (`Dialogue.flix:57`):

```
ViewEvent = Line(LineText, Option[SpeakerName])
          | Choices(List[ChoiceLabel])
          | Dismiss
          | Command(CommandText)
          | Complete
```

**PresentedLine / PresentedChoice** = `DialogueView` で view に渡す整形済み型:

```
PresentedLine   { lineId, text, speaker }
PresentedChoice { index, text, available }
```

**Transition** = 旧パネルの演出 + 完了時に流す保留イベントのペア:

```
Transition {
    oldLines:     List[String],   // 演出開始時のパネルに表示されていた行
    progress:     Float64,        // 0.0 → 1.0
    pendingEvent: ViewEvent       // 演出完了時に applyEventInner で実反映するイベント
}
```

`pendingEvent` を `Transition` の中に持つことで、「演出が終わるまで次の文章は出さない」
というゲートが型レベルで担保される（`transition = None` なら保留中イベントも存在しない）。

**ConfirmAction** = 確定キー押下時に取るべき動作の分類:

```
ConfirmAction = Ignore                   // 非表示・transition 中・auto-next 待ち
              | ForceFullReveal          // typewriter 進行中 → 残り一気出し
              | SelectChoice(Int32)      // 選択肢提示中 → submitSelect
              | AdvanceLine              // ▼ 表示中 → submitNext
```

**DialogueProfile** = ジャンル設定 (`Dialogue.flix:92`):

```
DialogueProfile {
    maxLinesPerPanel,        // 1 パネルに溜める最大行数 (1 で VN 風)
    breakOnSpeakerLine,      // 名前 prefix で新パネル化するか
    autoNextContinuation,    // 継続行の typewriter 完了で自動送りするか
    transitionDuration,      // パネル切替演出の長さ
    revealCharsPerSecond,    // typewriter 速度 (文字 / 秒)
    blinkPeriod,             // "▼" 点滅 1 サイクル長
    nextIndicatorGlyph       // "▼" の表示記号
}
```

既製: `jrpgProfile()` (3 行 / 名前で待機 / 自動送り / 40 文字毎秒) / `visualNovelProfile()` (1 行 / 毎行確定 / 50 文字毎秒)。

---

## 5. データフロー全体図

```
┌─ ゲームロジック ────────────────────────────────────────────────┐
│ Dialogue.Session.start("Start")                                 │
└─────────────┬───────────────────────────────────────────────────┘
              │
              ▼
┌─ Runner (DialogueRunner.flix) ──────────────────────────────────┐
│ Yarn.VM.init(...) → Ref に保持                                  │
│ runUntilWaiting:                                                │
│   loop: Yarn.VM.step(vm) →                                      │
│     Running       → 続ける                                      │
│     WaitingLine   → DialogueView.presentLine(...) ─┐            │
│     WaitingChoice → DialogueView.presentChoices(...)│           │
│     WaitingCommand→ DialogueView.runCommand(text)  │            │
│                     syncCommands?                  │            │
│                       true  → VM.commandComplete  │            │
│                       false → 外部完了通知を待つ   │            │
│     DialogueComplete → DialogueView.dialogueComplete()          │
└────────────────────────────────────────────────────┼────────────┘
                                                     │
                                                     ▼
┌─ SceneView handler (SceneView.flix) ────────────────────────────┐
│ presentLine(...)        → viewQueue.pushBack(Line(...))         │
│ presentChoices(...)     → viewQueue.pushBack(Choices(...))      │
│ runCommand(text)        → commandQueue.pushBack(text)           │
│ dialogueComplete()      → viewQueue.pushBack(Complete)          │
└─────────────┬──────────────────────────┬────────────────────────┘
              │ (次フレーム)              │ (次フレーム)
              ▼                          ▼
┌─ Scene.process ──────────────┐  ┌─ Game.CommandRouter ─────────┐
│ events = Inbox.takeAll()      │  │ texts = CommandInbox        │
│ state' = applyFrame(          │  │            .takeAllCommands()│
│            delta, events, st) │  │ for each: parse → dispatch  │
│ formatBody(state') を描画     │  │            → submitCommandDone│
│ shouldAutoNext → submitNext   │  └─────────────────────────────┘
└──────────────────────────────┘
```

`viewQueue` と `commandQueue` を分けてあるのは、view 系を `Inbox.takeAll` で drain
する Scene 側ライフサイクルと、コマンド系を別フレーム/別ルータで処理するライフサイクルを
独立させるため。同じキューに混ぜると、片方を drain するともう片方が読めなくなる。

---

## 6. Session の各操作と VM 入力の対応

`DialogueRunner` は `Session.submit*` を Yarn VM の入力解除関数に 1:1 で翻訳する。
解除のあと **次の `Waiting*` / 完了に到達するまで `runUntilWaiting` で step** する
(暴走防止に `maxStepsPerSubmit() = 1000` で打ち切り)。

| `Session` | 中で呼ぶ Yarn VM 操作 | 解除する VM 状態 |
|---|---|---|
| `start(node)` | `Yarn.VM.init(rc, project, node, sharedStorage)` で新 VM を作り Ref に格納 → `runUntilWaiting`。**変数は前 session のものをそのまま継続** | (新 VM 起動) |
| `restart(node, vars)` | `VariableStorage.reset(sharedStorage, initialValues)` → `vars` を上書き → `init` → `runUntilWaiting` | (新 VM 起動 + 変数フル復元) |
| `submitNext()` | `Yarn.VM.next(vm)` → `runUntilWaiting` | `WaitingLine` |
| `submitSelect(idx)` | `Yarn.VM.selectChoice(idx, vm)` → `runUntilWaiting` | `WaitingChoice` |
| `submitCommandDone()` | `Yarn.VM.commandComplete(vm)` → `runUntilWaiting` | `WaitingCommand` (async 時) |
| `stop()` | Ref を `None` に + `DialogueView.dialogueComplete()` | (強制中断) |
| `isActive()` | Ref が Some かつ `vm#currentNode` が Some か | — |

**変数ストレージは Runner 1 個** — `withRunner` 起動時に `Yarn.VariableStorage.init`
で 1 個作って全 session で共有する。`Yarn.VM.init` は storage を **借りる** だけ
で自分では作らない。これにより、Hotspot をクリックする度に `Session.start` で
新 VM を立てても `$flag_*` や `$Yarn.Internal.Visiting.*` は保持される。
「タイトル → 最初から」のように完全リセットしたい場合は `restart(startNode, Map.empty())`
を呼ぶ（initialValues に戻る）。

VM 側の `Waiting*` / `next` / `selectChoice` / `commandComplete` の挙動は
[`yarn/README.md` §6](../yarn/README.md#6-stepresult-の-7-状態) と
[§5](../yarn/README.md#5-vm-内部状態) を参照。

---

## 7. 同期コマンド vs 非同期コマンド

`<<wait 0.5>>` のような Yarn コマンドは VM が `WaitingCommand(text)` で停止する。
ここから先の進め方は **`Dialogue.Runner.withRunner` の `syncCommands` 引数** で
静的に決まる（boolean を 1 つ渡すだけで、effect ベースのディスパッチは不要）。

```
WaitingCommand("wait 0.5")
        │
        ├─► DialogueView.runCommand("wait 0.5")    (view に通知。queue に push)
        │
        └─► syncCommands?
                ├ true  (同期完了) → Yarn.VM.commandComplete(vm) を即呼ぶ
                │                    → runUntilWaiting で続行
                └ false (非同期)   → 何もせず待つ
                                     → 外部が Session.submitCommandDone() を
                                       呼んだら再開
```

| facade | `syncCommands` | 用途 |
|---|---|---|
| `Dialogue.withDialog` | `false` | 本番。実コマンドは `CommandInbox` 経由で `Game.CommandRouter` が処理し、完了時に `Session.submitCommandDone()` を呼ぶ |
| `Dialogue.Test.withTestDialog` | `true` | テスト。`gameLoop` を回さず Runner を直接駆動するときに、コマンドで永久停止しないようにする |

実コマンド名 → 動作対応表は `Game.CommandRouter` 側にある (本プロジェクト固有)。
Dialogue 層は文字列を Inbox に流すだけ。

---

## 8. UIState のライフサイクル

`applyEvent` と `tick` の組合せで状態が遷移する。新パネル化が絡むと **transition で
ゲートする** 動きに注意。

```
emptyState                          (visible = false)
   │ Line(text, speaker)
   ▼
Showing line                        (visible = true, lines = [text], typewriter 進行中)
   │ Line(continuation, None) かつ panel 余裕あり
   ▼
Showing line (panel 蓄積中)         (lines = [...,...], typewriter 連続継続)
   │ Line(named) または lines 上限
   ▼
beginPanelTransition                (transition = Some({
                                       oldLines = 旧 lines,
                                       progress = 0.0,
                                       pendingEvent = event   ← 完了時に流す
                                     }),
                                     新 lines = [], typewriter リセット)
   │ tickTransition で progress → 1.0
   ▼
applyEventInner(transition#pendingEvent)
                                    (transition = None,
                                     新 panel に Line 反映)

   ※ Choices / Complete も同様に新パネル化扱い (transition でゲート)
```

**「panel 全体を 1 つの連続列として typewriter する」** のがポイント:

- `revealProgress` は **Float64 の文字数累積** (line 単位ではない)
- 行が append されると `cap = totalCharCount(state)` が伸びるので、typewriter は
  そのまま次行へ流れていく (`Dialogue.flix:324` の `tickReveal`)
- `formatBody` は cap を全行に **連続して** 分配して表示
  (`Dialogue.flix:392` の `step` 関数)

**新パネル化 (`eventStartsNewPanel`)** の判定 (`Dialogue.flix:196`):

| 条件 | 新パネル化? |
|---|---|
| `lines` が空 | **しない** (最初の行は即時表示) |
| `Line` で `breakOnSpeakerLine = true` かつ `speaker = Some` | **する** |
| `Line` で `lines.length >= maxLinesPerPanel` | **する** |
| `Choices` | **する** |
| `Complete` | **する** |
| `Dismiss` / `Command` | **しない** (状態を変えない) |

新パネル化されると:

1. `beginPanelTransition` で **旧 lines + イベント本体** を `Transition` に退避（`oldLines` /
   `pendingEvent`）し、新 lines は空
2. `tickTransition` が毎フレーム `progress` を進め、1.0 に達した瞬間に
   `applyEventInner(transition#pendingEvent, ...)` で実反映
3. 描画側は `transitionView(state)` で `oldLines` と `progress` を取り出してフェードアウト

これにより **「演出が終わるまで次の文章は出さない」** が型レベルで保証される
（`transition` が `None` のときに保留中イベントが残ることはあり得ない）。

---

## 9. 具体例: start → 行 → 行 → 選択肢 → 完了

`yarn/story.yarn` の Start ノードを `DialogueScene` (`jrpgProfile`) で表示する想定で、
1 フレーム単位の流れを追う。speaker は `"おう"` で固定。

### t = 0: ゲーム開始時に 1 度だけ走る

```flix
Dialogue.Session.start("Start")
```

Runner 側の動き:

```
init(rc, project, "Start") → vmRef ← Some(vm)
runUntilWaiting:
  step()  → Running...      (PushString / CallFunc / JumpIfFalse など)
  step()  → WaitingLine("line:abc", []) を返す
            DialogueView.presentLine({lineId="line:abc",
                                       text="おう: ゆうしゃよ、よくぞ もどった！",
                                       speaker=Some("おう")})
            → viewQueue.pushBack(Line("おう: ゆうしゃよ…", Some("おう")))
```

この時点で `viewQueue` は `[Line(...)]`、Scene の `UIState` はまだ `emptyState`。

### t = フレーム 1: Scene.process が 1 回目の drain

```flix
let events = Dialogue.SceneView.Inbox.takeAll();    // [Line("おう: ゆうしゃよ…", Some("おう"))]
let state' = Dialogue.applyFrame(delta, events, state);
```

あるいは `Dialogue.processFrame(delta, state)` 1 関数でも良い（`Inbox.takeAll` から
`shouldAutoNext` 判定までを一括）。

`applyEvent` の中:

- `eventStartsNewPanel`: `lines` 空なので **false** → `applyEventInner` で即反映
- `acceptLineInner`: `lines` 空なので新規行 → `lines = ["おう: ゆうしゃよ…"]`,
  `revealProgress = 0.0`, `lastLineHadName = true`, `visible = true`
- `tick(delta)`: typewriter が `delta * 40` 文字進む

Scene は `formatBody(state')` で部分表示文字列を取り出して `RichTextLabel` に流す。

### t = しばらく後: typewriter 完了

`isPanelFullyRevealed(state)` が true、かつ `lastLineHadName = true` なので
`shouldShowNextIndicator(state)` が true。"▼" を点滅で出す
(`isBlinkOn(state)` で ON/OFF)。

`shouldAutoNext` は `breakOnSpeakerLine = true && lastLineHadName = true` のため
**false** → 自動進行はしない。ユーザのキー入力待ち。

### t = ユーザがキーを押した

`DialogueScene.handleInput` から:

```flix
Dialogue.Session.submitNext()
```

Runner:

```
Yarn.VM.next(vm)             // WaitingLine 解除
runUntilWaiting:
  step()  → Running...
  step()  → WaitingLine("line:def", []) を返す  // "おう: まおうを たおすのじゃ。"
            → viewQueue.pushBack(Line("おう: まおうを…", Some("おう")))
```

### t = フレーム N: 2 行目を反映

`viewQueue = [Line("おう: まおうを…", Some("おう"))]` を `applyFrame` で食わせる:

- `eventStartsNewPanel`: `lines = ["おう: ゆうしゃよ…"]` あり、Line に speaker
  あり、`breakOnSpeakerLine = true` → **true**
- → `beginPanelTransition`:
  - `transition = Some({
        oldLines = ["おう: ゆうしゃよ…"],
        progress = 0.0,
        pendingEvent = Line("おう: まおうを…", Some("おう"))
    })`
  - `lines = Nil`, `revealProgress = 0.0`

その後数フレームかけて `tickTransition` が `progress` を `transitionDuration = 0.6s`
かけて 1.0 まで進める。`progress >= 1.0` のフレームで `applyEventInner` が走り、
新 panel に `lines = ["おう: まおうを…"]` がセットされる。

### t = もう 1 回 submitNext → 選択肢

```flix
Dialogue.Session.submitNext()
```

Runner で Choices 系命令まで進み、`WaitingChoice([entry0, entry1])` で停止 →
`presentChoices([{index=0, text="はい", ...}, {index=1, text="いいえ", ...}])` →
`viewQueue.pushBack(Choices(["はい", "いいえ"]))`。

`applyFrame` で `eventStartsNewPanel = true` (`Choices` は常に true) → transition →
新 panel に `choices = ["はい", "いいえ"]`, `cursor = 0`。

`formatBody` は choices モードに入り `"> はい\n  いいえ"` を返す。

### t = カーソル移動 + 確定

```flix
Dialogue.moveCursor(1, state)   // "  はい\n> いいえ"
Dialogue.Session.submitSelect(0)
```

Runner で `Yarn.VM.selectChoice(0, vm)` → step → 「はい」分岐の Line → ...

### t = `<<wait 0.5>>` コマンド到達

Runner:

```
step() → WaitingCommand("wait 0.5")
DialogueView.runCommand("wait 0.5")  → commandQueue.pushBack("wait 0.5")
syncCommands = false (withDialog 経路) → 何もせず待つ
```

別フレームで `Game.CommandRouter` が `commandQueue` を `takeAllCommands()` で drain
し、`CommandParser.parse("wait 0.5")` → `("wait", ["0.5"])` → 該当処理 → 0.5 秒経過 →
`Session.submitCommandDone()` で再開。

### t = 終端

最後の `Return` で `DialogueComplete` → `DialogueView.dialogueComplete()` →
`viewQueue.pushBack(Complete)` → 次フレームで `applyEvent(Complete)` が
`emptyState(profile)` に戻し (`elapsed` のみ保つ)、`visible = false`。

---

## 10. DialogueProfile (JRPG vs VN)

| フィールド | JRPG | VN |
|---|---|---|
| `maxLinesPerPanel` | 3 | 1 |
| `breakOnSpeakerLine` | `true` | `false` |
| `autoNextContinuation` | `true` | `false` |
| `transitionDuration` | 0.6s | 0.2s |
| `revealCharsPerSecond` | 40.0 | 50.0 |
| `blinkPeriod` | 0.5s | 0.5s |
| `nextIndicatorGlyph` | `"▼"` | `"▼"` |

挙動の差:

- **JRPG**: 名前付き Line で新パネル化 + 確定キー待ち、無名の継続行は自動送り。3 行
  まで蓄積したら確定キーで次パネル
- **VN**: パネル = 1 行。毎行確定キーが要る。名前 prefix は装飾扱い (新パネル化しない)

純粋関数 (`applyEvent` / `shouldShowNextIndicator` / `shouldAutoNext` 等) は
`profile` を読んで分岐するため、Scene 側のコードはジャンルを意識しなくて済む。

カスタムプロファイルは個別フィールドを上書きして作る:

```flix
let myProfile = { revealCharsPerSecond = 80.0 | Dialogue.jrpgProfile() };
let state = Dialogue.emptyState(myProfile);
```

---

## 11. CommandParser

`Dialogue.CommandParser.parse(text)` は VM の `WaitingCommand(text)` (= `<<` `>>` を
剥がした中身) を **コマンド名 + 引数列** に分解する純粋関数。

```
"wait 0.5"            → ("wait", ["0.5"])
"bgm play title loop" → ("bgm", ["play", "title", "loop"])
"save"                → ("save", [])
""                    → ("", [])
"  bgm   fade   1.0  "→ ("bgm", ["fade", "1.0"])    // 連続空白は無視
```

クォート文字列 (`"..."` 内の空白を保持) は **当面サポートしない** (YAGNI)。必要に
なったらこのモジュールを拡張する。

---

## 12. テスト時の使い方

### 純粋層 (`UIState` 遷移) のテスト

副作用なしなので region も effect も不要:

```flix
let state0 = Dialogue.emptyState(Dialogue.jrpgProfile());
let state1 = Dialogue.applyEvent(
                Dialogue.ViewEvent.Line("おう: ゆうしゃよ", Some("おう")),
                state0);
Assert.assertEq(expected = ["おう: ゆうしゃよ"], state1#lines)
```

### Runner の effect 層テスト

`Dialogue.Test.withTestDialog` 1 行で 3 段 handler（StubView + sync runner +
no-extension）を被せ、view イベントログを返す:

```flix
@Test
def testFlow(): Unit \ Assert =
    let project = TestYarnFixture.loadProject();
    let events = region rc {
        let (_, log) = Dialogue.Test.withTestDialog(rc, project, () -> {
            Dialogue.Session.start("Start");
            Dialogue.Session.submitNext();
            Dialogue.Session.submitSelect(0);
            Dialogue.Session.submitNext()
        });
        log
    };
    // events: [Line(...), Line(...), Choices(...), Line(...), Complete]
    Assert.assertEq(expected = ..., events)
```

`withTestDialog` の中身:

- `Dialogue.StubView.withRecordingView` — view 操作を `ViewEvent` ログに蓄積
- `Dialogue.Runner.withRunner(..., syncCommands = true, ...)` — `<<command>>` を即完了扱い
- `Yarn.BuiltinExtension.withNoExtension` — `inv_has` 等のゲーム固有関数を「常に `NotFound`」で握りつぶす（テスト fixture が拡張を使わない前提のとき）

詳細は [`yarn/README.md` §11](../yarn/README.md#11-テスト時の使い方)。

実例は `test/engine/dialogue/TestDialogueRunner.flix` / `TestCommandParser.flix`。

---

## 13. 本番統合 (`withDialog`)

`Game.flix` ではこの 1 行で 2 段 handler を被せる:

```flix
run gameLoop()
    with Dialogue.withDialog(yarnProject)
```

これは内部で:

```
region rc {
    run body()
        with Dialogue.Runner.withRunner(rc, yarnProject, false)  // Session 実装 + 非同期コマンド
        with Dialogue.SceneView.withSceneView(rc)                // DialogueView + Inbox + CommandInbox
}
```

の糖衣。region と event queue を内部に閉じ込めるので、`gameLoop` 側は
`Session.start` / `Inbox.takeAll` / `CommandInbox.takeAllCommands` を呼ぶだけで済む。
`syncCommands = false` を渡しているので `<<command>>` は外部完了通知 (`Session.submitCommandDone`)
を待つ。`Game.CommandRouter` が完了タイミングで呼ぶ。

---

## 関連ドキュメント

- [`src/engine/yarn/README.md`](../yarn/README.md) — VM 本体・命令一覧・StepResult・Builtin 拡張点
- 本プロジェクト固有のコマンド処理は `src/game/CommandRouter.flix` を参照
- Scene 側の使用例は `src/scenes/DialogueScene.flix` を参照 (`process` で `Inbox.takeAll → applyFrame`、`handleInput` で `Session.submit*`)
