# 課題メモ（トリガー待ちの将来作業）

いますぐやらないが、**ある出来事が起きたら着手する**と決めてある作業を、
トリガー（着手の合図）つきで置いておく。トリガーが来たら別計画として起票する。

## App の構造

- **App を `{init, update, view}` の3口へ整理する検討** — **App.game として着手済み**
  （2026-07-24）。`make / addSystem / watchFile / withView` の合成へ desugar するだけの
  便利コンストラクタ `App.game({init, update, view, reloads})` を engine_world/App.flix に
  **追加**し（既存ビルダーは不変）、novel/rpg/game-starter の Main をこの 1 レコード形へ
  書き換えた（スナップショット全枚バイト一致で挙動不変を確認）。初学者は Main を読むだけでループの
  全体像を掴める。update は「合成 1 本」方式（複数システムはゲーム側で `w |> step |> …` と
  繋いで渡す）で、音・HUD・quit 差し替え・複数システムの明示列挙が要る高度なゲームは従来
  ビルダーへ降りる、という線引きは doc コメントに明記済み。新 API なので外部ゲームが使うには
  将来リリースが要る（in-repo テンプレは sync でローカル解決）。

## デュアルグリッド地形の昇格（2026-07 完了）に伴う積み残し

- **リポジトリ内に地形経路の見本が無い** — トリガー: **engine_world の
  `DualGrid` / `Material` / `Terrain` / `TerrainDoc` を編集する時点**。この 4 つを呼ぶ
  コードは `templates/` にも `bench/` にも 0 件で、`.terrain.json` も 0 件。
  `engine_world/test/TestTerrainDoc.flix` は JSON デコードだけを見ており、描画の導出を
  守るスナップショットも無い（値を取り違えても `make test-engine_world` も SHA も緑になる）。
  経路を現役で使っているのは外部の独立リポジトリ（internet_dungeon / dq_map / kaidan /
  harvest_hollow）なので、ここを直しても壊れは repo 内に出ない。触るときは外部リポジトリで
  絵を見るか、テンプレへ地形の場面を足して絵の SHA で守る（後者は `.terrain.json` と
  テンプレ側の配線ごと足す数日仕事）。
  - 最終確認日: 2026-08-13

- **editor_server の engine 追随** — トリガー: **Studio マップエディタが
  `TerrainDoc.palette` を呼ぶ実装を開始する時点**。flix_ge_studio/server は
  `flix_engine_core` / `flix_engine_world` / `flix_engine_tools` を古いバージョンで固定
  参照しており（全量 sync は API 乖離で現状不可という既知の状況）、パレット供給口
  `TerrainDoc.palette` を server から呼ぶにはこの追随が要る。マップエディタ実装計画の
  開始時に、その時点の engine バージョンへの追随を別計画として起票する。あわせて rows の
  保存形式の固定（文字列配列・SetOp 全置換 = 既存 Main.elm の実装形を正とする）を、
  その起票するマップエディタ側計画の requirements に転記し、承認条件とする。

- **lighten / darken の重複を一本化** — **解消済み**（2026-08-13 確認）。engine の
  `Color.lighten` / `Color.darken` が source of truth で、`TerrainDoc` はそれを直接呼ぶ。
  rpg-starter の `ThemeDoc.lighten` / `darken` は `Color` へ委譲するだけの薄い別名。

- **dungeon の Surfaces を engine Terrain へ移す移行** — 将来計画（定期見直し）。
  dungeon は当面 engine の `DualGrid` / `Material` を呼ぶだけに留め、セル種→質感の表
  （Surfaces）は dungeon 側に残す。dungeon Surfaces と engine Terrain が別実装のまま
  乖離していく温床なので、**engine 側で Terrain に手を入れるときは Surfaces との差分を
  確認し、下に最終確認日を残す**。乖離が痛くなった時点で「スナップショット一致で締める機械的
  リファクタ」として移行計画を立てる。
  - 最終確認日: 2026-07-24（M5 時点。差分レビューはまだ不要と判断）

## 性能（2026-08-13 の回で測って打ち切った物）

- **draw 経路の走査を `drawInto` の畳み込みへ同乗させる（適用 E）** — **打ち切り**
  （2026-08-13 に測って判断）。トリガー: **`Render.draw` / `drawWith` / `drawInto` の
  1 回の走査そのものがフレーム時間の 1 割を超えたと数字で出たとき**、または
  **`Item` の case を増やして走査 1 本の per-item の仕事が今より重くなるとき**。
  `engine_world` の draw 経路は 1 フレームに `glyphFingerprint` / `missingGlyphs` /
  `drawShaders` / `withoutShaders` / `drawInto` の最大 5 本、字の指紋が効いている
  ふだんは 4 本を舐める。同乗させれば 1 本になる、という見立てだった。
  **測った結果、届かない。** N=2000（R3 の上限）・design 320×240・この Mac・
  min-of-50 で、`glyphFingerprint` 0.13〜0.20ms / `drawShaders` 0.13〜0.18ms /
  `withoutShaders` 0.18〜0.24ms。**3 本が丸ごと消えるという物理的にありえない上限**でも
  0.43〜0.62ms で、足切りの 0.8ms（R3 の avg 8ms の 1 割）に届かない。
  実際に減るのは `unwrapClip` の引き直しと中間リストの割り当てだけなので、もっと小さい。
  同じ走査で本体の `drawInto` は 3.8〜4.7ms 掛かっており、支配項はそちら（item 1 個
  約 2.3μs という既存の見積もりと一致）。
  **さらに、設計の見立て自体が 2 点まちがっていた**（次にやるとき同じ道を歩かないよう残す）:
  - `glyphFingerprint` / `missingGlyphs` が舐めるのは `itemsForGlyphs`
    （`App.flix:1232`＝レンダーターゲットの items ＋ 本編の items）で、`drawInto` が見る
    `withoutShaders(items)` とは**別のリスト**。1 本の畳み込みには入らない
  - `missingGlyphs` は指紋が変わったフレームだけ走る（`App.flix:1240`）。同乗させると
    毎フレーム走ることになり、**速くなるどころか 0.23〜0.33ms の持ち出し**になる
  同乗できるのは `drawShaders` と `withoutShaders` の 2 本だけで、合わせて 0.31〜0.42ms。
  代金（1 回の走査で 4 つの仕事を同時に進める形は、後から 1 つだけ直したい人に最悪）に
  見合わない。設計は `plans/performance.md:418-432`。
  - 最終確認日: 2026-08-13

- **`ShaderEval.envOf` の画素ごとの `Map` 作り直しをやめる（適用 F）** — **打ち切り**
  （2026-08-13 に測って判断）。トリガー: **`shared`（bindings）を実際に使う shader Doc が
  出てきて、その面が `make render` の中で目に見える時間を占めたとき**。
  `envOf`（`engine/src/ShaderEval.flix:46-51`）は 1 画素ごとに `Map.empty()` から
  binding の表を作り直す。値は `uv` と `t` に依存するので面ごとに 1 回へ持ち上げることは
  できず（持ち上げると絵が変わる）、残る余地は入れ物の作り直しという係数だけ、という
  見立てだった。**測った結果、届かない。**
  **見立ての前提が現物と食い違っていた**: `shared` を持つ shader Doc は
  リポジトリに 1 つも無く（テンプレの `*.shader.json` / `*.fx.json` 全部・コードで
  spec を組む場所も無し）、`bindings` は常に `Nil`。つまり画素ごとに払っているのは
  `Map.insert` ではなく **`Map.empty()` の割り当て 1 個だけ**で、削れる上限が最初から
  ほぼ無い。
  env を `Map[String, Float64]` から連想リスト（`List[(String, Float64)]`・新しい物が先頭・
  `Ref` は `List.findLeft`）へ替えて実測: `make render`（テンプレ 5 本・同一セッション・
  背中合わせ・各 3 回）の実時間は **前 154.5 / 148.7 / 141.9 秒（中央値 148.7・最小 141.9）**、
  **後 148.8 / 154.8 / 157.6 秒（中央値 154.8・最小 148.8）**。改善は無し（測定のばらつき
  ±9% の中で、むしろ遅い側）。合否線の 1 割に遠いので `git checkout` で戻した。
  なお絵は変わらなかった（`make gl-parity` 6 場面すべて 0 px・テンプレ 5 本の reference
  27 枚がバイト一致）ので、**戻した理由は絵ではなく利得がゼロだったこと**。
  そもそも `make render` の実時間はテンプレのコンパイル時間が支配していて、画素ループの
  取り分が小さい（実時間 150 秒に対し CPU 時間 653 秒・406% で、コンパイルが 4 コアを
  使い切っている）。次にこの経路を疑うときは、`make render` の実時間ではなく
  画素ループ単体の数字で測ること。設計は `plans/performance.md:434-446`。
  - 最終確認日: 2026-08-13

- **毎フレーム走らせず結果を持ち回す（`RichText.place` のキャッシュ）** — **見送り**
  （2026-08-13 に判断）。トリガー: **文字送りのある画面で `RichText.place` が
  フレーム時間の 1 割（avg 8ms に対して 0.8ms）を超えたと数字で出たとき**。
  `RichText.place` は文字送りの最中、毎フレーム全部を組み直している。結果を持ち回せば
  文字数が変わったフレームだけの仕事にできる、というのが 3 番目の手。
  **採らなかった理由は代金。** キャッシュを足すと「いつ古くなるか」という新しい正しさの
  問題が生まれ、**絵の SHA では捕まらない種類のバグ（1 フレーム古い絵）**を作りうる。
  スナップショットは各場面 1 枚なので、1 フレーム遅れた絵は正解として登録されてしまう。
  この回で `placeLine` の O(N²) が消えて割り当ての伸びが 19.2 → 8.26 に落ちたので、
  まず**計算量が 1 つ下りた後の数字**を見る。再開するなら「いつ捨てるか」を先に決めて、
  文字送りの途中のコマを複数枚 pin するテストを足してから。設計は
  `plans/performance.md:462-467`。
  - 最終確認日: 2026-08-13

- **二乗の形を機械で裁く `bin/lint-quadratic.py`** — **作らないと判断**（2026-08-13）。
  トリガー: **この回で直したのと同じ形の二乗が、もう一度コミットに入ったとき**
  （1 回でも再発したら固定費より安い）。
  理由は固定費で、`.flix` を 1 本ステージすると既に 4 本の lint が走っており
  （`lint-view` / `lint-fallback` / `lint-f32` / `lint-jargon`）、5 本目になる。
  **結果として、この回は「同じ形がまた入るのを機械で止める物」を持たない。**
  残したのは文章だけ（`docs/performance.md` と `.claude/rules/flix.md` の「二乗を書かない」）。
  作るときの材料は `plans/performance.md:364-416` にそろえてある — 裁く 3 規則、
  既存パーサ（`gen-api-digest.py:290` / `lint-fallback.py:143`）は本体を持たないので
  借りられないこと、`RichText.flix:118` の二重の `List.foldLeft` はタプル分解の別名を追う 1 段階が
  要ること、適用範囲はステージした差分の + 行だけにすること。
  **当たる件数の実測は 規則 1 が 9 件・規則 2 が 1 件・規則 3 が約 12 件**（合計約 22 件。
  この回で 6 件直したので残り 16 件前後）。EXEMPT は宿題の一覧にならない
  （規則 3 の大半は 3〜10 要素の許可リストに対する会員判定で、理由が「N が定数」ばかりになる）。
  宿題の置き場は `docs/performance.md` の「残っている二乗の一覧」。
  - 最終確認日: 2026-08-13

## サンプルテンプレを増やして見えた共通化の芽（2026-07-24）

shooter / race / raise の 3 スターターを教科書として作る中で「エンジン/Studio にこれが
あれば車輪の再発明が減る」と感じた点。方針は **一度きりの手書きは共通化しない、2〜3 本
重なったら持ち上げる**。ユーザー判断で **いまは着手せずメモに留める**（2026-07-24）。

- **rows（文字格子）の Doc/schema 型 + Studio の格子エディタ + プレビュー追随** —
  トリガー: **実質達成**（rpg=map / shooter=waves / race=course が rows を使い、Studio の
  schema にこれを表す型が無くフォームに出せず note の説明で逃がしている。tetris の盤は
  コード）。**最レバレッジ**（「非プログラマが配置を触れる」= Studio の存在意義そのもの）。
  再開時に最優先で別計画として起票する。MapEditor.elm の格子資産を流用できる可能性。
- **スクロール（ループ）背景の描画ヘルパ** — トリガー: **3 本目の「流れる背景」ゲーム**。
  現在 2 本（race のループ道・shooter の星空）を View に手書き。Terrain/TerrainDoc は静的
  マップ + dual-grid 用でスクロール/ループを想定せず素の背景には過剰。3 本目が来たら
  「rows を縦/横に流す背景」ヘルパを engine_world に持ち上げる。
- **ゲージ/バーの宣言ヘルパ（`Render.gauge(rect, ratio, fg, bg)` 相当）** — トリガー:
  **2 本目**（RPG の HP 等）。現在 raise が「値/上限に比例する棒（土台+中身+ラベル+数）」を
  View で手組み。育成・RPG 系で頻用。
- **軽量な List×List 当たり判定ヘルパ（重なるペアを返す純粋関数）** — トリガー: **2 本目**
  （ブロック崩し等）。engine の `Collision.detectCollisions` は Map[EntityId]+layer/mask
  前提で STG の弾×敵には重い。shooter は自前 `overlaps`+二重ループ（教育性優先で許容）。
- **UiStore 非依存の軽量キーボードメニュー・キット（項目列+カーソル+ハイライトを
  PlacedItem で返す純粋ヘルパ）** — トリガー: **2 本目のキーボードメニュー主体ゲーム**。
  現在 raise が素の Render で手組み（novel は UiStore ベースの UiMenu/ui.json で別系統）。
  カーソル回り込みだけ `UiMenu.moveCursor` を再利用済み。
- **固定キー集合を 1 関数で拾う Doc デコードヘルパ（軽微）** — raise の `statsFromRow`
  （power/spirit/skill の 3 数）のような固定キー組の写経が少し減る。優先度低。
