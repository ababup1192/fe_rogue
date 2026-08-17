# テンプレ複製の正を 1 つにする

> **最終形は末尾の「v3 — レビュー 2 本を通した最終形」を読むこと。**
> 以下の S0〜S4 とシミュレーションは、そこへ至るまでの記録。
> v3 で却下された物: `bundle.json` / `BUNDLE.txt` / `templates/MANIFEST` の 3 概念、検査 7 本のうち 3 本、段階 6 つのうち 4 つ。

2026-08-17 に設計。レビュー 2 本（保守・構造変化の視点 / AI が確実に使える視点）を通過。
実装は未着手。速度は結果であって目的ではない — 目的は**「テンプレとは何か」の正を 1 つにすること**。

## 何が壊れているか

「テンプレ 1 本が何でできているか」を宣言したファイルは、engine にも Studio にも**無い**。
判定は 3 経路がそれぞれ別々に持っている。

| 経路 | 除外している物 | 場所 |
|---|---|---|
| Studio `stage-engine` | `lib` / `build` / `.devbox`（全階層） | `flix_ge_studio/Makefile:275` |
| engine `new-game` | **`lib` だけ** | `Makefile:783-784` |
| Studio `NewGame.create` | **`lib` だけ**（しかも最上位のみ） | `server/src/NewGame.flix:207`・`copyTree` 470-479 |

`copyTree` の `skipTopLevel` は再帰呼び出しで `Set#{}` を渡すので、最上位以外は原理的に一致しない。
これが下の 3 つの症状の直接の原因。

### 症状 1 — 新しいゲームを作るたび 533MB を複製する（実測）

`cp -R templates/rpg-starter/.` = **22 秒 / 533MB / 125,330 ファイル**。
除外つきにすると **37ms / 2.0MB / 54 ファイル**。ビルド時に 1 回ではなく、**人がゲームを作るたび毎回**払っている。

### 症状 2 — `.app` の中身がビルドしたマシンの状態に依存する

`cp -R $(ENGINE)/templates` は git 管理外の `debug/*.png` `gallery/*.png` `reference/*.png`（title 以外）も運ぶ。
git 追跡 5.6MB に対し、実際に `.app` へ入るのは 11.5MB。**clean clone の CI と手元で中身が違う。**

### 症状 3 — 運び漏らしても検査が緑

ジャンルカードのサムネは `<engine>/templates/<name>/reference/title.png` の直読み
（`server/src/Genesis.flix:135-151` → `Editor.flix:146` が 404）。
だが `bin/check-refs.py` の `BUNDLE_REQUIRED`（44 点）が templates について守っているのは
`templates/game-starter/Makefile` の **1 点だけ**。cp が 99% 痩せても検査は通り、絵なしカードへ黙って倒れる。

### ついでの数字

Studio `make stage-engine` は **167 秒**。支配項は `Makefile:266` の `cp -R templates`
（単体実測 193 秒 / 2.1GB / 499,851 ファイル）で、直後に 99% を捨てている。
`build/` が 2.08GB（テンプレ 5 本で 253M〜520M）。

## 決めたこと

**engine が生成時に git から一覧を焼き、下流 3 経路はリテラルの行を読んで写すだけにする。**

- 判定（何がテンプレか）と実行（どこへ写すか）を分ける
- git は **git がある場所でしか使わない**。`.app` 内の同梱 engine は git リポではない
- 一覧は**生成物**。AI も人もズラせない（宣言ファイルは追記を忘れられる）

## 却下した案と理由

| 案 | 却下理由 |
|---|---|
| `build/` を templates の外へ出す | **Flix に build 出力先を変える口が無い**（`bin/flix --help` の全オプション・`flix.toml` のキー・環境変数すべてを確認）。`build/` は「flix を走らせた CWD 直下」で固定 |
| `rsync --exclude` の手書きリスト | 構造が変わると黙って追随しない。新しいゴミディレクトリが生えたら 3 か所とも漏れる |
| パターンで宣言するファイルを新設 | 前例の `agents-pack/manifest.json` に**パターンは 1 つも無く全部リテラル**。パターンを入れると glob を Make / Python / Flix の 3 実装で書くことになり、`**/` の意味・否定の順序・symlink の扱いが 3 通りにズレる |
| `git ls-files` を運搬の正にする | `.app` 内の同梱 engine で `git ls-files` は**空を返す**。空を「テンプレ 0 個」と解釈すると、空のゲームが「成功」で産まれる |

## 段階（この順に。速度は最後）

### S0 — 検査を先に。出荷物は 1 バイトも変えない

- `bin/check-refs.py` の `--bundle` を、リテラル列挙から **`ROOT/templates/*/` の列挙から導く形**へ。
  各テンプレについて `Makefile` / `flix.toml` / `project.json` / `src/`（非空）/ `reference/title.png` を要求。
  `BUNDLE_REQUIRED` の `templates/game-starter/Makefile` 1 行は消してよい。
  **リテラルで 6 テンプレ分を書き足す形にしない** — 7 個目で AI が追記を忘れ、同じ病気が再発する
- Studio `make test` に 1 本追加: `Genesis.genres()` の `starter != ""` な全件について
  `<engine>/<starter>/reference/title.png` が実在すること。絵なしカードを直接守る唯一の検査
- **今の `cp -R` バンドルで緑になることを確認してから次へ。**
  CI の clean clone に `reference/*.png`（title 以外）は無いので、それらを必須にしない
- 検査自身は fail-open にしない。期待値の出どころ（`ROOT/templates`）が空なら
  「守る物が無い」ではなく「壊れている」として非ゼロ終了

### S1 — 除外リストを 3 経路で 1 つにする（速度改善ゼロ・退行リスクほぼゼロ）

**520MB 事故はここで今日直る。**

- 除外は `lib` / `build` / `.devbox` / `.test-logs` / `gallery` / `debug` / `.DS_Store` / `__pycache__`
- `Makefile:783` の `new-game` と `NewGame.flix:207` の `copyTree` を**全階層**へ
  （`skipTopLevel` の最上位限定をやめる）
- 緑の保ち方: S1 の前後で `make new-game` した成果物を `find | sort` で差分。
  消えるのが build/lib/debug/gallery だけであることを目視

### S2 — stage を生成リスト化（167 秒 → 1 秒。スパイク実測済み）

- engine に templates 専用のターゲットを新設。`git ls-files -z -c templates` から
  `templates/MANIFEST` を生成し、`rsync --files-from` でステージ
- **`-o`（未追跡）は使わない。** 代わりに `git ls-files -o --exclude-standard templates` が
  非空なら名前を挙げて**落とす** — これが「AI の `git add` 忘れ」をその場で殴る仕掛け
- **`git archive HEAD` も使わない。** 未コミットのテンプレ修正が `.app` に入らず、
  「直したのに反映されない」の診断が極めて難しくなる
- git が使えない（tarball / `.git` 無し / PATH に git が無い）なら**落とす**。
  S1 の除外コピーへ倒さない（ここはビルド工程で、AI が直せる場所）
- Studio `Makefile:266`（`cp -R`）と `:275`（`find -exec rm`）をこの呼び出しに置換。
  他の約 20 行の `cp` は触らない
- 切り替え前に旧経路と新経路の両方でステージし、`find <stage>/templates -type f | sort` を比較。
  差分が「ignore 済み PNG と `.test-logs` と `.DS_Store` のみ」であることを確認してから置換

### S3 — `NewGame.flix` が一覧を読む

- バンドル内に `templates/MANIFEST` があればそれに従い、無ければ S1 の除外コピーへ倒して 1 行言う
  （実行時＝人の目の前なので、ここだけ fail-open を許す。倒れ先が**正しくなってから**上に速い経路を載せる）
- Flix 側は行を読んで copy するだけ。**glob は要らない**
- JSON / 行読みの前例は `NewGame.flix:171-190`（`DocJson.parse` → `JsonCodec`）。新規に作る物はゼロ
- `manifestPlan` の「1 節でも欠けたら全体を捨てる（半端に配らない）」という**形**は真似する。
  倒れ先の中身だけ作り直す

S2 と S3 の間に `.app` を 1 本焼き、実機で「9 枚のカードに絵が出る / 各ジャンルで 1 本産む」を通す。

## fail-open の分け方（好みでなく倒れ先の性質で決める）

| 倒れ先 | 判断 |
|---|---|
| 遅いが正しい（ビルド工程） | **fail-closed**。黙って 167 秒に戻ると、この作業の目的が無言で失われる |
| 速いが間違い | 絶対に倒さない。`NewGame` の `cp -R` フォールバックは fail-open でなく fail-wrong |
| 実行時（.app の中・人の目の前） | fail-open を許す。ただし倒れ先を「昔の経路」にしない |
| 検査自身 | 絶対に fail-open にしない |

## 実装コスト

| 段階 | ファイル | 言語 | 目安 |
|---|---|---|---|
| S0 | `bin/check-refs.py`、Studio の test 1 本 | Python / Flix | +40 / +15 行 |
| S1 | `Makefile`(new-game)、Studio `Makefile`、`NewGame.flix`(copyTree) | Make / Flix | +30 行 |
| S2 | `Makefile`(新ターゲット)、Studio `Makefile`（2 行 → 1 行） | Make | +30 行 |
| S3 | `NewGame.flix`、`Makefile` | Flix / Make | +50 行 |

Rust は 0 行（`main.rs:357` は `EDITOR_ENGINE` を渡すだけ）。web も 0。実質 5 ファイル・3 言語。

## 計測する指標（3 つだけ）

1. `make stage-engine` の実時間（秒）。仮説 167 秒 → 10 秒未満。
   5 秒を切らないなら次の支配項（`chmod -R u+w`・`cp -R agents-pack`・`check-refs`）を測ってから続ける
2. **バンドルの決定性** — 汚れた作業ツリーと clean clone の 2 条件で焼いた
   `<stage>/templates` の `find -type f | sort | shasum` が一致するか。
   **一致 = 症状 2 が消えた証拠**で、時間より重要
3. `.app` の中から新しいゲームを 1 本産む所要時間と成果物サイズ。
   現状 533MB / 22 秒（複製だけ）→ 2.0MB + engine_full

## いま手元にある未コミットのスパイク

`flix_ge_studio/Makefile:266` を git ベースへ差し替えたスパイクが**入ったまま**
（`-co` のまま・fail-closed なし = S2 の最終形ではない）。
実測 167 秒 → 1 秒、`swap-engine` 10 秒、`check-refs --bundle` 44 点通過、
templates 288 ファイル・`title.png` 6 枚・`build`/`lib`/`.devbox`/`debug`/`gallery` 0 個。
**S0 から順に入れ直すなら、これは戻す。**

## シミュレーション — 変更の種類ごとに、この形が持つか

「◯ 自動で追随」「△ 手作業だが気づける」「✗ 手作業で、落としても黙って壊れる」。

### A. engine のコードを変えた

| # | 変更 | 今日 | S0〜S3 後 | 判定 |
|---|---|---|---|---|
| A1 | `engine/src` 等を直した | `check-engine-full` が mtime で「fpkg がソースより古い」を見て止める | 変わらず | ◯ **今日すでに正しい。計画は触らない** |
| A2 | pub API に非互換（今回の `anchorOffsetOf`） | 自動検出なし。Studio の `flix check` が落ちて初めて分かる。呼び手がゼロなら無風のまま版だけズレる | 変わらず | △ **計画の対象外・宿題** |

A2 の手作業は `server/flix.toml` の 1 行 + lib 入れ替え + stage + swap。
今回それで足りたのは「Studio に呼び手がゼロだった」という**運**であって、仕組みではない。

### B. テンプレを変えた（計画が直接効く範囲）

| # | 変更 | 今日 | S0〜S3 後 | 判定 |
|---|---|---|---|---|
| B1 | 既存ファイルを直した | 167 秒かけて拾う | 1 秒で拾う（`git archive` を使わない決定がここを守る） | ◯ |
| B2 | ファイルを足した（`git add` 済み） | 拾う | 拾う | ◯ |
| B3 | ファイルを足した（**`git add` 忘れ**） | 手元では運ばれ CI では消える。**無言** | `git ls-files -o` が非空 → 名前を挙げて落ちる | ◯ **今日の無言バグが直る** |
| B4 | テンプレを 1 本新設した | `cp -R` が拾う。`Genesis.genres()` の白名簿に追記が要る | S0 の検査が `title.png` 等の焼き忘れを止める | △ **穴が残る**（下記） |
| B5 | テンプレを削除・改名した | 白名簿が宙を指し 404 = 絵なしカード。無言 | S0 のテストが赤 | ◯ |
| B6 | 新しいトップ階層を足した（`shaders/` 等） | 拾う | 拾う | ◯ **パターン宣言案を却下した理由の実証** |
| B7 | 新種の生成物ディレクトリが増えた | 運ばれてしまう | S2 は `.gitignore` に足せば自動追随。**S1/S3 の除外リストは追記が要る** | △ |

**B4 の穴**: S0 で入れる検査は「`Genesis` に載っているテンプレに `title.png` があるか」の**片方向だけ**。
逆（`templates/` にあるのに `Genesis.genres()` へ足し忘れた）は誰も見ない — カードが出ないだけで緑。
→ 検査を**両方向の集合比較**にする（`templates/*/` の集合と `starter != ""` の集合が一致すること）。

**B7 の位置づけ**: S2（生成リスト）が正で、S1 の除外リストは git が使えない場所の保険。
保険側に追記漏れが出ても、正しい経路は `.gitignore` で自動追随する。許容できる非対称。

### C. skills・補助 script・docs だけを変えた（**計画の対象外**）

`stage-engine` の cp は約 20 行あり、`templates` はそのうちの 1 行にすぎない。
残りは glob と literal が混ざっている。

| # | 変更 | 運搬（stage-engine） | 配布（manifest.json） | 検査（BUNDLE_REQUIRED） | 判定 |
|---|---|---|---|---|---|
| C1 | skills を足した / 直した | `cp -R agents-pack` 丸ごと ◯ | `copyDirs` でディレクトリ丸ごと ◯ | — | ◯ **今日すでに正しい** |
| C2 | `bin/lint-*.py` を足した | `lint-*.py` glob ◯ | **literal 20 件に追記** ✗ | 追記 ✗ | △ |
| C3 | `bin/` に別名の script を足した | **literal に追記** ✗ | 追記 ✗ | 追記 ✗ | ✗ **3 か所とも黙って落ちる** |
| C4 | `docs/` に 1 枚足した | literal 7 件に追記 ✗（`docs/api-digest/*.md` だけ glob） | — | 追記 ✗ | ✗ |
| C5 | `.claude/hooks/` に足した | literal 4 件に追記 ✗ | — | 追記 ✗ | ✗ |
| C6 | `mk/*.mk` を足した | glob ◯ | — | — | ◯ |

**C3〜C5 が最大の残穴。** しかも既にズレている — `stage-engine` が cp しているのに
`BUNDLE_REQUIRED` に無い物が実在する（`.claude/hooks/after-flix-work.py`・`after-flix-touch.py`、
`bin/lint-composition.py`・`lint-style.py`・`lint-jargon.py`）。
このうち 3 つは `manifest.json` が配布対象として要求しているので、
**運搬が痩せた日にゲーム側で「そんなファイルは無い」になる**。

### D. Studio 側だけ変えた

`swap-jar` / `swap-web` で反映。`stage-engine` は不要。◯

## この形は一般化すべき（シミュレーションの結論）

templates で正しいことは、バンドル全体でも正しい。
S2 を「**templates の一覧を焼く**」で止めず「**バンドル一式の一覧を焼く**」まで広げれば、
C2〜C5 が同時に消える。

- engine が「配る物の定義」を持つ（= 案 C を全面適用）。判定は git + 明示規則、出力はリテラルの一覧
- `BUNDLE_REQUIRED` を**手書きリストから、生成された一覧の検証へ**変える
  （今の 44 点は「engine 側に実在するか」の検査で、`stage-engine` の cp とはズレたまま。
  ズレを機械が見ていない）
- Studio 側の cp 約 20 行はターゲット 1 本の呼び出しに畳まれる

**ただし段階は変えない。** S0 → S1 → S2（templates）で一度緑にしてから、
S2' としてバンドル全体へ広げる。一度に全部やると、退行したとき原因が切り分けられない。

## 併せて直す小物（レビュー指摘）

- `Genesis.firstReferencePng` のフォールバックは S2 後に無効な網になる（バンドルに title.png しか無い）。
  **消して title.png 必須に倒す**。網があるふりが一番危ない
- ステージ後に「symlink が 0 本」を検査に足す（`.devbox` を名前で消していた網が外れるため。
  追跡 symlink 1 本で `codesign --verify` が落ち、`make app` では出ず `swap-engine` でだけ出る）
- Studio が古い engine を指したときのメッセージ（新ターゲットが無いと
  `No rule to make target` になり、原因が読めない）

---

# v3 — レビュー 2 本を通した最終形

新ファイル 0・新概念 0・**AI が新たに覚える手順 0**。実装 50 行以下。

## 原則が 1 つ変わった

「個別列挙をやめてディレクトリ丸ごと」ではなく、**「個別列挙をやめて `git ls-files <dir>` で丸ごと」**。

`cp -R bin` は `bin/flix.jar`（32MB・gitignore 済み）と `__pycache__` を .app へ入れる。
skills が無事だったのは「ディレクトリ丸ごとだから」ではなく「そのディレクトリに捨てる物が無かったから」。
取り違えると事故る。

## 却下した物（v2 から）

| 物 | 却下理由 |
|---|---|
| `bundle.json` | バンドル全体を宣言できない。`bin/flix.jar`（nix 由来）・`bin/flix`（**Studio 由来**）・`engine_full.fpkg`（生成物）・`lib/cache`（Studio 由来）・版付きパスは、いずれも ENGINE の git に存在しない |
| `BUNDLE.txt` | 「焼き直す手順」を AI に作る。検査が赤くなったとき、AI は高確率で**一覧を手で編集して緑にする**。嘘をつく口を開けるのと同じ |
| `templates/MANIFEST` | 読む側が 1 つしかないなら、それは MANIFEST ではない |
| I2（`git ls-files templates` ⊆ 宣言） | 運搬が `git ls-files templates` そのもの。自分自身との比較でトートロジー |
| I4 / I5 | 対象が消えた / ⊇ にしか書けず `BUNDLE_REQUIRED` と役割が重複 |
| api-digest の diff から非互換を自動判定 | 判定器の規模が別プロジェクト級。`git diff docs/api-digest/` を**表示するだけ**で 9 割取れる |
| glob を宣言に持つこと | 解釈器が git / Python / Flix の 3 つになり、`*` がスラッシュを跨ぐかで食い違う。**除外リストの三重化を glob 実装の三重化に置き換えるだけ** |

## やること（5 つ）

### 1. Studio の cp 群 15 行 → 1 行

```make
git -C $(ENGINE) ls-files -z -c bin docs mk agents-pack .claude/hooks templates \
  | rsync -a --from0 --files-from=- $(ENGINE)/ $(ENGINE_STAGE)/
```

丸ごと運んでも実量は `bin/` 488K・`docs/` 4.5M・`.claude/hooks/` 44K・`mk/` 12K・`agents-pack/` 224K。
同じ .app に `flix.jar` 32MB と JRE が同居しているので、4MB を惜しんで二重管理を維持するのは割に合わない。

**git で解けない 5〜6 行は Studio に残す**（`bin/flix.jar` / `bin/flix` / `engine_full/artifact/*` /
`lib/cache` `lib/external` / `chmod -R u+w`）。ここを ENGINE へ移すと、
ENGINE が Studio の配置規約を知ることになり依存が双方向になる。

これで C2〜C5 の穴（`bin/` に lint- 以外の名前を足す・`docs/` に 1 枚・`.claude/hooks/` に 1 本）が
**全部消える**。今バンドルから漏れている `after-art-edit.py` ほか 5 本も自動で入る。

### 2. `-c` と `-co` の使い分け（明文化する。片方に統一されると必ず事故る）

| 経路 | 使う | 理由 |
|---|---|---|
| stage（.app を焼く） | **`-c`（追跡のみ）** | 再現性。`.git/info/exclude` のマシン依存も、未追跡の混入も原理ごと消える |
| new-game（人がゲームを産む） | **`-co --exclude-standard`** | テンプレを編集中の AI が未コミットの `.flix` を書いた直後に産むと、`-c` では黙って消える |

現在 Studio に入っているスパイクは `-co` なので、**`-c` へ直す**。

### 3. `BUNDLE_REQUIRED` を「宣言に格上げ」ではなく **導出に降格**

`bin/check-refs.py` は既に「参照から必要物を導出する」機構を 3 つ持っている
（`sync_agents_dist()` / `check_templates()` / `check_agents_pack()`）。
`BUNDLE_REQUIRED` **だけ**がその機構から外れて手書き literal で取り残されており、
5 件ズレているのはその必然。

```
必須集合 = manifest.json の src 一式
         ∪ templates/*/Makefile と mk/*.mk が参照する $(ENGINE)/{bin,docs}/*
         ∪ AGENTS.core.md が参照する bin/ docs/
         ∪ agents-pack/settings.json が指す .claude/hooks/*
         ∪ コア literal 6 件（Makefile, flix.toml, bin/flix, mk/game.mk,
                              engine_full/flix.toml, engine_full/artifact/engine_full.fpkg）
```

上 4 つは全部すでに同ファイルで計算済み。`check_bundle()` に渡すだけ。literal 44 → 6。
**`manifest.json` に節を足すのは反対** — あちらは「産まれたゲームへ配る物」、
こちらは「engine を .app に運ぶ物」で集合が違う（`docs/api-digest/*.md` は配らないが運ぶ）。
混ぜると、どちらに足すかを AI が毎回間違える。

### 4. ENGINE の `new-game` を 1 行差し替え（22 秒 → 37ms）

`Makefile:778` の `cp -R "templates/$(NG_TEMPLATE)/."` を
`git ls-files -z -co --exclude-standard "templates/$(NG_TEMPLATE)"` + rsync へ。
533MB / 125,330 ファイル → 2.0MB / 54 ファイル。

`NewGame.flix:207` の `copyTree(skipTopLevel = Set#{"lib"})` は**触らなくてよい** —
写す先が既に刈られた .app 内の templates なので、実害が無い。

### 5. 検査 4 本（合計 15 行程度）と版

- **I6 symlink 0 本**（1 行）: `find $(ENGINE_STAGE) -type l`。`.devbox` を名前で消す網の代替
- **I7 genres ⟷ templates**（3 行）: `Genesis.genres()` の `starter != ""` の集合と
  バンドルの `templates/*/` の集合を**両方向** diff。失敗が「カードが出ない」で最も気づきにくい
- **I3 テンプレの必須物**（10 行・優先度最低）: `templates/*/` の列挙から
  `Makefile`/`flix.toml`/`project.json`/`src/`/`reference/title.png`。add-template スキルの機械化
- **版一致**: バンドルに engine の版を焼き、Studio の `make test` で `server/flix.toml` と一致検査。
  過去に実際の事故がある（`8f87f99 同梱 engine を 0.25.0 へ上げる — templates と Studio 本体で版がずれていた`）
- **`make release` は `git diff docs/api-digest/` を表示するだけ**（判定しない）

## 併せて棚卸しする物（レビュー指摘・実在）

- `NewGame.flix` の `distributeLegacy` に **4 本目の手書きリスト**がある
  （`lint-view.py` `lint-palette.py` `lint-sprite.py` `lint-anim.py`）。manifest とは別系統で、
  検査外・fail-open。`lint-ui-overflow.py` を manifest に足しても legacy 経路のゲームには届かない
- 同ファイルの `copyEntry` / `copyDirEntry` は「src が無ければ黙って飛ばす」。
  ビルド工程側は fail-closed へ
- `.gitignore` に `.devbox/` を足す（実測では `-o` が拾う物は 0 件で今日の実害は無いが、1 行の保険）

## 塞がらないと認める物

- **engine の pub API 非互換の伝播**（A2）。本当に効いているのは Studio の `flix check` で、
  それ以上の自動化は費用に見合わない。`make release` の api-digest diff 表示までで止める
- `Genesis.flix` の literal（ジャンル id・表示名）は I7 の対象外

## 実測の現在地

| | 前 | 後 | 状態 |
|---|---|---|---|
| `make stage-engine` | 167 秒 | 1 秒 | スパイク投入済み（`-c` へ直す必要あり） |
| `make swap-engine` | 約 177 秒 | 10 秒 | 同上 |
| new-game の複製 | 22 秒 / 533MB / 125,330 ファイル | 37ms / 2.0MB / 54 ファイル | **未着手** |
| バンドルの決定性 | 461 ファイル（マシン依存） | 288 ファイル | `-c` で確定 |

---

## 追記 — git の履歴と index の話（実測で確認）

### 履歴の深さ・コミット数は無関係

`git ls-files` が読むのは **index（ステージ領域）であって履歴ではない**。
実測: このリポジトリは 1029 コミットあり、500 コミット前には `templates/` が存在すらしないが、
`git ls-files -c templates` は今の 288 件を返す。shallow clone（`--depth 1`）でも index は完全なので影響しない。

### 影響するのは index と作業ツリーのズレ

| 状態 | どうなるか |
|---|---|
| 追跡ファイルを消したが `git rm` していない / sparse checkout の skip-worktree | 一覧に載るが実体が無い → **rsync が名前を挙げて落ちる（終了コード 23）**。実測済み。fail-loud で望ましい |
| merge / rebase の conflict 中 | unmerged エントリが stage ごとに複数行出る（重複）。**未検証** — 実装前に確かめること |
| shallow clone | index は完全なので影響なし（原理。未検証） |

### 実測で見つかった本当の穴 — パイプが終了コードを飲む

```
false | rsync -a --files-from=- src/ dst/   → 終了コード 0・何も運ばれない
```

`git ... | rsync` の形では、**git が失敗しても rsync は空の入力で正常終了する**。
git が無い / リポジトリでない / pathspec が壊れている、のどれでも
**「何も運ばずに成功」**になる。1 本目のレビューが指摘した fail-closed の穴が、実際に開いていた。

直し方（実測で確認）:

```make
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
```

`pipefail` ありなら失敗時は終了コード 1、正常時は 0 で 288 ファイル。
一覧を一時ファイルへ書いて件数を検査する形でもよい。

**現在 Studio に入っているスパイクはこの穴を持っている。** `-co` → `-c` と併せて直すこと。

---

# 訂正 — v3 の前提が間違っていた（レビュー 3 本・実測で確定）

**この計画の看板だった「167 秒」の診断は誤り。** 真因は 3 経路の除外リストのズレではなく、
`templates/*/build/` が放置されていること。

## 実測

```
templates 全体      499,851 ファイル / 2.1GB
  うち build/ の中  498,928 ファイル   ← 99.8%
  build を除くと        923 ファイル / 68MB
```

`make clean-game-builds`（`Makefile:150-159`・**今日すでに存在する**）を 1 回打てば
`cp -R templates` は 193 秒 → 1 秒台になる。**この計画を 1 行も書かずに。**
そしてこのターゲットは**どこにも配線されていない**（`grep -rn clean-game-builds` は Makefile と README のみ）。

## 症状 2（決定性）も、出荷物では起きていない

`.github/workflows/release.yml:52-56, 131` は engine を `actions/checkout` で clean clone し
`ENGINE="$PWD/engine_repo"` で `make app` する。clean clone に `build/` も未追跡 PNG も無い。
**出荷される .app は既に 288 ファイルで決定的。** 汚れているのは手元で焼いた .app だけ。

## 症状 1（533MB）も既定経路では起きない

`new-game` の既定は `game-starter`（`Makefile:735`）で、**9.8MB・`build/` 無し**（実測）。
533MB を払うのは重いテンプレを明示したときだけ。しかも `new-game` は末尾で
check → test → render-all を回すので、end-to-end に対する複製の比率は数%。

## 過去の事故は全部「痩せた」方向

Studio の同梱まわりのコミット 12 本は**すべて「運搬が痩せていた」**。
「太っていて壊れた」は 0 本。この計画は運搬をさらに痩せさせる方向へ動く。

## v3 のまま実装すると静かに壊れる 5 点（実測で確認）

1. **`bin/flix` が上書きされる。** pathspec の `bin` に engine 版（5330B）が入り、
   Studio 専用ラッパ（2117B・同梱 JRE だけを見る）を rsync が後から潰す。
   `.app` から産んだゲームが JDK の無い Mac で動かなくなる。4 本の検査は全部緑
2. **`.SHELLFLAGS` は CI で効かない。** GNU Make 3.82 以降の機能で、macos-latest の
   `/usr/bin/make` は **3.81**。手元 devbox（4.4.1）では fail-closed、
   **リリースを焼く CI では fail-open** という最悪の組み合わせ
3. **pathspec の打ち間違いは pipefail でも静か。** `git ls-files -c nosuchdir` は
   終了コード 0・出力ゼロ・メッセージ無し。一時ファイル + **件数の下限検査**でしか止まらない
4. **`BUNDLE_REQUIRED` の導出化は検査を痩せさせる。** 実測で 44 のうち **14 件が落ち**
   （`bin/carve/carve.py` と `check-render-budget.py` は、まさにその穴を塞ぐために
   足された行）、**18 件の偽陽性**が入る（`sync_agents_dist()` が src と dst と親を混ぜて返すため）
5. **`-c` 統一で「`git add` 忘れ」が今日より悪化する。** 今の `cp -R agents-pack` は
   未追跡も運ぶ。`-c` にすると運ばない。門番（`-o` が非空なら名前を挙げる）を v3 で落としていた
6. **4 本目のバンドル定義**: `flix_ge_studio/ci/package-windows.ps1`。make を通らず、
   独自のリテラル一覧を持ち、`mk/` も `docs/` も入れず `check-refs` も走らせない

## 順序の訂正（効果 / コスト / リスク）

| 順 | 手 | 効果 | 変更量 | git 依存 |
|---|---|---|---|---|
| **0** | `make clean-game-builds` を配線（フック or status の警告） | 2.1GB → 68MB、167 秒 → 数秒 | 数行 | 無 |
| **1** | `Makefile:779` の `rm -rf "$(GAME)/lib"` に `build debug gallery .devbox` を足す | 533M → 2.9M | **1 行** | 無 |
| 2 | I7（genres ⟷ templates 両方向）・I3（テンプレ必須物） | 無言バグを止める | 15 行 | 無 |
| 3 | Studio の cp 15 行 → `git ls-files -c` 1 行 | C2〜C5 が消える | 1 行 | 有（ビルド工程のみ） |
| 4 | `BUNDLE_REQUIRED` を**導出 ∪ literal**（減らさない） | ズレ 5 件が消える | 40 行 | 無 |
| — | new-game を git 化 | 手 1 の後では **+0.9MB のみ**。runtime の git 依存を買う価値なし | — | 有（実行時） |

**手 0 と手 1 で、この計画が謳う数字の 95% が取れる。** その後で git 化を評価し直すと、
それは速度の施策ではなく**決定性と C2〜C5 の施策**として正味の姿で判断できる。

## 実装前に潰す最小セット

1. `bin/flix` を pathspec から除外するか、rsync の**後**に Studio 版を置く（順序をコメントで固定）
2. `pipefail` に頼らず、一覧を一時ファイルへ落として**件数の下限**を検査
3. 残置リストに `Makefile` / `flix.toml` / `engine_full/flix.toml` を明記（v3 の抜け）
4. `BUNDLE_REQUIRED` は**減らさない**（導出 ∪ literal）
5. `check_bundle()` の失敗メッセージを「ENGINE で `git add` したか」へ書き換える
   （今の文面は AI を「一覧を編集して緑にする」へ誘導する）
6. `-o --exclude-standard` の門番を戻す
7. I7 は Studio の `flix test` でなく `check-refs.py --bundle` に置く（`make test` は ENGINE を export していない）

## 私の測定の訂正

- 「1029 コミット」は正しい（main = 1029・初コミット 2026-05-04）。
  レビューの「main は 50 コミット」は誤り
- `build/` の増加率は `find -newermt` が正しく動かず**測れていない**。最古が 2026-08-11 とは確認済み
