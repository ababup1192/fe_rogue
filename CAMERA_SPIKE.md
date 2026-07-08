# カメラ Bevy スタイル移行 — スパイク作業メモ

worktree: `agent-a6f645e2bace17df5`（未コミット・使い捨てスパイク前提）
最終更新: 2026-07-08

## 目的・方針

カメラを Godot 風モノリシック `engine/scene/Camera2D.flix`（659行・追従+変換+scene ノードの3役）から **Bevy スタイル**へ寄せる。

- 機能別 module に分割し engine_world / engine_core が提供する
- **World が持つ状態は position（`cameraSmoothPos: Vec2`）ただ1つ**（Resource スタイル撤去）
- Viewport を Camera(Projection) に統合（Bevy の `world_to_viewport` 語彙）
- CameraFollow を Godot から輸入（lerp スムーズ追従 `t = min(1, speed*dt)`）
- pipe 合成しやすい純関数
- **終着点＝world↔screen 変換語彙を `engine_core.CameraProjection` に一本化**（今 `Camera2D.ViewTransform` と `CameraProjection.Projection` が構造同型で二重）。Camera2D は「Godot 互換 scene ノード」の単一責務へ痩せる

## 到達点（実装済み・green）

### 新設ファイル
- `engine_core/src/CameraProjection.flix`（56行）— Bevy 語彙の変換。`Projection={offset,scale}` / `worldToViewport` / `viewportToWorld` / `toProjection(center,zoom,viewport)` / `Viewport={width,height}`。**Step A で engine_world→engine_core（最下層）へ移設済**
- `engine_world/src/CameraFollow.flix`（67行）— 追従の純関数。`step`（lerp+deadZone・Camera2D の式を字面移植＝golden 保つ）/ `settled`（+2px/4px 閾値）
- `engine_world/src/Camera.flix`（48行）— **ファサード**。下記
- `engine_world/src/OffscreenCull.flix`（23行）— カリング（未使用ぎみ・削除候補）
- `examples/fe_rogue/src/render/CameraView.flix`（16行）— fe_rogue 側の橋。`config()`=`Camera.smooth(...)` / `projectionOf()`=`Camera.projectionOf(...)`

### 撤去
- `engine_world/src/Viewport.flix`（未使用）
- `examples/fe_rogue/src/ecs/CameraState.flix`（旧 Camera2D 値 resource・87行）

### ファサード `Camera`（engine_world/src/Camera.flix）
下の部品を1つの入口にまとめた窓口。初学者は `Camera.` だけ、上級者は部品直呼び（Bevy の DefaultPlugins vs 個別 plugin と同型）。
- 型 re-export: `type alias Config = CameraFollow.Config` / `Viewport = CameraProjection.Viewport` / `Projection = CameraProjection.Projection`
- 設定プリセット: `smooth(zoom)`（ゆるやか・deadZone 0.3）/ `snappy(zoom)`（きびきび）/ `locked(zoom)`（中心固定）
- 毎フレーム: `chase(...)`（=CameraFollow.step）/ `settled(...)`（=CameraFollow.settled）
- 変換: `projectionOf(...)`（=CameraProjection.toProjection）/ `toScreen(...)`（=CameraProjection.worldToViewport）
- **`project` は Flix 予約語**なので `projectionOf` にした（既知の落とし穴・再度踏んだ）

### Step A 実測（green）
CameraProjection を engine_world→engine_core へ `mv`+sync。engine_world/engine_core ビルド green・**fe_rogue 38 test green・golden(PNG/GIF SHA)一致・FAIL 0・参照側 import 改修ゼロ**（mod 名保持で推移パッケージ解決）。→「置き場所を最下層へ移しても mod 名を保てば参照側ゼロ改修」を実証。

### ファサード＋型 re-export 実測（green）
fe_rogue を Camera 経由に置換 → test green・golden 一致。CameraView から `CameraFollow`/`CameraProjection` の直呼び・型名が消えて `Camera.*` だけに。

## いま worktree に残っている「未確定物」（要処理）

- `examples/fe_rogue/src/systems/CameraScene.flix` に **`commit` という「畳みすぎ版」ヘルパ**が残っている（read→chase→emit を1関数に畳んだもの）。green だが **要撤回**。理由: World への emit が隠れ、他 driver（emit 明示の流儀）と一貫性が崩れる＝可読性の問題（純粋性・golden 自体は壊れていない）。
- 代替案（未実装）: `setCameraSmoothPos` セッターで `Command.emit(Cmd.SetCameraSmoothPos(v))` の3層ネストのノイズだけ畳む（emit という行為＝World 権威は明示のまま残す）。

## Cmd 形式についての結論（重要・方針転換あり）

「emit が大変」→「Cmd 形式は本当に真か？」の議論の結論:
- **Cmd 形式は fe_rogue（effect ベース gameLoop 家族）のローカルな正解であって、グローバルな真理ではない**。breakout/sokoban（App 家族）は Cmd/emit を使わず `(Frame,World)→World` の値合成で同じ本質（World 権威・巻き戻し・golden）を達成している。
- fe_rogue は World を `Ref` で持ち、`Command.emit(cmd)` が `applyCmd(cmd, world)` で即 Ref 更新する手続き型（`WorldDriver.withWorld` の handler が `Ref.put(applyCmd(c, Ref.get(worldRef)), worldRef)`）。
- **`applyCmd(cmd, world): World` / `stepFrame(current, dt): World` という純粋コアは既にある**（値合成の素地はある）。手続き的なのは worldRef への書き戻し（emit）の層だけ。
- **カメラ単体では Cmd を消せない**: gameLoop（effect 家族）から worldRef へ world を反映する口が emit しかないため。しかもカメラは view-lane（描画直前）で sim の stepFrame とは別フェーズ。
- **Cmd を完全に消すには fe_rogue gameLoop 全体を値合成家族へ寄せる**大リアーキが必要（view-lane / sim-lane の2フェーズ再設計込み）。

## 値合成化の調査結果（2026-07-08・Explore agent 2本）

### 数値
- `applyCmd(cmd, world): World`（World.flix:749-1087）は **enum Cmd（World.flix:493-561, 60 case）を全網羅する完全な純関数**。effect 注釈なし
- World 更新の純関数群も既存: `stepWorld`（tween/fx tick）/ `stepAnimClocks` / `applyEventToWorld`（内部は applyCmd 再利用）/ `refreshMirror`
- **手続き的な書き込みは World.flix に一切ない**（全てレコード更新の値合成）。World フィールド直接構築も World.flix 内に完全カプセル化（外部0件）
- 手続き的なのは `Command` effect handler `emit(c) = Ref.put(applyCmd(c, Ref.get(worldRef)), worldRef)`（WorldDriver.flix:43）だけ
- **emit は約150〜164 箇所・21 ファイル**に散在: PlayerScene 71 / EnemyScene 36 / CombatDriver 11 が大半

### 「Cmd を消す」＝ emit を消す（Cmd enum は残す）
値合成コアは既に完成。「Cmd を消す」の正体は **emit effect を撤廃し、Cmd を `List[Cmd]` 戻り値で受け渡して `foldLeft(applyCmd)` で畳む配線の付け替え**。Cmd/applyCmd/eventToCmds はそのまま流用できる。`CombatDriver.flix:540` は既に `events |> flatMap(eventToCmds) |> forEach(emit)` ＝「値で Cmd 列を組んでから適用」の好例（emit を foldLeft(applyCmd) に変えるだけ）。

### 障害
- (a) worldRef 手続き書き込み: Game.flix:856/879、WorldDriver.flix:43 emit handler
- (b) **World の外の権威 State effect が約20種**（TurnPhase.State / SelectedPlayer / CursorState / GatherResume / UiWorldState / EnemyTurn.Queue …）。`(Frame,World)->World` に寄せるには World field へ統合 or Frame 入力化が要る。**特に TurnPhase.State は World と dual-write**（Game.flix:774-781、stepFrame の parity 検査が象徴）＝**最大ボトルネック**
- (c) GameEngine 入力/音/描画 effect への癒着: handleInput 450行、`getViewportRect` を sim 内で直呼び、Audio/CustomEffects を sim 判断中に発火
- (d) emit 150超のシグネチャ連鎖変更（`Unit \ World.Command` → `List[Cmd]` 返却へ）

### 難易度（3段階）
- **カメラ/カーソル周辺だけ**: 低。閉じた read→計算→emit なので Cmd 戻り値 or World 返却に変えるだけ。真っ先に着手可
- **sim 全体**: 中〜高。①TurnPhase を World 統合 ②emit 150超書き換え ③CustomEffects 純関数化 の三段階。regression risk 高
- **view-lane 込み全体**: sim 全体完遂が前提＋handleInput 450行の圧縮＝**現時点では非現実的**

### 模範と分水嶺
- 模範: `stepWorld`（tween/fx tick）が既に `World->World` 値合成の見本。これを横展開するのが筋
- 分水嶺: **TurnPhase の権威を World へ統合できるか**が「sim 全体を値合成化できるか」を左右する

## 決定した順序と方針（2026-07-08・要ユーザー判断）

当初「Cmd を完全に消してから、カメラ」の順序で合意。ただし調査の結果、**Cmd 完全撲滅（全面・view-lane 込み）は非現実的**（特大・regression risk 高）。現実的な落とし所は **段階的移行**:
1. カメラ/カーソルなど「world を read→計算→emit するだけの閉じた driver」から値合成化（低難易度）
2. `stepWorld` の模範を横展開
3. **TurnPhase の World 統合**を要石として試す（sim 全体の分水嶺）

→ このどこまでやるかはユーザー判断待ち。

## 残ステップ（engine 変更ゆえ着手前に相談）

- **Step B**: `Camera2D.ViewTransform` を `CameraProjection.Projection` の別名に（engine→engine_core・golden 不変のまま意味的一本化）
- **Step C**: engine/scene・IDE を Projection へ改名（葉から・ブリッジで途中も compile 可）。**ユーザー明言=IDE は壊れてOK・作り直す**ので大胆に進めてよい
- **Step D**: Camera2D から follow 撤去→scene ノード単一責務

### Camera2D 全体削除は不可（実コードで確定）
- ①追従＝削除可（CameraFollow が肩代わり）
- ②ViewTransform 変換語彙 + Camera2DWithState scene ノード＝**削除不可**（engine/scene/Scene.flix 描画パイプ・GameEngine:310 findActiveCamera・EngineNode・SceneLoader・**ide/ 全体**が依存）

## 検証コマンド

```
make sync-engine-core      # engine_core fpkg を全依存先へ配布
make sync-engine-world     # engine_world fpkg を配布
make test-fe_rogue         # FLIX_TEST=headless 付き。golden(PNG/GIF SHA)一致＝挙動不変の機械証明
```
番人: golden SHA=挙動不変の機械証明 / CameraFollow の式 pin=新旧同値 / TestMapIntegration=ゲーム進行（isSettled ゲートが止まらない/暴走しない）。

## 関連
- メモリ: `project-camera-bevy-style`（~/.claude/.../memory/project_camera_bevy_style.md）に同内容
- プラン: `~/.claude/plans/woolly-jingling-lantern.md`
- Before/After Artifact: https://claude.ai/code/artifact/50f579c8-6428-409a-8c58-f2582db6d3b4
