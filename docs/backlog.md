# 課題メモ（トリガー待ちの将来作業）

いますぐやらないが、**ある出来事が起きたら着手する**と決めてある作業を、
トリガー（着手の合図）つきで置いておく。トリガーが来たら別計画として起票する。

## App の構造

- **App を `{init, update, view}` の3口へ整理する検討** — トリガー: **初学者向けに
  「ゲームループの2役割」を doc でなく型で示したくなった時点**。現状 App は addSystem /
  withView / withAudio 等の多数の繋ぎ口を持ち、更新（状態を進める）と描画（絵に写す）の
  分業は doc コメントで説明している。この分業を1つのレコード型（init/update/view）で表に出すと
  初学者がループ構造を型から掴めるが、既存ゲーム全ての Main を書き換える大工事なので別計画。
  今回は API を変えず doc の明示に留めた。

## デュアルグリッド地形の昇格（2026-07 完了）に伴う積み残し

- **editor_server の engine 0.8.0 追随** — トリガー: **Studio マップエディタが
  `TerrainDoc.palette` を呼ぶ実装を開始する時点**。flix_ge_studio/server は
  `flix_engine_core` / `flix_engine_world` / `flix_engine_tools` を 0.7.1 固定で
  参照しており（全量 sync は API 乖離で現状不可という既知の状況）、パレット供給口
  `TerrainDoc.palette` を server から呼ぶにはこの追随が要る。マップエディタ実装計画の
  開始時に「editor_server 0.8.0 追随」を別計画として起票する。あわせて rows の
  保存形式の固定（文字列配列・SetOp 全置換 = 既存 Main.elm の実装形を正とする）を、
  その起票するマップエディタ側計画の requirements に転記し、承認条件とする。

- **lighten / darken の重複を一本化** — トリガー: **engine に共有の
  `Color.lighten` / `Color.darken` が入った時点**。現状は白/黒へ寄せる同式の線形補間が
  3 箇所に散っている（engine `TerrainDoc` の private 実装・rpg-starter `ThemeDoc` の
  pub def・dungeon `Surfaces` 相当）。engine が template の ThemeDoc に依存する向きは
  作れないためやむなく重複している。共有ユーティリティが engine の Color に入ったら
  `TerrainDoc` / `ThemeDoc`（/ dungeon の Surfaces）をそれへ寄せて一本化する。

- **dungeon の Surfaces を engine Terrain へ寄せる移行** — 将来計画（定期見直し）。
  dungeon は当面 engine の `DualGrid` / `Material` を呼ぶだけに留め、セル種→質感の表
  （Surfaces）は dungeon 側に残す。dungeon Surfaces と engine Terrain が別実装のまま
  乖離していく温床なので、**engine 側で Terrain に手を入れるときは Surfaces との差分を
  確認し、下に最終確認日を残す**。乖離が痛くなった時点で「golden 一致で締める機械的
  リファクタ」として移行計画を立てる。
  - 最終確認日: 2026-07-24（M5 時点。差分レビューはまだ不要と判断）
