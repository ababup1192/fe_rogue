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
| リリース zip = 同梱しているソース | 誤り。`bin/flix` が別物・`lib/external` と `lib/cache` が zip に無い | `stage-engine.json:125-132`・実測 |
| internet_dungeon で追随の検証ができる | **半分誤り。** 追随コミット `37a24c3` は src/ 変更ゼロ＝正解のエラー集合が空 | `git show --stat` |
| 1〜3 の追随は実装済み | 正しい。`make upgrade-game` がある | `Makefile:931-952` |
| `api-digest --root/--out` で任意のフォルダに当てられる | 正しい | `apidigest.go` 冒頭 |

---

## エンジンを 1 段上げるとゲームに起きること

| # | やること | 今の状態 |
|---|---|---|
| 1 | `flix.toml` の依存の version 行 | `upgrade-game` が済ませる |
| 2 | `lib/` へ新しい fpkg を種付け | 同上 |
| 3 | agents-pack の再配布 | 同上 |
| 4 | **壊れた API への追随**（`Sprite` の `loop` → `clips`） | **無い。ここを作る** |
| 5 | `reference/` の作り直し | 判断が要る（4 の後） |

---

# A. 追随の材料を、リリース時に engine 側で作る

**肝**: 材料を作れるのは engine のリポの中だけ（git の履歴と全ソースがある）。
ゲーム側・Studio が同梱しているソースには `.git` が無い。だからリリースの流れで生成して配る。
ゲーム側は読むだけ。

## A1. `fge api-diff --from <ver> --to <ver>`

**md を diff しない。`flixdecl.ScanPackage` を両方のソースへ直接当て、構造で比べる。**
（md の行比較だと doc コメントの書き直しが全部「変わった」に化ける・
`pub def draw` が 2 つある現状で取り違える）

- キーは (パッケージ, mod, 宣言名)。doc コメントは比較から外す
- type alias / enum は中身を浅く割り、**フィールド・variant の増減**まで出す。
  純追加（variant 追加・フィールド追加）は「壊さない変更」の別の棚に出す
  — update-plan に偽陽性の「直す物」を積まないため
- バージョンごとのソースは **`git archive <tag> engine/src engine_world/src engine_tools/src docs/*.json | tar -x`**
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

## A2. `make bump` が `docs/migrations/<version>.auto.md` を生成する

**release の中ではなく bump の中。** release の途中で生成すると、未コミットの生成物が
zip にだけ入り**タグのソースに入らない**（後から `git archive v0.31.0` しても存在しない）。
bump は既に api-digest を再生成してコミット対象に載せているので、同じ棚に乗せる。
release-guard には `api-digest --check` と同型の「作り直して一致するか」を足し、
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

- 同梱するのは ①各バージョンの宣言スナップショット（JSON・schema のバージョン付き）
  ②各バージョンの `.auto.md`（追随例の器として）
- **API 差分は常に from→to の 2 点比較**をその場で取る（from = ゲームの flix.toml の現在値）
- スナップショットの schema バージョンが合わない古い物は、同梱ソースからの再生成へフォールバック
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

engine を **`.app` の中から外へ出す**。Studio は `~/.flix_ge_studio/engines/<バージョン>/` に
置いた engine を指し、self-update はそこへ新しいフォルダを 1 つ増やして指し先を変えるだけにする。
`.app` は読み取り専用のまま一切触らない。

```
~/.flix_ge_studio/
  engines/
    0.31.0/            今使っている
    0.32.0/            落として展開した物
  engine-current.txt   "0.32.0" の 1 行（指し先）
  engine -> engines/0.32.0   （macOS だけ・空白を含まないパスをゲームへ渡すため）
```

**主語は editor_server（Flix）** — 同梱 JRE で HTTPS が引ける（`java.net.http` と
`jdk.crypto.ec` と cacerts が入っていることを実測済み）・長い仕事を裏で走らせて
進み具合を出す口が既にある（`Runner.launchWork`）・止める物を自分が知っている。

## なぜ外へ出すか（中でやると要る物が、全部要らなくなる）

| `.app` の中でやる場合に要る物 | 外に出した場合 |
|---|---|
| `codesign` の seal（741 ファイル）が古くなる問題 | 無関係（`.app` を触らない） |
| `Resources/` へ書けるかの検査（権限・App Translocation） | 無関係（ホーム配下） |
| `engine` → `engine.old` → `engine.new` の rename 2 回と、その間の窓 | 無し（別フォルダへ展開してから指し先を変える） |
| ランチャー起動時の「engine が無く engine.old が有る」修復 | 無し |
| 前回の残骸（`engine.old` / `engine.new`）の掃除 | `*.partial` を消すだけ |
| 走行中のゲームが掴んでいる engine を消してしまう問題 | 無し（古いバージョンのフォルダを消さない） |
| 持ち越し（`bin/flix`・Maven の種） | **やはり要る** |

**残るのは持ち越しだけ**で、そこは `stage-engine.json` の `owner: "studio"` から導く（D2）。

代わりに受け入れる性質: アプリを消しても engine が残る・手元にバージョンが溜まる
（1 つ前まで残して、それより古いのは消す）。

## D0. 置き場を外に移す（最初の 1 段。self-update より前に効く）

1. **種まき**: `~/.flix_ge_studio/engines/<同梱バージョン>/` が無ければ、`.app` の
   `Contents/Resources/engine` をそこへ写す（`NewGame.copyTree` / `copyFile` と同型。
   **実行ビットを写すこと** — `bin/flix` と `bin/fge-go` が走らなくなる）。
   同梱バージョンは同梱 engine の `Makefile` の `VERSION :=` を読む
   （`NewGame.versionFromMakefile` が既に `pub`）
2. `engine-current.txt` にそのバージョンを書く
3. `EngineHome.dir()` の解決順を **`engine-current.txt` → `EDITOR_ENGINE` → 開発時の既定**
   に変える。ランチャーが渡す `EDITOR_ENGINE`（`.app` の中）は種まきの元としてだけ使う
4. macOS の別名（`EngineHome.linkedAlias`）の指し先を `engines/<バージョン>` に向ける

**指し先を symlink にしないのは Windows のため。** Windows の symlink は管理者権限か
開発者モードが要る。テキスト 1 行なら両 OS で同じに書け、テンプファイル → rename で
不可分に差し替えられる。macOS の別名は**空白を含まないパスをゲームの Makefile へ渡す**
ための物なので、そのまま残す（`FLIX := $(ENGINE)/bin/flix` が空白で千切れる）。

## D1. 差し替えの手順

1. バージョンの確認は GitHub API 1 回（ETag 付き条件付き GET・1 日 1 回。未認証 60 回/h を枯らさない）。
   ダウンロードは **タグ固定の `browser_download_url`**（latest だと表示したバージョンと落ちるバージョンがずれ得る）
2. zip と **`SHA256SUMS.txt`** を落として照合（`make bundle-zip` が作ってリリースへ添付する。
   v0.31.0 の時点ではまだ添付されていないので、実際に動くのは次のリリースから）
3. `engines/<新バージョン>.partial/` へ展開
4. **持ち越し**: 今の `engines/<今のバージョン>/` から写す。一覧は手で持たず、
   **展開した側の `bin/lint-rules/stage-engine.json` から導出**する
   — 新しい engine が「自分は何を運ばないか」を宣言している側だから。
   軸は「その項目の中身をどちらのリポが決めるか」（`owner`）。

   | dest | owner | zip の中身 | 差し替え時 |
   |---|---|---|---|
   | `bin/flix` | **studio** | engine リポの devbox ラッパ（PATH と nix store を探す） | **持ち越す** |
   | `lib/cache` | **studio** | 無し（bundle-zip は `--maven-seed` を渡さない） | **持ち越す** |
   | `lib/external` | **studio** | 無し（同上） | **持ち越す** |
   | `bin/flix.jar` | engine | 有り（33.8 MB） | 上書き |
   | `bin/fge-go` | engine | 有り | 上書き |
   | 残り 22 項目 | engine | 有り | 上書き |

   **「`@` 始まりか」でも「bundle-zip が引数で渡すか」でもない。** `bin/flix` は
   bundle-zip が `--flix-wrapper bin/flix` を渡すが、渡している実体は engine リポの
   devbox ラッパで、Studio の手元には nix も devbox も PATH 上の java も無い。
   上書きするとゲームのビルドが一切通らなくなる。逆に `bin/fge-go` は引数を渡していないが、
   中身を決めるのは engine 側なので上書きするのが正しい。引数で渡すかどうかは
   「engine リポの外に実体があるか」でしかなく、**どちらのリポが中身を決めるか**とは別の軸。

   `skipOnWindows` は尊重する。新しい engine が studio 持ちの項目を増やしたときは
   写す元が無いので、そこは 5 の世代ゲートで拒む。
5. **組み立て後の中身検査**（存在照合だけでは足りない）:
   - `bin/flix` が `../jre` を見るラッパか（devbox ラッパで上書きしていないか）
   - `bin/fge-go --version` が走るか。**`make bundle-zip` は `--fge-go` を渡さないので、
     zip に入るのは zip を作ったマシンの OS/CPU 向けの 1 つ**。走らなければここで止める
   - **世代ゲート**: zip の中に「要求する Studio 側部品の世代番号」を 1 行入れておき、
     自分の持ち物が満たさなければ拒んで「アプリごと入れ直し」へ倒す
6. `engines/<新>.partial/` → `engines/<新>/` へ rename（ファイルの rename と違い
   フォルダの rename も同じ場所なら不可分）
7. `engine-current.txt` を書き替える（テンプファイル → rename）。macOS の別名も張り直す
8. **古いバージョンは消さない。** 1 つ前まで残し、それより古い物だけ消す
   （走行中のゲームが掴んでいても壊れない・戻したいときは指し先を戻すだけ）
9. 更新完了イベントで Elm にバージョン表示とテンプレ一覧を読み直させる

**`codesign` は打たない。`.app` を触らないので署名の対象が何も変わらない。**

## D2. 更新の前に止める物

外に置くと「使っている物を消す」場面が無くなるので、止める物は **1 つだけ**になる。

- **checkd の常駐**（`bin/fge checkd --stop-all`）— 古い `flix.jar` を掴んだまま
  新しい規約を判定する新旧混在になる。**Studio は checkd を管理していない**
  （起こしているのは Claude Code のフックだけで、サーバは pid も掴んでいない）ので、
  これは新しい配線になる。同梱 engine の `bin/fge` を 1 回叩く形
- 走行中のゲームは**止めなくてよい**（古いフォルダを消さないため）。
  ただし「今動いているゲームは古い engine のままです」の 1 行は出す
- 受付を塞ぐ門は**作らない**。差し替えは別フォルダの中で完結し、
  指し先を変える瞬間だけが切り替わりなので、塞ぐ意味が小さい。
  同時に 2 回押されるのだけ `Runner.launchWork` の走行権で防ぐ（既にある）

## D3. Windows

置き場の設計（`engine-current.txt`）は Windows でもそのまま動く。残る壁は **zip の側**:
`make bundle-zip` が作るのは macOS 向けだけで（bash のラッパ・1 つだけの `fge-go`）、
Windows の Studio が落とせる物が無い。`ci/package-windows.ps1` は別の組み方をする。

→ **第 1 段では Windows は帯の案内だけ**（「新しいバージョンが出ています」＋
アプリごと入れ直し）。更新の実行は macOS のみ。作るなら CI の windows ジョブで
engine zip も作る形。

## D4. UI

「engine 0.31.0 → 0.32.0 が出ています」＋ボタン 1 つ。**開いた瞬間に自動で上げない**
— バージョン上げは絵と挙動まで変わる「人が選ぶ側」の変更。人が押すのはこの 1 回だけ。

進み具合は **`Runner.launchWork` に乗せる**（`Runner.flix:122-123`）。任意の仕事を
走行権つきで裏走らせる口が既にあり、`GET /engine/update/log` を
`Runner.logJson` に繋ぐ 1 行で進み具合の口が完成する。Elm 側は `Time.every` で
1 秒ごとに引く（ゲーム起動の経路がそのまま写経元）。

**engine のバージョンは今どこにも表示されていない**（`/health` の `version` は
editor_server 自身の `"0.1.0"` で、Elm はデコードしてから捨てている）。
帯を書く前に「今のバージョンを出す」1 段が要る。

## D5. ゲーム側への接続

- 押した後: 開いているゲームに `upgrade-game` → `update-plan`。呼ぶときは
  **別名経由**（`engines/` の実パスは空白を含まないが、別名の既存経路にそのまま乗る）
- **`upgrade-game` は `--json` を持つ**ので、Studio は
  `{swapped, checkGreen, planCount, planPath, rolledBack}` を読んで
  「上げ切った / 追随待ち / 失敗」を出し分けられる（終了コードは 0/3/1/2）
- 開いていない 10 リポへは新しい配線を作らない — **`bin/fge status` の
  「engine バージョンズレ」表示**が次に触った瞬間に案内を出す
- エンジンだけ上がってゲームが古い期間、`make check` は古い fpkg で普通に緑
  （flix.toml のバージョンで解決するので嘘ではない）。案内は status の仕事とする

## 段階と見積もり（実績ベースの日数）

| 段階 | 中身 | 日数 |
|---|---|---|
| D0 | 置き場を外へ（種まき・`engine-current.txt`・`EngineHome` の解決順・別名） | 0.5 |
| — | engine のバージョンを `/engine/version` で出し、画面へ（帯の土台） | 0.5 |
| D1 | GitHub API（ETag）・zip と SHA-256・展開・持ち越し・中身検査・指し先の差し替え | 1.5 |
| D2 | checkd を止める配線 | 0.25 |
| D4 | 帯とボタンと進み具合（Elm。ゲーム起動の経路を写経） | 1 |
| D5 | `upgrade-game` / `update-plan` へ繋ぐ（CLI は既にある） | 0.5 |
| **合計** | | **4.25** |

`.app` の中でやる案（5 日＋ codesign の未知）より小さく、未知が 1 つ減る。

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
| 2 | A2〜A3（bump で生成・絞り規則・スナップショット JSON・28 点照合へ） | 1.5 | 0 |
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
