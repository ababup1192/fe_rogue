---
name: mapchip-debug
description: "fe_rogue のマップチップ不具合（黒い穴・欠けた壁・繋がらない天井帯）を注釈チケットの world.json から再現・検証して直す標準フロー。「注釈: fe_rogue — frame N」の md が貼られてマップの見た目の修正を求められたら、作業前に必ず読む。"
when_to_use: "「マップチップ直したい」「壁が壊れた」「黒い穴」「チップ(4,1)があるべき」等。material.json の wallMap / autoRules を触る作業全般も対象。見た目以外（フロー系バグ）のチケットは対象外。"
allowed-tools: Read, Grep, Glob, Bash, Edit, Write
---

# マップチップデバッグ（fe_rogue）

F8 注釈チケット（`examples/fe_rogue/debug/annotations/<チケット>/`）でマップチップの
見た目不具合が報告されたときの標準フロー。**スクショからの目視推定でルールを書かない**こと
（過去に実フロアで誤発火して壁を壊した）。必ず world.json → オフライン再現 → 全セル差分検証の順。

チケットが見た目でなく進行・フロー系のバグ（例: フロアがリセットされない）なら本フローは使わず、
コメント欄の再現手順と world.json の要約（floorId / screen / turnPhase / HP）から通常のバグ修正をする。

作業ディレクトリはすべて `examples/fe_rogue`。

## 仕組みの前提（30 秒で思い出す）

- 床 = decorTiles、自動壁 = 床の 8 近傍 ring（`MapLoader.computeWallCells`）。
- 壁チップは TRBL trit キー（上右下左を W/F/E で符号化）で material の `wallMap`（全 81 キー）を引く。
- その上に `autoRules`（IntGrid 5x5 パターン・**第一マッチのみ**・manual セルは抑止）が重なる。
- **wallMap は 4 近傍しか見えない**。同じキーで違うチップが要る箇所（L字の合流角など）は autoRules で上書きする。
- material はアンカー部屋（modulePaths 先頭 = 常に部屋）のものがフロア全体に適用される。
  → ルール追加先は **base_room + room_1〜18 の 18 ファイル**（pathway は対象外）。
- タイルはフロア生成時に焼き込み。**material 修正は再起動 / 次フロアまで画面に反映されない**。

## フロー

### 1. チケットを読む

world.json の `cellsInRect`（pos / chips / wallKey / terrain）で対象セルと現状チップが分かる。
`map`（`.`=床 `,`=盤内void 空白=範囲外）と `materialId` が再現の入力。
highlighted.png は「どう見えているか」の確認用。

world.json に `materialId` が無い旧形式なら、新しい注釈を取り直してもらう。

### 2. 再現器を校正する

```bash
python3 debug/replay_tiles.py debug/annotations/<チケット>/world.json
```

cellsInRect が全て OK になること。「dump にだけ余分にあるチップ」は manual タイル由来（正常）。
MISMATCH（計算が dump に無いチップを出す）が出たら再現器か dump の理解がずれている——先にそれを直す。

### 3. 原因セルを調査する

```bash
python3 debug/replay_tiles.py <world.json> --cell 22,18
```

5x5 IntGrid・trit キー・wallMap の引き先・発火ルール名が出る。
**既存ルールがなぜこのセルで発火しないのか**を必ず言語化する（近くの正常な類似地形と比較
すると速い。今回のセルだけ何が違うかがルール条件になる）。

### 4. ルール案を書いて全セル差分で検証する

候補を JSON で書く（material の autoRules と同形式のリスト）:

```json
[{"name": "ルール名", "size": 5, "v": 2, "srcX": 104, "srcY": 26,
  "pattern": [0,0,-1000001,0,0, 0,0,2,0,0, 0,-1000001,2,1,0, 0,2,2,0,0, 0,1,0,0,0]}]
```

pattern は 5x5 行優先。0=不問 / 1=床 / 2=壁 / -1000001=空(void)要求 / 1000001=非空要求。
srcX/srcY はチップ(列,行)×26。**条件は最小でなく「その地形にしか合わない」まで絞る**
（緩いと別フロアで誤発火する。8 条件程度は普通）。

```bash
python3 debug/replay_tiles.py <world.json> --rules 候補.json --diff --render preview.png
```

- 差分が**狙いのセルだけ**であること（これが最重要ゲート）。
- preview.png でチップの帯・エッジがつながって見えること。
- world.json が複数あれば全部に対して回す。

### 5. 適用 → テスト → 記録

```bash
python3 debug/apply_wall_rules.py add 候補.json     # 18 material へ冪等追加（末尾=既存先勝ち）
```

- `test/TestMapLoader.flix` にピンテストを足す（ミニ盤面で「発火する / 類似地形で沈黙する」の対。
  既存の testShortJunction* がひな型）。
- `make test` を**最後に 1 回**（マテリアル JSON のみの変更で golden は動かない実績あり。
  途中で何度も全走しない）。
- before/after を `gallery/` へ、チケット README に対応記録を追記
  （原因 / ルール名 / 検証結果 / gallery リンク / 「反映は次フロアから」）。
- しくじったら `python3 debug/apply_wall_rules.py remove ルール名` で外せる。

## チップ語彙（tileset_dungeon_green・26px角）

ID は `gallery/tileset_green_chip_ids.png` の「(列,行)」。ユーザーとの会話もこの座標で通じる。

| チップ | 役割 |
|---|---|
| (0,5) / (7,5) 等 | 壁の正面（床が下にあるときの明るいレンガ面） |
| (6,0) | 横方向の天井帯（壁上面を横に走る明るい帯） |
| (7,1) / (5,1) | 縦壁のエッジ（(7,1)=左端・(5,1)=右端。床のある側に細い線） |
| (6,1) | 無地の暗い壁内部 |
| (3,0) ┌ / (4,0) ┐ / (3,1) └ / (4,1) ┘ | 天井帯の L 字曲がり角 |
| (7,0) / (5,0) | 帯の端が縦へ折れるフック |
| (5,6) 等 | 床（実際の床装飾はマップの decorTiles 由来） |

## 落とし穴

- **目視の壁/床/空判定は誤る**: 装飾ルール（上辺装飾系）が「空セル」にキャップを描くため、
  明るく見えるセルが IntGrid 的には void のことがある。判定は必ず world.json / 再現器で。
- **既存ルールとの分担**: 同型の地形が既にきれいに描けているなら、そこでは別ルールが発火している。
  `--cell` でルール名を確認し、新ルールは漏れているケースだけを埋める（例: 「長い L」は既存
  「上出口凸左/右」担当、「短い L（縦壁が角の直上で終わる）」だけ新ルール）。
- manual タイルのセルは autoRules 抑止 + dump の chips に余分として現れる（再現器は写せない）。
- 左右対称の地形は**鏡像ルールもセットで**足す（片方だけ直すと逆側のチケットがすぐ来る）。
