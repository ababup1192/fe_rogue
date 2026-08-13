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
