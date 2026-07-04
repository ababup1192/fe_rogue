# UI クックブック — パーツ制作の標準手順

このファイルは「手順に従えば、熟練なしでも品質の揃った UI パーツが作れる」ことを目的とした標準手順書。
実証済み: この手順（の原型）に従ったサブエージェントが、ActionMenu を雛形にメニュー4本を品質を保って量産した。
規約の詳細（スキーマ・幾何・z帯）は `README.md`、スナップショット運用は `../../test/snapshots/README.md` が正。

---

## レシピ1: 選択メニューを1つ追加する

参考実装: `ActionMenuUi.flix`（動的項目+幅フィット）/ `SuspendConfirmUi.flix`（固定2択の最小形）

1. **ui.json を書く** — `assets/<Name>.ui.json`
   - root に `"layer"` を必ず宣言（重なる窓は z 帯を分ける。README「窓ごとの前後は z 帯で分ける」）
   - パネル + ヘッダ + 最大項目数ぶんの行スロット。行テンプレは `"pad": [1.5, 0, 1.5, 0]`（ハイライト inset 0.5 + 余白 1px — 幾何規約）
   - 選択ハイライト箱（`#16314f` 塗り + `#2f6df0` 枠 0.5 + 角丸2）を menu 内の abs 子として宣言
2. **`<Name>Ui.flix` を書く** — 定数（specPath/rootPath/menuPath/slotPath/maxSlots/行ピッチ）→
   - `buildItems`: 文脈 → `List[{text, disabled, meta}]`（読みは PartyQuery 等の effect 経由）
   - `frameStep`: phase 可視同期 + スロット流し込み + `UiMenu.applyHighlight`。**スロット超過は bug! で検知**・selection は `UiMenu.clampSelection`
   - `moveSelection`: `UiWidget.selectionMoveSkipping`（disabled スキップ+wrap）
   - confirm/cancel: 選択は `UiStore.selectionOf` → `List.nth(buildItems)` で解決
   - 項目数がスロットを超えうるなら windowing（`ItemMenuUi.windowOffset` を再利用。ハイライト y = (sel−offset)×pitch）
3. **結線** — `Game.flix`:
   - `dispatchMenuKey` に対象 phase の Confirm/Cancel、`dispatchNonMenuKey` に ↑↓（`gameOverDirection` と同型の direction 関数）
   - gameLoop パイプに `<Name>Ui.frameStep(dt)`、start に `spawnUiOrBug(<Name>Ui.specPath())`
   - 移動音・確定音は `playInputSfx`（単一集約点）に phase を足す
4. **テスト** — buildItems の分岐 pin + confirm の効果種別 pin（純粋部を切り出す。**@Test 内で UiWorld レコードを直構築しない** — コンパイラの既知 StackOverflow。UiSpec.load→spawnRoot 経由は可）
5. **スナップショット** — レシピ3へ

## レシピ2: HUD / パネルを1つ追加する

参考実装: `TopBarUi.flix`（bind+時間演出）/ `BattlePanelUi.flix`（対象追従配置）/ `UnitCardUi.flix`（カード+sprite）

1. **状態の置き場**: 演出 ephemera（anim/elapsed 等）は `../ecs/resources/<Name>State.flix`（CursorState 同型の Ref-based handler）。UI ツリーの動的状態（selection/visible）は UiWorld
2. **ui.json**: 静的構造 + `"bind"` 宣言（毎フレーム変わる文字は bind + resolver。構造の再spawn 不要 — TopBar の floorNum/phaseJp 参照）
3. **`<Name>Ui.flix`**: `frameStep` = 状態の時間発展（純粋コアに切り出して pin テスト）+ UiStore setter 流し込み + `UiBinding.apply(resolver)`
   - 幅・位置が動く要素は `setWidthPx`/`setAbs`（決定論的に計算 — レイアウト結果の読み戻しは不要な設計にする）
   - 数値の右揃えは「右端 x − 実測幅」（`BattlePanelUi.putRight` 方式）。**固定 x の左揃えに逃げない**（4文字ラベル被りの前例）
   - 図形は poly widget（**凸単位**。凹形状・リングは複数凸サブポリを `setPolyPolys` — TurnEndHoldUi 参照）
4. **結線**: gameLoop パイプ + spawn。dual-write（World の bool 等を driver が読む場合）は書き込み位置の順序制約をコメントに明記
5. **テスト + スナップショット**

## レシピ3: スナップショット / GIF シーンを追加する

参考: `../../test/snapshots/README.md`（正）・`TestUiSnapshots.flix`・`TestGifSnapshots.flix`

1. **カタログ1行**: `SnapshotCatalog.flix` に `{name, desc, kind, scenario, tags}`（scenario はゲーム機能単位。エッジケースは tag `"edge-case"`）
2. **drive 関数1個**: fixture は**データ宣言のみ**（ユニットは実カタログ由来）。UI の組み立ては本物の `frameStep` に任せる（`SnapshotHarness.withMocks` / 確定遷移が要るなら `withFullMocks`）。**手で setText して見た目を捏造しない**（敵フェーズが青かった事故・空きスロット欠落の前例）
3. GIF は `ReplayScript`（`KeyPress(Down) :: ...` の宣言）+ 実 dispatch。生成は `FE_ROGUE_SNAPSHOT_GIF=1`、出力は `test/snapshots/gifs/`（永続・コミット対象）
4. golden は初回目視 → コミット。意図した見た目変更時は `FE_ROGUE_SNAPSHOT_UPDATE=1` で撮り直し、差分を PR で確認

## 品質チェックリスト（全レシピ共通・完了条件）

- [ ] `flix check` + `flix test` 全 green（golden 2回連続安定）
- [ ] RenderLint clean（text 被り・親はみ出し・画面外。意図的な例外は `lint-allow:` タグで明示）
- [ ] 値は既存実装/デザインから厳密に（**目測禁止**）。挙動差・見た目差は正直に列挙してレビューへ
- [ ] 引数5+ or 同型隣接の関数はレコード名前渡し
- [ ] コメントは現在形（移行史・作業経緯を書かない）
- [ ] 予約語に注意: `spawn` / `from` / `region` / `run`（変数名にも不可）

## engine_world UI API メモ（読み戻し・注入・既定フォント）

- **読み戻し getter**（`UiStore`）: setter には対称な getter がある。`textOf(path, ui): Option[String]`（`setText` の逆）/ `visibleOf(path, ui): Option[Bool]`（`setVisible` の逆・継承前の生値）。テストや検算で `ui#texts` など record 内部を直に覗かず、名前パスで読む。未登録パスは `None`。
- **注入版レンダ**: `UiRender.renderUiWith(atlasOf, textureInfoOf, ui, design)` は font 実寸（`atlasOf`）とスプライトのテクスチャ寸法（`textureInfoOf`）を呼び側から渡す。両者が純粋なら描画全体が純粋になり、画面なしのテスト/プレビューは `GameEngine.Game` ハンドラ（全 op スタブ）を組まずに済む。box/text だけのページなら `renderUiWith(_ -> atlas, _ -> None, ui, design)`。本番は薄い委譲の `renderUi`（Game registry 版）をそのまま使う。
- **既定フォント**: ui.json トップレベルの `"defaultFont": "<名前>"` が、`font` を明示しない text ノードの既定になる（省略時は `"ui"`）。全 text が同じフォントのページは各ノードの `"font"` 反復を 1 行に畳める。既存 json は無改変で従来どおり。

## 設計原則（なぜこの手順で品質が出るか）

1. **UI は宣言データ + 純関数** — 構造は ui.json、動きは frameStep。手続き的なノード操作を書いた時点で手順から外れている
2. **fixture は嘘をつけない** — 見た目は必ず本物のコードパスから。スナップショットは「実機でこう見える」の証明
3. **ガードレールが違反を叱る** — golden / RenderLint / 幾何不変条件 / スロット超過 bug!。手順を外れると `flix test` が具体的に落ちる
