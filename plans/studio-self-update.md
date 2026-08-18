# Studio の self-update と、エンジン追随プロンプトの生成

2026-08-19 計画（v3・敵対レビュー 2 巡反映）。未着手。

方針: **人の手をなるべく入れない。** 毎リリース人が書く物は作らない。
人が押すのは 1 ボタンだけにする。**黙って嘘をつく形（無言の 0 終了・無言のスキップ）は作らない。**

---

## 前提の実測（v1〜v2で崩れた物・確かめた物）

| 主張 | 実際 | 出典 |
|---|---|---|
| `.app` の中は署名で触れない | 誤り。アドホック署名。`make swap-engine` が既に差し替えている | `codesign -dv`・`flix_ge_studio/Makefile:112-125` |
| `apireleased` の骨で差分が取れる | 誤り。1 行しか見ず `Sprite` の `loop`→`clips` は原理的に出ない | `apireleased.go:41-43` |
| リリース zip = 同梱の木 | 誤り。`bin/flix` が別物・`lib/external` と `lib/cache` が zip に無い | `stage-engine.json:125-132`・実測 |
| internet_dungeon で追随の検証ができる | **半分誤り。** 追随コミット `37a24c3` は src/ 変更ゼロ＝正解のエラー集合が空 | `git show --stat` |
| 1〜3 の追随は実装済み | 正しい。`make upgrade-game` がある | `Makefile:931-952` |
| `api-digest --root/--out` で任意の木に当てられる | 正しい | `apidigest.go` 冒頭 |

---

## エンジンを 1 段上げるとゲームに起きること

| # | やること | 今の状態 |
|---|---|---|
| 1 | `flix.toml` の依存の version 行 | `upgrade-game` が済ませる |
| 2 | `lib/` へ新しい fpkg を種付け | 同上 |
| 3 | agents-pack の再配布 | 同上 |
| 4 | **壊れた API への追随**（`Sprite` の `loop` → `clips`） | **無い。ここを作る** |
| 5 | `reference/` の焼き直し | 判断が要る（4 の後） |

---

# A. 追随の材料を、リリース時に engine 側で焼く

**肝**: 材料を作れるのは engine のリポの中だけ（git の履歴と全ソースがある）。
ゲーム側・Studio 同梱の木には `.git` が無い。だからリリースの流れで焼いて配る。
ゲーム側は読むだけ。

## A1. `fge api-diff --from <ver> --to <ver>`

**md を diff しない。`flixdecl.ScanPackage` を両方の木へ直接当て、構造で比べる。**
（md の行比較だと doc コメントの書き直しが全部「変わった」に化ける・
`pub def draw` が 2 つある現状で取り違える）

- キーは (パッケージ, mod, 宣言名)。doc コメントは比較から外す
- type alias / enum は中身を浅く割り、**フィールド・variant の増減**まで出す。
  純追加（variant 追加・フィールド追加）は「壊さない変更」の別の棚に出す
  — update-plan に偽陽性の「直す物」を積まないため
- バージョンの木は **`git archive <tag> engine/src engine_world/src engine_tools/src docs/*.json | tar -x`**
  の部分展開（worktree は `.git/worktrees/` に残骸とロックが残る。archive は読み取り専用・
  掃除はテンポラリ 1 個）。展開先はスクラッチに置き、必ず消す
- **from の決め方**: 先に `git fetch --tags origin` を必須にする（この clone のローカルタグは
  v0.25.0 止まりで、fetch 無しだと 6 バージョン分を「1 つ前」と誤認する）。
  from = sort -V で VERSION 未満の最大タグ。**候補ゼロなら大声で失敗**
  （初リリースだけ `--from none` を明示させる）。タグが引けないのに 0 終了は作らない
- 出力は `--json` も出す（Studio と CI が読む）
- **render_gl は対象外**（ゲームが直接呼ばない前提。api-diff に出ないことを明記）
- `docs/*.schema.json` の差分も出す。ただし schema は fx / sprite / ui の 3 枚しか無いので、
  **schema の無い Doc 種（shader ほか）は診られない**と生成物に明記する（網があると思わせない）

## A2. `make bump` が `docs/migrations/<version>.auto.md` を焼く

**release の中ではなく bump の中。** release の途中で焼くと、未コミットの生成物が
zip にだけ入り**タグの木に入らない**（後から `git archive v0.31.0` しても存在しない）。
bump は既に api-digest を再生成してコミット対象に載せているので、同じ棚に乗せる。
release-guard には `api-digest --check` と同型の「焼き直して一致するか」を足し、
bump 後に API を触るコミットが入ったら止める。

中身は 2 つ。**どちらも機械が作る。人は書かない。**

1. **A1 の差分**（1 つ前のリリースとの 2 点比較）
2. **engine 自身の追随の実物** — `git log -p v<前>..v<今> -- templates/ examples/ bench/` から、
   A1 の名前で絞った hunk

### 絞りの規則（`draw` のような一般語で溺れないため）

- **def / enum / eff**: `\bMod名.名前\b` の**修飾付き完全一致だけ**。裸の名前では拾わない
- **レコードのフィールド**（`loop` の類）: `loop =` の字面か、alias 名（`Sprite`）が
  同じ hunk に居ることを必須条件にする
- **当たらなすぎの補完**: このリポは非互換と追随を同じコミットに入れる習慣があるので、
  「engine*/src と templates/ を**両方**触ったコミットの templates 側 diff」を候補に足す
- 1 名前あたりの量に上限。超えたら「代表 1 件＋コミット ID 一覧」に落とす
- それでもゼロ件なら「**追随例がありません。手当ては自分で考えてください**」と正直に書く

リリースは止めない。ただし無言にもしない — `make release` の出力の最後に
「追随例の無い非互換 N 件（.auto.md 参照）」と 1 行出す。
手で足したいときのために `docs/migrations/<version>.md` が有れば連結する逃げ道だけ残す。

## A3. 配る物は「バージョンごとの api-digest スナップショット（JSON）」

`.auto.md` の**連結で跨ぎを済ませる案は捨てる**。A→B で `loop`→`clips`、
B→C で `clips`→`animations` と改名が連鎖すると、連結を読んだエージェントは
**一度死んだ中間状態へ直してしまう**。

- 同梱の木に入れるのは ①各バージョンの宣言スナップショット（JSON・schema のバージョン付き）
  ②各バージョンの `.auto.md`（追随例の器として）
- **API 差分は常に from→to の 2 点比較**をその場で取る（from = ゲームの flix.toml の現在値）
- スナップショットの schema バージョンが合わない古い物は、ソース木からの再生成へフォールバック
- 跨ぎの追随例は、名前ごとに**最新バージョンの hunk だけ**残し、古い物は
  「後のバージョンでさらに変わっています」と印を付ける
- 材料の置き場は同梱エンジン 1 か所（ゲームの lib/ へは写さない — 二重管理を作らない）。
  同梱物は `bin/lint-rules/stage-engine.json` へ足して 28 点照合に乗せる

---

# B. `fge update-plan --game DIR`

A の材料を読み、**ゲームのソースへ grep して当たる物だけに絞って** markdown を吐く。
grep の規則は A2 と同じ物を使う。

```
# engine 0.28.0 → 0.31.0 への追随

## 済んだこと（upgrade-game が実行済み）
- flix.toml / lib/

## 直す物（このゲームで当たる非互換 3 件）
### 1. PxSpriteDoc.Sprite の中身が変わった
- 前: { anchor, frames, loop = Loop }
- 後: { anchor, frames, clips = Map[String, Clip] }
- 当たる場所: test/TestPieceAtlas.flix:11, src/World.flix:203
- engine 自身はこう直した: <templates/rpg-starter の実際の diff>

## 壊さない変更（読むだけでよい）
## 診られない物（schema の無い Doc 種: shader ほか）
## 確かめ方
make check → make test → make reference-check
```

**自動で直しにはいかない。** 機械置換は当たり所を読み違えたときに黙って壊す。
直すのはエージェントの仕事に残す。

---

# C. `upgrade-game` の組み替えと巻き戻し

## 順番を変える（退避を増やすのではなく）

今は `toml+lib → sync-agents → check`。これだと巻き戻し対象に agents-pack 一式
（`bin/fge` 本体・skills・lint-rules。copyDirs は**消す方向にも**書くミラー）が入ってしまう。

→ **`toml+lib → check → 緑なら sync-agents`** に組み替える。
巻き戻し対象は本当に 3 ファイルで済む。

## 赤の意味を 2 つに分ける（自動巻き戻しは本命フローを殺さない形で）

非互換のあるバージョン上げでは、エージェントが直すまで check は**必ず赤**。
「赤なら戻す」を一律に入れると、本命のバージョン上げが永遠に完了できない。

- update-plan が「当たる非互換 **0 件**」なのに赤 → 想定外。**自動で戻して**「上がりませんでした」
- 当たる非互換 **N 件**で赤 → **正常系**。新バージョンのまま update-plan を出して
  「エージェントに直させてください」で終わる
- `reference-check` は check が緑のときだけ回し、「絵が変わった / 変わっていない」の
  1 行を update-plan に載せる

---

# D. Studio の self-update

`make swap-engine` が既にやっている「`.app` の中の engine を差し替える」を、
Studio 自身が走らせる。**主語は editor_server（JVM）**
— 同梱 JRE で HTTPS が引ける・Progress の口が既にある・止める物を自分が知っている。
（ランチャー main.rs は起動と道連れ kill しか持っていない）

## D0. 差し替え前の検査と停止（ここがv2に無かった穴）

1. **残骸掃除**: 前回の `engine.old` / `engine.new` が残っていたら先に消す
   （残ったままだと rename が ENOTEMPTY で**永久に更新できなくなる**）
2. **書けるか検査**: 自分の `Resources/` 直下に touch できるか。書けなければ
   （App Translocation の読み取り専用マウント・/Applications の権限）更新を諦め、
   「Finder で一度移動してから開き直す / アプリごと入れ直し」の案内へ倒す
3. **空き容量検査**（zip 40MB＋展開 100MB 超）
4. **止める物 3 種**:
   - 走行中のゲームプロセス（`list_running_games`）→ 停止を促す
   - **checkd の常駐 repl** — headless なのでゲーム一覧に映らない。古い flix.jar の
     inode を掴んだまま「古いコンパイラで新しい規約を判定する」新旧混在になる。殺して、
     更新後の初回保存で立ち直らせる
   - server 自身のタスク受付（Runner / BakeHost / new-game）を更新中は塞ぐ

## D1. 差し替えの手順

1. バージョンの確認は GitHub API 1 回（ETag 付き条件付き GET・1 日 1 回。未認証 60 回/h を枯らさない）。
   ダウンロードは **タグ固定の `browser_download_url`**（latest だと表示したバージョンと落ちるバージョンがずれ得る）
2. zip と **`SHA256SUMS.txt`** を落として照合。
   **SHA256SUMS.txt は `make bundle-zip` が焼いてリリースへ添付する**（今は存在しない。
   作らないと「照合」は実装時に無言のスキップへ退化する）
3. `Contents/Resources/engine.new/` へ展開
4. **持ち越し**: 今の木から写す。一覧は手で持たず、**`stage-engine.json` から導出**する
   — 「src が `@` 始まり（外から来る物）かつ bundle-zip が引数で渡さない物」＝持ち越し対象。
   現時点で `bin/flix`（`../jre` を見るラッパ）・`lib/external`・**`lib/cache`**（v2は
   これを列挙から漏らしていた — 列挙は必ず漏れる、の実証）。
   組み立て後の照合に「`bin/flix` の中身が `../jre` を見るラッパか」の**中身検査**も足す
   （存在照合だけでは devbox ラッパの上書き忘れを拾えない）
5. **世代ゲート**: zip の中に「要求する Studio 側部品（ラッパ / JRE モジュール）の世代番号」を
   1 行入れておき、自分の持ち物が満たさなければ差し替えを**拒んで**「アプリごと入れ直し」へ倒す
   — ラッパと JRE の source of truth は Studio リポ側にあり、engine の self-update では更新できないため
6. `engine` → `engine.old`、`engine.new` → `engine` の **rename 2 回**。
   間に窓があるので、**ランチャー起動時に「engine が無く engine.old が有る」を検出したら
   戻す修復**を入れる（数行）。「不可分」とは言わない
7. **`codesign` は打たない。** 走行中の自分の実行ファイルの署名を書き換えると以後の
   ページインで SIGKILL され得る。アドホック署名で実行ファイル未変更なら起動は通る。
   打つなら「再起動の案内 → 再起動の直前」に順序を変える
8. `engine.old` と zip を消す。更新完了イベントで Elm にバージョン表示とテンプレ一覧を読み直させる

戻したいときは 1 つ前のリリース zip を指定して同じ手順（別の仕組みは作らない）。
/Applications と ~/Applications の両方に入っている場合、上がるのは自分の実パスの方だけ
（その旨を表示に 1 行）。

## D2. ゲーム側への接続

- 押した後: 開いているゲームに `upgrade-game` → update-plan。呼ぶときは
  **`~/.flix_ge_studio/engine` の別名経由**（同梱の木の実パスは空白入りで、
  `FLIX := $(ENGINE)/bin/flix` が千切れる。EngineHome の既存経路に乗せる）
- 開いていない 10 リポへは新しい配線を作らない — **`bin/fge status` の
  「engine バージョンズレ」表示が同梱 engine 更新直後に必ず点く**ことを検証に入れる。
  status は全ゲーム配線済みなので、次に触った瞬間に案内が出る
- checkd はバージョンズレを見たら自ら再起動する（か「再起動して」と言う）1 行を足す
- エンジンだけ上がってゲームが古い期間、`make check` は古い fpkg で普通に緑
  （flix.toml のバージョンで解決するので嘘ではない）。案内は status の仕事とする

## D3. Windows

`ci/package-windows.ps1` が別の木を組む（bash ラッパ無し・`fge-go.exe`）。mac 機の
`make release` の zip は Windows 向けにならない。**第 1 段では作らない** —
帯で「新しいバージョンが出ています」＋アプリごと入れ直しの案内だけ。
作るなら CI の windows ジョブで engine zip も焼く形。

## D4. UI

「engine 0.31.0 → 0.32.0 が出ています」＋ボタン 1 つ。進み具合は `Progress.elm`。
**開いた瞬間に自動で上げない** — バージョン上げは絵と挙動まで変わる「人が選ぶ側」の変更
（`upgrade-game` のコメントの明文）。人が押すのはこの 1 回だけ。

---

# 検証（機械判定）

1. **正解データは templates/ で作る**（internet_dungeon は追随コミットに src/ 変更ゼロ＝正解が空）:
   templates を v_from の状態で `git archive` から取り出し、v_to のエンジンで `make check`。
   **出たエラーの名前一覧**が正解。update-plan の出力がそれを覆っているか比べる（偽陰性の検査）。
   .git のあるリリース側で毎回機械的に作れるので、**リリースの常設ゲート**にできる
2. internet_dungeon は「非互換ゼロのバージョン跨ぎで update-plan が『直す物なし』と正しく言う」
   **陰性の検査**として使う
3. self-update は「壊した zip を食わせて engine が無傷で残る」「rename の窓で殺して
   起動時修復が効く」を必ず通す
4. コンパイルが通って実行時に静かに壊れる類（Doc のフィールド名）は 1 では拾えない。
   schema 差分（3 枚ぶん）で拾い、**診られない Doc 種は診られないと言う**

---

# 順番と見積もり（実績ベースの日数）

| 段階 | 中身 | 日数 | 人の手 |
|---|---|---|---|
| 1 | A1 `fge api-diff`（flixdecl 直・archive 部分展開・fetch --tags） | 2 | 0 |
| 2 | A2〜A3（bump で焼く・絞り規則・スナップショット JSON・28 点照合へ） | 1.5 | 0 |
| 3 | B `update-plan` ＋ templates 正解データの機械検証 | 1.5 | 0 |
| 4 | C `upgrade-game` の順番組み替え＋条件付き巻き戻し | 0.5 | 0 |
| 5 | D0〜D1 Studio の差し替え（mac のみ・SHA256SUMS を先に） | 1.5 | 0 |
| 6 | D2・D4 UI と接続 | 1 | ボタン 1 回 |

段階 1〜4 でターミナルから打つ道具として完結する。段階 5〜6 は Studio の皮。

---

# 残る人の手（これ以上は減らせないと判断した所）

1. **更新ボタンを押す**（D4）— 自動追随は絵と挙動が変わるので危ない
2. **エージェントが直した後の確認**（`make test` と `reference-check` を見る）
   — 絵の良し悪しは機械では決められない
3. **engine 内で誰も使っていない API を壊したときだけ**、`docs/migrations/<version>.md` を
   手で書く — 稀。書かなくてもリリースは通り、release の出力に件数が出て、
   生成物に「追随例がありません」と出る

---

# 相談したい点

1. `fge` に 2 コマンド（`api-diff` / `update-plan`）。flixdecl 直叩きにしたので
   apidigest の md 生成（既存ゲートの source of truth）は無傷で済む
2. 「追随例が無い非互換」でリリースを止めない＋release の出力に件数を出す、の対でよいか
3. Windows の self-update を第 1 段で切ってよいか
4. 世代ゲート（D1-5）の番号を stage-engine.json に置く形でよいか
