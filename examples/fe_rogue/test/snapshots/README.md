# スナップショット（UI 目視カタログ）

UI の見た目を **カタログ駆動のマルチページ HTML サイト**で目視確認する仕組み。静止画（PNG・golden つき）と
操作フロー（GIF）を、**ゲーム機能単位**（コマンドメニュー・タイトル画面・持ち物…）のページに分けて
`index.html` から回遊できる。1 機能ページの中はさらに「基本状態 → エッジケース → 操作フロー」の 3 節に
分かれ、`tag_<tag>.html` でタグ単位に機能横断で見ることもできる。

## 生成と閲覧

```sh
# 静止画 PNG + サイトを生成（golden 比較つき）。既存の GIF（あれば）もページに載る。
flix test

# GIF を再生成（test/snapshots/gifs/ を上書き・golden 更新モード）
FE_ROGUE_SNAPSHOT_GIF=1 FE_ROGUE_SNAPSHOT_UPDATE=1 flix test
```

GIF は PNG と違って毎回焼き直すには重いので、`test/snapshots/gifs/`（コミット対象）に生成物を
置く。素の `flix test` では再生成しないが、そこにある GIF は毎回 `build/snapshots/` へコピーされて
ページに表示される（`SnapshotSupport.syncGifs`）。クリーンビルドで `build/` を消しても、次の
`flix test` でコピーが復元するので画面から消えない。`FE_ROGUE_SNAPSHOT_GIF=1` のときだけ
`test/snapshots/gifs/` 側を上書き生成する。

出力は `build/snapshots/`（.gitignore・閲覧用の使い捨て）:

- `index.html` … ハブ。ゲーム機能ごとに「代表サムネ + 件数 + 説明」のカードが並ぶ（末尾にタグ目次）。
- `page_<scenario>.html` … 機能別ギャラリー。パンくず（← index）＋前後機能導線つき。ページ内は
  「基本状態 → エッジケース → 操作フロー」の 3 節（節の判定は `SnapshotSite.sectionOf`。ext が
  `"gif"` なら操作フロー、タグに `"edge-case"` を含めばエッジケース、それ以外は基本状態）。
  各項目は名前のコード表記（クリックでコピー）＋説明＋タグ（クリックでタグページへ）＋画像。
  GIF が `test/snapshots/gifs/` にも無ければ生成コマンドの案内が出る。
- `tag_<tag>.html` … あるタグを持つ項目をゲーム機能横断で並べたページ（← index パンくずのみ）。
  各カードに所属機能ページへの `in <scenario>` リンクが付く。カタログのどのタグも自動でページ化される。
- `<name>.png` … 毎回焼き直す静止画。`<name>.gif` … `test/snapshots/gifs/<name>.gif` からのコピー。
- golden は `test/snapshots/<name>.golden.txt`（コミット対象）。GIF 本体は `test/snapshots/gifs/<name>.gif`
  （同じくコミット対象・「保存する生成資産」扱い）。

## ファイルの役割

| ファイル | 責務 |
|----------|------|
| `SnapshotCatalog.flix` | **目録（純データ）**。全 34 枚の name/desc/kind(Png/Gif)/scenario/tags を宣言。ゲーム側。 |
| `SnapshotSite.flix` | **汎用サイト生成器**。カタログ → HTML 群への変換。ゲーム非依存（Flix 標準 + Fs + java.io.File のみ）。 |
| `SnapshotSupport.flix` | mock Game・テクスチャ表・決定的フォーマット・golden 比較・PNG 焼き・GIF 永続化コピー（`syncGifs`）。 |
| `SnapshotHarness.flix` | フィクスチャ用の effect 束（World/フェーズ/クエリ等）を巻く。 |
| `TestUiSnapshots.flix` | PNG の drive（`driveByName`）と @Test オーケストレータ。サイト設定・Item 変換・毎回の GIF 同期・lint 実行もここ。 |
| `TestGifSnapshots.flix` | GIF の収録（ReplayScript を本物の入力処理で回す）。出力先は `test/snapshots/gifs/`。 |
| `RenderLint.flix` | **幾何リンタ（純データ・ゲーム非依存）**。要素の bbox 列＋親子関係＋画面寸法だけ受け、R1/R2/R3 の破綻を検出。fe_rogue の型を import しない。 |
| `SnapshotLint.flix` | `UiWorld` → `RenderLint.Input` のブリッジ（fe_rogue 依存）。描画経路と同じ算式で各 entity の実描画 bbox・祖先パスを組む。 |

## 分類ガイド（scenario / tags の付け方）

`scenario` は「コマンドメニュー」「持ち物」のような**ゲーム機能単位**で決める。「menus」「hud」
「edge-cases」のような技術的な括りは使わない。目安:

- **新しいゲーム機能を移行したら scenario を 1 つ足す。** 例えば新メニューを追加したら、その専用の
  `scenario` 文字列（kebab-case）を 1 つ起こし、その機能に関する静止画・組み合わせ HUD・GIF を
  すべて同じ `scenario` にぶら下げる。
- 複数 HUD を組み合わせたコンボ（例: TopBar + アクションメニュー）は、独立ページを作らず、最も体感が
  強い機能のページへ合流させる（例は `action-menu` へ）。
- 満載・境界などのエッジケースも独立ページを作らず、同じ機能ページ内に留め、`tags` に必ず
  `"edge-case"` を含める。`SnapshotSite` がこのタグでページ内の節を自動振り分けする。
- 複数機能にまたがる GIF（例: コマンド→アイテムの遷移）は、遷移の起点になる機能を主 `scenario` にし、
  もう一方の機能名を `tags` に足す。これで両方の機能ページから辿れる（主機能側のページ本体＋もう一方は
  `tag_<その機能名>.html` 経由）。
- それ以外のタグ（`"combo"` `"modal"` `"scroll"` `"transition"` など）は自由に付けてよい。タグは
  すべて `tag_<tag>.html` として自動でページ化されるので、増やすほど機能横断の見え方が増える。

## 拡張の仕方

- **スナップショットを 1 枚足す** = `SnapshotCatalog.entries()` に 1 行足す（name/desc/kind/scenario/tags）＋
  `TestUiSnapshots.driveByName` に腕を 1 つと drive 関数を 1 個足す（GIF なら `TestGifSnapshots` に gen 関数を 1 個）。
- **ゲーム機能を 1 つ足す** = 新しい `scenario` 文字列を書くだけ。`SnapshotSite` が自動でページを増やし、
  ハブのカードと前後導線に組み込む。宣言順がそのまま表示順・ページ順・前後導線の順序になる。
- **タグを 1 つ足す** = 既存/新規のエントリの `tags` にタグ文字列を書くだけ。`SnapshotSite` が
  `tag_<tag>.html` を自動生成し、index のタグ目次にも並ぶ。

## RenderLint（描画データの自動破綻検知）

PNG を焼く過程で組み上がる World / レイアウトを、**人間が画像を見て被りに気づく前に幾何データで
検査する**リンタ。各 PNG シーンを撮影した直後、描画に使ったのと同じ `UiWorld` を `SnapshotLint` が
「実際に描かれる外接矩形（bbox）＋名前パス＋祖先関係」の構造レコードへ射影し、`RenderLint.check` が
3 ルールで検査する。**有効な Finding が 1 件でもあれば `flix test` は fail**（メッセージに全詳細）。
検査は読み取りのみで描画・golden には一切影響しない。

粒度は **1 テキスト要素 = 1 bbox**（measure 実寸）。golden の色・z 集約は別ラベルまで融合してしまう
ので lint では使わず、entity 単位で見る。sprite は「実際に描かれる大きさ」（region/texture サイズ ×
scale）で bbox を取る（レイアウトが確保する箱ではなく実描画。アイコン巨大化を拾うため）。

### ルールと閾値

| ルール | 内容 | 閾値（定数・報告文に埋め込み） |
|--------|------|--------------------------------|
| **R1** text×text 交差 | 可視テキスト同士の bbox が**両軸**で重なる（同一シーン内・z 帯問わず。文字が別の文字に被るのは常に不具合）。 | `textOverlapEpsilon = 1.25px`。measure はフォント行間（leading）ぶん実グリフより縦に膨れ、縦積みの隣接行が最大 1.0px 食い合う（＝ノイズ）。実被りは 1.5px 以上重なるので、その谷間に閾値を置く。 |
| **R2** text の親はみ出し | テキスト bbox が、階層上の**直近の box 祖先**（パネル）rect からはみ出す。box 祖先を持たない（パネルと兄弟配置の）テキストは対象外。 | `panelOverflowEpsilon = 1.0px`。角丸・枠線の内側食い込みは誤差として許す。 |
| **R3** 画面外/超過 | 可視要素（box/text/sprite/poly）の bbox が design 画面 240×128 を大きく超える。 | `screenMarginPx = 2.0px`。端に接する HUD の誤検出を避ける。 |

方針は **精度重視・偽陽性を出さない側に倒す**。閾値はすべて `RenderLint` の定数で、報告文にも
`[閾値 Npx]` として出す（調整が透明）。

### 抑制の書き方

意図的な演出重なりは、カタログ `Entry` の `tags` に `"lint-allow:R1"` のように**シーン単位・ルール
単位**で抑制タグを付ける。抑制された Finding は fail させないが**黙殺せず「抑制済み」として別掲**する
（ダッシュボードのバッジに「抑制 N」と出し、詳細にも `[抑制]` 印つきで残す）。例:

```flix
{name = "foo", kind = Kind.Png, scenario = "bar",
 tags = "bar" :: "lint-allow:R1" :: Nil, desc = "..."} ::
```

### ダッシュボード表示

`SnapshotSite.Item` に `lint`（`LintBadge` 構造データ）フィールドを持たせ、各シーンカードにバッジを
出す: 違反なしは `✓ lint`、有効違反ありは `⚠ N`（＋抑制があれば `抑制 N`）。⚠ の詳細は各カード内の
折りたたみ（`<details>`）に全 Finding を並べる。GIF など未検査の項目はバッジを出さない
（`checked=false`）。バッジ描画は `SnapshotSite`（ゲーム非依存）が構造データを見て行うだけ。

### 今日の実バグ群がどのルールで捕まるか

直近の視覚バグはすべて幾何検査で事前検出できる:

- **こううんの被り / 閉じるの被り**（レベルアップのラベル・footer が本文列に食い込む）→ **R1**。
  実証: `LevelUpPanel.ui.json` の `footer` の y を旧値 66 に戻すと、footer が bodyLabels /
  bodyBefore / bodyArrow / bodyAfter と **1.50px 交差**して R1 が 4 件 fail する（現行 y=70 では
  1.50px の谷を越えないので緑）。Stage 4 の意図的破壊テストと同じ流儀で検証済み。
- **GameOver 枠はみ出し**（パネル box が画面外へ）→ **R3**。
- **武器アイコン巨大化**（sprite が実寸で巨大描画）→ **R3**（sprite bbox は実描画サイズで取る）。
- **閉じる等がパネル外へ**（テキストがパネル rect を超える）→ **R2**。
- **z 潜り**に起因する被りも、被った結果の bbox 交差として **R1** で顕在化する。

### 既存シーンの棚卸し（初回導入時）

全 PNG シーンへ lint をかけた初回結果: **実バグはゼロ**。閾値 1.25px 未満の Finding（font leading
由来の縦積み隣接行の 1.0px 以下の食い合い: `log_lines` の 3 行スタック、`battle_panel` の攻/防
予報数値 2 段）はすべてノイズと判定し、閾値でノイズ側に落とした（抑制タグは不要）。R2 / R3 は
既存シーンで違反ゼロ。

## engine 抽出の見立て

`SnapshotSite.flix` はゲーム固有の型を一切 import しない汎用パーツ（入力は構造的な `Item` レコードだけ）なので、
そのまま engine 側の「カタログ → HTML サイト」ユーティリティへ吸い出せる。抽出時に残る作業は、
`Item` 契約（name/desc/scenario/tags/ext/pxWidth/generateHint/lint）と `Config`（outDir/title/cssScale）を
engine の公開 API として据え、ゲーム側は `SnapshotCatalog` のような目録 + アダプタ（`toItems`）を持つだけにする。
`lint`（`LintBadge`）と `RenderLint` も同様にゲーム非依存なので engine 側の汎用リンタとして吸い出せる
（fe_rogue 依存はブリッジの `SnapshotLint` に閉じている）。
