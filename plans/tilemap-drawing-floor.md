# 盤を敷く口をどうするか — 「毎フレーム N 個の PlacedItem を組む」事故の根本対応

状態: **設計前の調査が済んだ段階**。実装は未着手。engine の pub は 1 行も触っていない。

## 1. 発端

dq_map（見下ろしワールドマップ・1 マス 16px）で fps が落ちた。人が手で
`PxSprite.draw`（box 列）→ `PxSprite.drawQuad`（1 コマ 1 クアッド）へ移して直したが、
**同じ踏み方を毎回している**という指摘から、engine 側で起きにくくできないかを調べた。

## 2. 調べて分かったこと（すべて実物で確認済み）

### 事故の一般形は「ドット絵の box 列」ではない

**毎フレーム N 個の PlacedItem を組む**という 1 つの形が、少なくとも 6 か所に散っている。

| 場所 | 危なさ |
|---|---|
| `Terrain.fromRows` / `staticItems` → `Material.blotchItems` | **doc に「毎フレーム呼ぶな」の警告が 1 行も無い**。`module-index.md:261` が「この 4 つを呼ぶ見本はリポジトリに無い」と明記。AGENTS は地形に Terrain を使えと指示している |
| `PxTerrain.fill` | `PxTerrain.flix:5-6` に警告はあるが、強制する物が無い |
| `Fx.derive` / FxDoc の emitter（`Fx.flix:20,75`） | **count が JSON から来る**。コードを 1 行も触らずに予算を突破でき、API 名ベースの lint では原理的に検出不能 |
| `PxSprite.draw`（box 列） | 今回踏んだ所 |
| 1 マス 1 quad のループ | **dq_map は quad へ移した後もここに居る**（後述） |
| `RawDraw.box` の手打ち | N は小さいが同じ形 |

予算は既に決まっている — `docs/performance.md:29` の R3「**動的 PlacedItem < 2000 個/フレーム**・
avg < 8ms / p99 < 12ms」。

### dq_map は quad へ移した今もまだ間違っている

盤を敷く正解は `App.withTileLayers`（1 draw call・`App.flix:308-325`）。
今は 252 マス（14×18）× 最大 20 個（床 1 + 砂の縁 8 + 浅瀬と波頭 12 + 城 1）の quad を
毎フレーム組んでいる（`dq_map/src/View.flix:36-42`、`src/MapTiles.flix:117-141`）。

ただし**海と波頭が 2 コマで動く**ので丸ごとはタイル層に載らない —
`App.flix:322-323`「**タイルのコマ替えアニメは持てない** — 水面・旗のように動く絵は
動的側かシェーダー面で描く」。**動かない陸・砂の縁を静的タイル層へ、動く水面だけ動的に**
という分割が要る。この分割の見本はリポジトリのどこにも無い。

### 新しいゲームが写す手本が、遅い方を教えている

- `make new-game` の既定テンプレは **game-starter**（`Makefile:762`）で、その実機 View は
  box 列（`templates/game-starter/src/View.flix:61`）
- 実機 View の内訳: box 3 本（game / novel / rpg のキャラ）: quad 2 本（platformer / rpg の町）
- **タイル層の見本は platformer と rpg にしか無く、既定テンプレには無い**
- game-starter は `reference/SHA256SUMS.txt` を持たない = **reference の作り直しゼロで直せる**
  唯一のテンプレ（`Makefile:171` の `TEMPLATE_DIRS` からも除外）

### 却下した案と、その理由（同じ道を 2 度通らないため）

**案 B「アトラスを App が持つ・配線ゼロの quad 経路」— 却下。**

1. 作り直しの合図が取れない。`watchFile` は `App.flix:213`「**監視は withDebug 有効時のみ**」で、
   リリースビルドでは初回フレームしか合図が来ない。key を engine が持つ設計だと、
   走行中に色が変わるゲームの絵が永久に固まり、**ゲーム側から要求する手段もゼロ**になる
2. 合図は `Branch.Running`（`App.flix:785-795`）にしか無く、Paused / Resuming / Remote が抜ける
3. **タイル層に届かない。** `TileLayerSpec` の `Tileset` は `baked#side` を要る
   （`templates/rpg-starter/src/TownMap.flix:27-33`）が、`tileLayers = w -> List[TileLayerSpec]`
   （`App.flix:136`）は ViewCtx を通らない。rpg-starter と farm_dungeon は World に Baked を
   持ち続けるしかなく、「そこそこ速い経路が配線ゼロ・一番速い経路が 5 段配線」という
   同じ坂が残るだけ
4. 移行が 25 ファイル + reference 最大 28 枚 + 外部ゲーム 7 本（観測不能）。`pub` 不変の門
   （`docs/performance.md:15`）の正面衝突
5. `ViewCtx` にフィールドを足すのも pub の変更（`docs/performance.md:20-23`「**pub を「足す」のも
   同じ扱い**」）。また `view(ctx, w)` が前フレームまでの履歴を運ぶようになり、
   F8 の時間スクラブで「巻き戻した World を現在の色で描く」ことになる

**案「lint で禁じる」— 却下。** 正当な呼び手がゲームの src に実在する
（atelier のコンタクトシート `dq_map/src/render/SceneRender.flix:160`、
`farm_dungeon/src/View.flix` の 7 か所は N が小さいので box が正しい）。Fx の count は
JSON 由来なので原理的に検出できない。

### 誇張だった数字（訂正済み）

- 「1 マス 256 個の box」→ `PxSprite.draw` は横に連続する同色を 1 矩形へ結合する
  （`PxSprite.flix:161-181`）。実数はその数分の 1
- 「300 マス」→ 252 マス（`assets/dq_map.map.json` は 14 行 × 18 列）

### 使える前例

- **key を画素から導く**: `templates/rpg-starter/src/World.flix:145-148` が `baked#pixels` を
  畳んでハッシュを key にし、理由まで doc に書いている。これを engine へ昇格すれば
  世代番号（`atlasGen`）が全ゲームから消え、resolver が何で変わっても追随する
- **名前 1 つで引ける形**: `withFonts` + `ctx#fontOf`（`App.flix:57,238`）。ゲームは
  `FontAtlas` を持たない。ただしドット絵は headless が画素を要る
  （`dq_map/src/render/SceneRender.flix:73-83`）ので、そのまま写せはしない

## 3. これからやること（順序は決定済み）

**根本 → テンプレ反映、の順。**

### 根本（未設計・次のセッションの主題）

「格子に敷く絵」を宣言するだけで、**engine が静的タイル層と動的 quad に分ける**口。
設計で答えを出すべき問い:

1. ゲームは何を渡すか。rows +「マス → コマ名」の純関数か。動くマスをどう申告するか
   （`Cell -> Option[String]`（None = 動的側）か、静的用と動的用の 2 本の関数か）
2. 静的側の key を engine が導けるか（rows と Doc の世代から）。導けないなら誰が持つか
3. `Tileset` が要る `baked#side` を、ゲームに Baked を持たせずに渡せるか。無理なら
   「Baked は World が持つ」を認めた上で持ち物を 1 個に減らす（`PxSpriteAtlas.toSheet`）
4. headless（`TileScene.toItems`）と GPU 経路で同じ絵になることをどう担保するか
5. 予算超過の検出（組み上がった PlacedItem 数が R3 を超えたら初回 1 回だけ `Log.warn`）を
   同時に入れるか。**これは API に依らず全 6 か所を 1 つの網で拾える唯一の手**で、
   実装は `App.renderFrame`（`App.flix:1271`）で長さを 1 回取るだけ

## 3.5 根本の設計（レビュー前の草稿）

### 何が本当に足りないか

タイル層（`App.withTileLayers`）は既にあり、速い（1 draw call）。**足りないのは、そこへ
たどり着くまでの 55 行**。`templates/rpg-starter/src/TownMap.flix:18-54` がその全量で、
中身は 4 つの定型:

1. `Baked` から `Tileset` を組む（`baked#side` を texWidth / texHeight に写す）
2. rows の全マスを回して `PxSpriteAtlas.regionOf` でコマの矩形を引く
3. マス座標 × tileSize で `px` を出す
4. サンクに包み、key を決める

**この 55 行を書くくらいなら、View に 1 マス 1 quad のループを書く方が短い。** これが
「一番速い経路が 5 段配線」の実体で、dq_map が quad へ移した後もタイル層へ行かなかった理由。

### 足す物（engine_world に 2 つ・既存 pub は 1 行も触らない）

```flix
// PxSpriteAtlas に足す — 生成結果と、それを指す名前・key を 1 つの値にまとめる
pub type alias Sheet = { texture = String, key = String, baked = Baked }

/// アトラスを生成して Sheet にする。key は生成した画素から導くので、ゲームは世代番号を持たない
/// （前例: templates/rpg-starter/src/World.flix:145-148）。resolver が何で変わっても、
/// 画素が変われば key が変わる = GPU のテクスチャが必ず追随する。
pub def toSheet(texture: String, doc: PxSpriteDoc.Doc, resolver: String -> Color): Sheet
```

```flix
// 新モジュール PxTilemap — ドット絵の盤を、タイル層の宣言へ写す純関数層
mod PxTilemap {

    /// 重ね順の 1 段。frameAt が None を返すマスには、その段を敷かない。
    pub type alias Layer = { zOffset = Int32, frameAt = Grid.Cell -> Option[String] }

    pub type alias Spec = {
        key      = String,                  // 盤の id（Doc の読み直しはエンジンが見るので混ぜない）
        sheet    = PxSpriteAtlas.Sheet,
        rows     = List[String],            // 盤（Doc がそのまま持っている値）
        tileSize = Float64,
        origin   = Vec2.Vec2,
        zIndex   = Int32,
        layers   = List[Layer]              // 下から順。床・砂の縁・屋根など
    }

    /// 動かない絵をタイル層の宣言へ写す。1 段 = 1 層（zIndex + zOffset）。
    pub def layersOf(spec: Spec): List[TileLayerSpec]
}
```

ゲームが書く量: `PxTilemap.layersOf({ key = "world", sheet = w#sheet, rows = w#map#rows,
tileSize = 16.0, origin = …, zIndex = 0, layers = floorLayer :: shoreLayer :: Nil })` の 1 式。
**`frameAt` はゲームが既に持っている**（dq_map の `MapTiles.frameOf` / `shorePiecesAt` がそれ）。

### 毎フレームの費用（ここを間違えると意味が無い）

- `layersOf` は**段の数だけ**レコードを組む（2〜3 個）。マスは 1 つも回さない
- マスを回すのは `TileLayerSpec#tiles` のサンクの中だけで、**key が変わって作り直す時しか
  走らない**（`TileScene.flix:14-16` の規約どおり）
- だから `rows` を渡す（`List[Grid.Cell]` を渡さない）。呼ぶ側が `Grid.cellsOfRows` を
  宣言の中に書くと 252 マスを毎フレーム組んでしまう

### 自動では分けない（設計の限界を先に書く）

「動くマスと動かないマスを engine が自動で分ける」はやらない。**engine はコマ名が時刻に
依存するかを知る手段が無い**（`frameAt` はただの関数）。ゲームが `frameAt` に動かないコマだけを
書き、動くマス（dq_map なら海と波頭）は今までどおり動的な quad で描く。

これは妥協ではなく分担の線引き: 盤の 8 割を占める動かない絵が 1 draw call になれば、
残る動的 item は R3 予算（`docs/performance.md:29`・2000 個）に対して十分小さくなる。
dq_map で言えば 252 マス × 最大 20 個 → 海のマスぶんだけに落ちる。

### 予算の網（API に依らない・同時に入れる）

`App.renderFrame`（`App.flix:1271`）で、組み上がった動的 PlacedItem の数が R3 を超えたら
**初回 1 回だけ** `Log.warn`。ドット絵の box 列でも 1 マス 1 quad でも Fx の count でも
Terrain でも、同じ 1 つの網に掛かる。`.claude/rules/error-handling.md` の
「毎フレーム通る経路では出さない・名前ごとに初回 1 回だけ」に乗る。

### 5 つの問いへの答え

1. **ゲームは何を渡すか** → key・sheet・rows・tileSize・origin・zIndex・layers。動くマスの
   申告は不要（`frameAt` が None を返せばその段を敷かないだけ）
2. **静的側の key** → ゲームが盤の id を渡す。Doc の読み直しはエンジンが見る（既存の仕組み）
3. **`baked#side` をどう渡すか** → `Sheet` が持つ。World の持ち物は 4 → 1
4. **headless との一致** → `TileScene.toItems`（`TileScene.flix:30`）に `layersOf` の出力を
   そのまま渡す。GPU と CPU が同じ Spec から派生する既存の担保に乗る
5. **予算の検出** → 同時に入れる（上）

### テンプレ反映（根本が入った後）

- **game-starter に「陸は静的タイル層・動く物だけ動的」の見本を置く**（既定テンプレであり、
  reference の拘束が無い）
- novel / rpg のキャラの box 列を quad へ（reference 作り直し: novel 3 枚・rpg 6 枚）
- `module-index.md` の逆引きを「盤を敷く → タイル層」へ向ける

### 保留

- `PxSprite.draw` → `drawBoxes` の改名（値段の見える名前）。Mirror を使うゲームは box 列に
  戻るしかない（`Mirror.flix:2,7`）ので、例外を書き添える必要がある
- dq_map 自体のタイル層への移行

## 4. 根本対応の設計（レビュー通過版）

2026-08-15。批判レビュワー 2 体 × 3 周（1 周目: 設計の穴 / 移行コストと実効性、
2 周目: 同 2 観点で v2 を再査、3 周目: 修正 10 点の閉じ確認）を経て
**致命的ゼロ・要修正ゼロで通過**。§3.5 の「予算の網」を、警告からゲートへ昇格させた物。

### 4.0 実測（設計の根拠。レビュワーが独立検算し全桁一致）

dq_map の代表場面 main を assets（sprite/map json）+ MapTiles のロジックで再構成
（DualGrid.hash 同式・盤外=海 `MapDoc.flix:66`・renderTime=3.0 / wave=0.5）:

- 現行（quad 移行後）: タイル **541**/フレーム — 実機の実測 541 と一致（再現の妥当性の証拠）
- box 列時代: タイル **24,713**/フレーム（`PxSprite.flix:161-181` rowRuns = 横同色 run の
  結合を適用。コマ 1 枚の run 数 min 2 / mean 27.8 / max 105。grass=73 sea1=91
  forest1=80 mountain1=71）+ hero 29〜37
- 比 **45.7 倍**。R3 上限 2000（`docs/performance.md:29`）の **12.4 倍** —
  **硬い上限だけで box 列時代は捕まる**。床タイルのみの最小構成でも ≈18,000（9 倍）。
  コスト重み付けは不要
- 注意: box→quad は画素が同一で SHA が変わらないため、reference-update を経由しない。
  **4.3 の検査経路がこの事故の唯一の門** — だから終了コードの伝播（4.7 の致命修正 1）が生命線

### 4.1 骨子

headless 描き出しの合流点で「動的 item 数」を場面ごとのサイドカーへ常時書き出し、
git 追跡の基準ファイルと 2 段判定（①硬い上限 ②ドリフト）。判定は `make reference-check` と
毎セッションの `make status` の両方に出す。基準の更新（reference-update）自身に予算の門を
置き、無確認の再基準化を塞ぐ。実行時の初回 1 回 Log.warn を併設する。

### 4.2 数える場所 — HeadlessRender の PNG 系 5 変種（engine_tools）

`renderPng / renderPngFonts / renderPngWith / renderPngWithImages / renderPngWithPasses`
（`HeadlessRender.flix:112-287`）で数える。**書き込みの実体は private 1 関数に集約し、
公開変種の委譲では二重に書かない**: renderPngWithPasses は末尾で renderPngWithImages を
同じ name で呼ぶ（`HeadlessRender.flix:291-293`）ので、素朴に「各先頭 1 行」と実装すると
passes 込みの値が本編のみの値で同名上書きされ、pass のぶんを数え落とす形が黙って再発する。実装は
renderPngWithImages の中身を private `renderPngWithImagesCore`（stats を書かない）へ分離し、
renderPngWithPasses は自分で stats（本編 + Σpass）を書いてから Core を呼ぶ。

- 数える量: 本編の drawables + polygons。renderPngWithPasses はさらに
  **Σ(各 PassSpec の drawables + polygons)** を加算（PassSpec は両フィールドを持つ:
  `HeadlessRender.flix:241-246`）。surfaces は本数を参考記録し予算には入れない
- 書き先: `<outDir>/<name>.items.tsv` 1 行 `total=<n>\tpasses=<n>\tsurfaces=<n>`。
  常時オン・env ゲート無し。**書く直前に同 dir の `<name>.static.tsv` を消す**
  （静的層をやめたゲームに前回の申告が残り動的数が過小に出る唯一の非保守経路を塞ぐ。
  このため noteStaticItems は render 呼び出しの**後**に呼ぶのが規約 — doc に明記）
- pub 不変の門: 既存 pub の型・引数・戻り値・PNG の画素は 1 ビットも不変。新 pub は
  noteStaticItems の 1 つ。`docs/performance.md:20-23` の「足すのも変更」は既存 pub 型に
  フィールドを足して形を変える話で、独立した新関数は既存の呼び手から観測できる形を
  何も変えない — §3.5 が既に新 pub（toSheet / PxTilemap）を提案しているのと同じ立場。
  異論があれば着手前に相談へ回す
- ゲーム書き換え: ゼロ（dq_map の `SceneRender.flix:93-95` はそのまま乗る）
- **対象外と明記**: GIF 系（renderGif*、`HeadlessRender.flix:295-390`。reference-check は
  *.png しか照合しない = 元々ゲートの外）と、renderPassImage / renderPassImageWith
  （`HeadlessRender.flix:254-267`）を直接呼ぶ手動合成（BufferedImage に item 数は乗らない）。
  どちらも 4.5 の実行時の網が実機側の受け皿
- 単位の注: 文字は 1 item → 字数ぶんの drawable に膨らむが、glyph は実機でも実クアッドで
  コスト指標として正当。膨らみで既定上限に触れる場面は 4.4 の caps で場面別に逃がす

### 4.3 「動的」の定義と判定

**静的層の投影は「items を渡して数えさせる」。** headless はタイル層・静的層を CPU 投影
（`TileScene.toItems` / withStaticLayer の build）で items に混ぜるため、正しく静的化した
ゲームほど総数が膨らむ。その分を除く:

- 新 pub `HeadlessRender.noteStaticItems(cfg, name, staticItems: List[Render.PlacedItem])` —
  **数値でなく items を受け取り**数えて `<outDir>/<name>.static.tsv` に書く（自由な整数の
  自己申告はできない）。render の後に呼ぶ（順序が逆なら申告が消え動的過大 = 保守側）
- 単位の整合: タイル投影は 1 item = 1 drawable（`TileScene.flix:37-49` は素の Sprite のみ）。
  withStaticLayer の build や Terrain.staticItems 系（例: rpg-starter の terrainShot の
  fill+stroke+粒）は 1:1 の外 — 混ざる分は動的が過大 = 保守側。触れるなら caps で逃がす
- 判定 `動的 = total(+passes) − static`

**判定の実体は `$(ENGINE)/bin/check-render-budget.py`**（reference-check.sh と同居 =
sync-agents 待ちの配布ずれ無し）。`bin/reference-check.sh` の SHA 照合の後に呼ぶ。
**呼び出しは if/else で書き、非 0 を必ず伝播する**（`[ -f ] && python3 ... || echo` は
python3 の exit 1 が `||` に食われ全体 exit 0 になる — ゲートが一度も閉まらない）:

```sh
budget="$(dirname "$0")/check-render-budget.py"
if [ -f "$budget" ]; then
    python3 "$budget" .   # 予算超過なら exit 1 → set -eu で reference-check が落ちる
else
    echo "[budget] check-render-budget.py が無いので予算判定は飛ばします"
fi
```

ロジック（場面ごと）:
① **硬い上限**: 動的 ≥ cap（既定 2000 = R3 から借りた値。reference/ITEMS.caps.tsv で
   場面別上書き・note 必須）→ 赤。**基準ファイルが無くても効く**（導入初日から有効）
② **ドリフト**: 基準があり、動的 > max(基準 × 1.5, 基準 + 200) → 赤。事故は 9〜46 倍の
   桁で来るので誤検知と漏れの間に十分な幅。基準の無い場面（新名・改名後）は ① のみ
③ sanity: static > total → 赤・items.tsv 無しの static.tsv → 赤（残骸か順序違反）

サイドカー欠け（古い engine で生成した gallery）は「予算: 未計測」の 1 行（黙らせない・
落としもしない）。基準 ITEMS.tsv 無しは ① のみ判定 + 作成の促し。
**status にも出す**: agents-pack の bin/status.py に予算の節を追加 — 最後に生成した
gallery/*.items.tsv と reference/ITEMS.tsv を check-render-budget.py の subprocess 呼びで
照合（二重実装しない）。render はしない（SHA 節と同じ「最後に生成した gallery」を見る流儀）。
engine リポ自身では既存節と同様にスキップ（`status.py:172-173` の流儀）。

### 4.4 記録と更新 — 生成物と手書きを分ける・update に門を置く

- `reference/ITEMS.tsv`（**生成物**・git 追跡）: `場面名\tdynamic=<n>\tstatic=<n>`。
  reference-update.sh が作り直す。**行にするのは gallery/*.png の名前集合にある場面だけ**
  （改名で残ったゴースト tsv・silhouette の `*_sil` 残骸を基準に混ぜない）
- `reference/ITEMS.caps.tsv`（**手書き**・git 追跡・再生成の対象外）: 場面別 cap 上書き。
  書式 `場面名\tcap=<n>\tnote=<理由>`（note 欠けは check が赤）。update で消えない
- **reference-update の門**（`reference-update.sh` の **cp/SHA 書き込みより前**に判定 —
  拒否時に PNG/SHA だけ更新された割れた状態を作らない。実装は
  `check-render-budget.py --gate 旧ITEMS.tsv` を呼ぶ形で判定ロジックを一本化）:
  (a) 新しい動的数が cap 超の場面 → **拒否**（上限超の値は基準として書き出せない —
      box 列が初回実装でも基準にする所で止まる）
  (b) 旧基準からドリフト閾値超の増加 → 増加表を出して**拒否**。通すには
      `make reference-update BUDGET=accept` と明示する（GNU make はコマンドライン変数を
      recipe の環境へエクスポートするので reference-update.sh に届く — make 4.4.1 で実測。
      ゲーム Makefile の書き換えゼロ。エラーメッセージにこのコマンドをそのまま出す）
- git の非対称との整合: reference/*.png は git 外・SHA256SUMS.txt は git 内（dq_map の
  .gitignore で確認済み）。ITEMS.tsv / ITEMS.caps.tsv は git 内 = clone 直後でも判定できる

### 4.5 実行時の網（併設）

App.renderFrame（`App.flix:1271-`）で、本編 items + passes の items（`App.flix:1286` の
itemsForGlyphs と同じ量）の長さが cap を超えたら**初回 1 回だけ** Log.warn（private・
~10 行）。headless の代表フレームに無い瞬間（Fx の最悪化・遷移スパイク・GIF でしか
生成しない場面・renderPassImage 直呼びの pass）を実機側で拾う最後の網。

### 4.6 7 つの問いへの答え

1. **数える場所**: HeadlessRender の PNG 系 5 変種。書き込み実体は private 1 関数に集約し
   委譲では書かない。ゲーム書き換えゼロ。既存 pub 不変・新規 pub は noteStaticItems のみ
2. **動的の定義**: total(+passes) − static。static は items を渡して関数が数える。
   render 後に呼ぶ規約 + 残骸掃除 + sanity 2 本で、非保守側に倒れる経路を塞いだ
3. **1 フレームの罠**: 認めて明記。renderTime 固定の代表フレームで、Fx 最悪化・スパイクは
   4.5 の実行時 warn が拾う。「絵が代表フレームで検査できるなら予算も同じ」前提に立つ
4. **閾値**: 硬 2000（借りた既定値 — `docs/performance.md:43-46` の「絶対視しない」に従い
   caps で場面別上書き・note 必須）/ ドリフト max(×1.5, +200)。更新 = reference-update
   だが cap 超は拒否・ドリフト超は BUDGET=accept の明示が必須
5. **置き場**: reference/ITEMS.tsv（生成・git 内）+ ITEMS.caps.tsv（手書き・git 内）。
   既存の「PNG は git 外・一覧は git 内」の非対称と同型
6. **box 列時代を捕まえたか**: **捕まえた。24,713/フレーム（独立検算一致）で上限 2000 の
   12.4 倍・現行比 45.7 倍。** 初回実装として基準化しようとしても update の門が拒否。
   コスト重み付け等の追加装置は不要
7. **実行時の網**: 併設する（4.5。passes 込みで数える）

### 4.7 レビューで落ちて直した点（3 周・抜粋）

1 周目（v1 → v2、致命 4 + 要修正 8 + 軽微）:
- [致命] cap の手書き例外が update の全量再生成で消える → 手書きを ITEMS.caps.tsv に分離
- [致命] pass へ items を移すと数え落とす → passes 分を加算・実行時 warn も passes 込み
- [致命] 「毎セッションの status で走る」が偽（status.py は reference-check を呼ばない）
  → status.py に予算の節を追加
- [致命] reference-update が絵の SHA 更新に相乗りして基準を無確認で上書き（ドリフト自壊）
  → update に門（cap 超は拒否・ドリフト超は BUDGET=accept 必須）
- [要修正] GIF 系対象外の未明記 / 整数の自己申告 / PlacedItem と drawable の単位混在 /
  withStaticLayer の欠落 / R3=2000 の絶対視 / fail-open の恒久スキップ（check を engine/bin
  へ）/ 頻度事故は捕まらない事の明記 / ゴースト tsv → いずれも v2 で対応

2 周目（v2 → v3、致命 1 + 要修正 7 + 軽微 4）:
- [致命] check 呼び出しの `[ -f ] && python3 ... || echo` が予算の赤（exit 1）を握り潰し
  exit 0 — ゲートが一度も閉まらない → if/else で非 0 を伝播
- [要修正] renderPngWithPasses → renderPngWithImages の同名委譲でサイドカーが上書きされ
  pass のぶんを数え落とす形が再発 → 書き込みを private 実体に集約・委譲では書かない
- [要修正] 古い static.tsv の残骸が動的数を過小に（唯一の非保守経路）→ render 時に削除 +
  呼び順の規約 + sanity
- [要修正] renderPassImage 直呼び経路 / pub 追加の扱い / 門の位置（cp より前）と --gate での
  一本化 / 未 sync ゲームの status 沈黙の明記 → いずれも v3 で対応
- [軽微] caps 濫用の明記 / 改名+悪化の規則 / status.py 見積り / rpg-starter terrainShot の
  棚卸し → v3 で対応

3 周目: **致命的ゼロ・要修正ゼロで通過**。軽微 1（BUDGET の理由づけの事実誤認 —
GNU make はコマンドライン変数を recipe 環境へエクスポートする。実測で確認し訂正済み）。
シェル断片の exit 伝播（set -eu 下の if-then 内の失敗は落ちる）も実験で確認された。

### 4.8 実装手順（ファイルと差分の見積り）

| 順 | ファイル | 差分 |
|---|---|---|
| 1 | engine_tools/src/HeadlessRender.flix | +~55 行（writeItemStats + Core 分離 + noteStaticItems + static 残骸掃除） |
| 2 | bin/check-render-budget.py（engine/bin・新規） | ~150 行（--gate モード込み） |
| 3 | bin/reference-check.sh | +~7 行（if/else・非 0 伝播） |
| 4 | bin/reference-update.sh | +~12 行（ITEMS.tsv 生成 = PNG 名前集合限定・--gate を cp より前に） |
| 5 | agents-pack の status.py | +~40 行（予算の節・engine リポではスキップ） |
| 6 | engine_world/src/App.flix | +~10 行（renderFrame 初回 warn・passes 込み） |
| 7 | docs/performance.md / module-index.md | 各 +数行（検出器の存在と更新手順） |
| — | 各ゲーム | 書き換えゼロ（タイル/静的層ゲームのみ noteStaticItems 1 行） |

**実効化の条件（最大の移行コスト）**: engine-upgrade で check 側が効き、**sync-agents が
済むまで status 側は沈黙する**（旧 status.py には節が無い — 「未計測 1 行」すら出ない）。
**導入手順に棚卸しを含める**: 全テンプレ + 手元ゲームで render-all を焼き、実測が既定
cap 2000 を超える場面（候補: rpg-starter terrainShot の粒）は caps.tsv を初期投入してから
門を有効化する — さもないと導入初日にテンプレ自身が update の門で詰む。
導入初日は基準が無いが、硬い上限①は基準無しで即効く。

### 4.9 この設計が防げない事（正直に）

- **個数が増えない「構築頻度」の事故**: 毎フレーム同じ 541 個を組み直しても個数は同じで
  見えない（今の dq_map の 1 マス 1 quad ループがこれ）。R3 予算が個数で定義されている
  以上この検出器の範囲外 — 頻度・時間は bench の背中合わせなど別の検出器の仕事
  （§3.5 の PxTilemap 側がこの形を根絶する担当）
- 2000 未満の緩やかな悪化のうち BUDGET=accept を明示された物
- **caps.tsv の濫用**: note の中身は機械が裁けない — cap=30000 と理由を書けば門は開く。
  BUDGET=accept と同格の「明示した迂回」で、git 差分に残ることだけが抑止
- 動的な物を noteStaticItems へ意図的に渡す虚偽申告（sanity static≤total までしか裁けない）
- GIF でしか生成しない場面・renderPassImage 直呼びの手動合成・headless に乗らないゲーム
  （view=None）— 実行時 warn のみ
- シェーダー面の画素コスト・大きな polygon 1 枚のような「1 item の重さ」
- Fx の最悪フレームが実機でも cap 未満に収まる範囲の悪化

---

## 5. 実装の記録（2026-08-15・7 手順すべて完了）

| 順 | 実物 | 確かめ方 |
|---|---|---|
| 1 | `engine_tools/src/HeadlessRender.flix` の `writeItemStats` / `noteStaticItems` / Core 分離 | flix check 緑・生成すると `gallery/<場面>.items.tsv` が出る |
| 2 | `bin/check-render-budget.py`（`--gate` / `--brief`） | 下の「赤の実測」 |
| 3 | `bin/reference-check.sh`（if/else で非 0 を伝播） | cap を下げると exit 2 で make が止まる |
| 4 | `bin/reference-update.sh`（門を cp より前・ITEMS.tsv 生成） | race / tetris で基準を作成 |
| 5 | `bin/status.py` の `section_budget`（engine リポではスキップ・`--brief`） | 緑「budget OK: 5 場面」／赤 2 行を実測 |
| 6 | `engine_world/src/App.flix` の `warnOverBudget` + `LoopState#budgetWarned` | flix check 緑（rpg-starter の make check も緑） |
| 7 | `docs/performance.md §9` / `docs/module-index.md` の症状 2 行 | check-docs-sync 緑（api-digest 作り直し込み） |

**赤の実測**: tetris-starter に `s4_over cap=100` を一時的に置くと
`s4_over: 動的 564 個 ≥ 上限 100 個` で exit 2、make が停止（設計の唯一の急所だった
「門が一度も閉まらない」配線が閉まることを実物で確認）。

### 棚卸しの結果（全テンプレを生成した）

| テンプレ | 結果 |
|---|---|
| game-starter | 描き出し無し（gallery が空）= 判定の対象外 |
| novel-starter 3 / platformer-starter 4 / tetris-starter 5 | 緑 |
| rpg-starter `terrain_grain` | 2398 個で赤 → **noteStaticItems で申告**（静的 2283 / 動的 115）。テンプレ側の実使用例も兼ねる |
| race-starter `s1_drift` | 2218 個で赤 → **caps.tsv で cap=3000**（擬似 3D の道は毎フレーム形が変わり、タイル層にも静的層にも載らない） |

基準（ITEMS.tsv）を生成したのは **race-starter と tetris-starter だけ**。
novel / platformer / rpg は**この作業と無関係に PNG のリファレンスが古い**
（engine の絵まわりの変更は 08-14〜08-15、それらの SHA256SUMS.txt は 08-13 で止まっている）。
`reference-update` を通すと未確認の画素の上に基準を作り直すことになるので触っていない。
**先に人が絵を見て reference-update してから、ITEMS.tsv を作る。**
硬い上限①は基準が無くても効くので、この間も検出器は生きている。

### 手元のゲームへ効かせるのに残っていること

dq_map の `ENGINE` は Studio 同梱の engine（`/Applications/Flix GE Studio.app/…`）を指すので、
`make engine-upgrade` は「既に v0.24.1」と言って何もしない。**Studio リポで `make swap-engine`
を通すまで、手元ゲーム側では items.tsv が出ない**（= status の予算の節も沈黙する）。
.app の差し替えと再署名なので、人が実行する。

---

## 6. テンプレの box 列 → quad（2026-08-15）

実機 View の 3 本を「生成したアトラスから 1 コマ = 1 クアッド」へ移した。
描き出しスクリプト（各 `render/SceneRender.flix` のコンタクトシート）は box のまま —
N が小さく毎フレームでもないので、そこは box が正しい。

| テンプレ | 触った所 | 画素 |
|---|---|---|
| game-starter | World（atlas / atlasKey / bakedOf）・View.hero・Main.withSpriteAtlases・SceneRender（withAtlasOf で texInfo） | **バイト一致**（make new-game で実体化して確認。item 67 → 47） |
| novel-starter | 同上（額縁 frame） | **バイト一致**（3 場面） |
| rpg-starter | 人と物の 2 枚目のアトラス（charAtlas / bakeCharAtlas / "chars"）・spriteAt・Main・headless 6 か所 | 7 場面中 6 枚が一致。**door.png だけ 12 画素**（下記） |

配線は 4 か所で 1 組（新しいゲームもこの形で写す）:
World が生成して持つ → Main が `withSpriteAtlases` で GPU へ上げる → View が `drawQuad` で貼る →
headless が `PxSpriteAtlas.asImages` + `HeadlessRender.imagePngs` + `Render.drawWith(texInfo,…)` で
同じ絵を PNG から貼る。アトラスの PNG は **debug/ に固定**して落とす（gallery/ に落とすと
絵の顔ぶれを突き合わせる reference-check が「増えた絵」で落ちる）。

### 残った差（engine 側の宿題。今回は直していない）

rpg-starter `door.png` の **y=0 の 1 行だけ 12 画素**が box 列と食い違う
（box は輪郭の濃色 38,33,44 / quad はその 1 つ下の行の色 182,175,173）。
画面の上端で切れるスプライトが、クアッドだと縦のテクセルを 1 つ取り違える形。
`PxSprite.drawQuad` の doc は「box 列と同じ画素を被覆する」と約束しているので、
**約束の側が破れている**（SoftRaster の切り取り位置の丸め）。見た目には出ない 12 画素だが、
バイト比較のスナップショットには出る。GL 実機側でも同じかは未確認。
