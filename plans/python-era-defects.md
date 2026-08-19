# Python 時代の不具合の一覧（Go へそのまま写した物）

**A が 34 件・B が 18 件・C が 22 件（合計 74 件）。ほかに未確認が 6 件。**

`bin/` の Python の道具 34 本を Go へ移した（`7a180747`）。移行の縛りは
「Python と 1 バイトも違わない出力」だったので、途中で見つかった Python 側の不具合は
**直さずそのまま写してある**。`NOTES.md` には「50 件超」と 1 行だけ残っていて中身が
無かったので、記録から掘り直した物がこれ。

危険度の分け方:

- **A** — 実際に誤判定を出す（通すべき物を止める / 止めるべき物を通す）。検査が例外で
  落ちて結果が出ない物もここに入れる
- **B** — 出力の字面や並び順がおかしい（判定そのものは合っている）
- **C** — 理屈上おかしいだけで、いまの使い方では表に出ない

**出どころの書き方**: `LOG` は
`/Users/abab/.claude/projects/-Users-abab-Desktop-flix-game-engine/` を指す。
`LOG/8869084b….jsonl:610` はその JSONL の 610 行目。移行前の Python は
`git show 7a180747^:bin/<名前>.py` で読める。

**見本の件数**: `testdata/lint/` にあるのは
check-refs 28・jargon 19・precommit 17・anim 13・sprite 12・check-render-budget 10・
check-api-released 9・check-api-index 9・view 4・hooks 4・explain-error 4・
ui-overflow 3・fallback 3・f32 3・style 2 の計 140 件。
**status・carve・sync-agents・gen-rules・api-digest には見本が 1 件も無い**ので、
この 5 本を直しても `testdata/lint/` は動かない（逆に、退行を捕まえる物も無い）。

---

## A: 実際に誤判定を出す（34 件）

### 1. 正方形を「楕円そのもの」と判定し、検査の狙いと逆向きに鳴る

- **どこ**: `bin/lint-style.py` の `ellipse_iou`（閾値 `ELLIPSE_IOU = 0.85` は 65 行目、
  判定は 451 行目 `if iou >= ELLIPSE_IOU`）/ `go/internal/style/measure.go:291 regionEllipseIOU`
- **何が起きる**: 10×10 の正方形を入れると IoU が `0.8915920840735931` になり、閾値 0.85 を
  超える。矩形だけで描いた絵に「塊を楕円の重ね合わせで作っている」という注意が鳴る
- **実害**: 誤判定。しかもこの検査は「矩形だけの画面から脱する」ために置いた物なので、
  **矩形の絵を見つけて逆の注意を出す**という一番まずい壊れ方をしている
- **いま**: そのまま写した。`go/internal/style/measure_test.go:61
  TestEllipseIOUOfSquareMatchesPython` が `0.8915920840735931` を期待値として固定している
- **直すなら**: 面積比だけでなく輪郭のふくらみを見るか、閾値を上げる。
  `testdata/lint/` で「楕円」を含む期待値は **2 件**
- **出どころ**: `LOG/8869084b….jsonl:1085`、`LOG/8869084b…/subagents/agent-aa246c7713f2a1547.jsonl:172`。
  Python のソースでも確認した

### 2. リポを `legacy/` という名前のフォルダに置くと常に緑になる

- **どこ**: `bin/check-api-index.py:37` `SKIP_DIRS = {"legacy"}` と `:58`
  `if SKIP_DIRS.intersection(p.name for p in path.parents)` / `go/internal/apiindex/`
- **何が起きる**: `path.parents` はリポの根で止まらずファイルシステムの根まで上がる。
  リポを `~/work/legacy/flix_game_engine/` のような場所へ置くと、**全ファイルが除外され、
  何を書いても検査が緑になる**
- **実害**: 誤判定（止めるべき物を通す）。検査が丸ごと無効になる
- **いま**: そのまま写した。`bin/lint-rules/check-api-index.json` の `skipDirs` に
  `"legacy"` があり、Go も祖先を全部見る
- **直すなら**: リポの根からの相対パスだけを見る。見本 9 件のうち `legacy` を使う物は
  リポの根の下に置いてあるので、期待値は動かない見込み
- **出どころ**: `LOG/8869084b….jsonl:1158`、`LOG/8869084b…/subagents/agent-a35bd48d569100ea4.jsonl:195`。
  Python のソースでも確認した

### 3. 中身が空の `items.tsv` が「計測済み・予算内」になる

- **どこ**: `bin/check-render-budget.py:39 read_kv` と `:96 if items is None`
  / `go/internal/renderbudget/renderbudget.go:246`
- **何が起きる**: `read_kv` は読めなければ `None` を返す約束だが、**中身が空のファイルは
  空の dict `{}` を返す**。`if items is None` を通り抜けて `total=0` として扱われ、
  「動的 0 個・予算内」かつ「計測済み」に数えられる。書き出している途中で切れたサイドカーが
  そのまま通る
- **実害**: 誤判定（止めるべき物を通す）
- **いま**: そのまま写した。Go も `readKV` の `ok` が真のまま `!items.ok` を抜ける
- **直すなら**: 空の dict も「読めなかった」扱いにする。見本 10 件のうち
  `no-sidecars-is-note-only` 系が動く可能性がある
- **出どころ**: `LOG/8869084b….jsonl:1124`、`LOG/8869084b…/subagents/agent-a5ce9308adcad5b17.jsonl:311`。
  Python のソースでも確認した

### 4. 数値でない値を 0 に丸めて緑にする

- **どこ**: `bin/check-render-budget.py:75 as_int` / `go/internal/renderbudget/`
- **何が起きる**: `except (TypeError, ValueError): return fallback` なので、
  `total=abc` と書かれた壊れたサイドカーが `total=0` になり予算内で通る
- **実害**: 誤判定（止めるべき物を通す）。3 番と組み合わさると「壊れたサイドカーは
  どう壊れていても緑」になる
- **いま**: そのまま写した（`asInt` が同じく既定へ落とす）
- **直すなら**: 数値でない値は赤にする。見本 10 件のうち数値でない値を持つ物は無いので
  期待値は動かない見込み
- **出どころ**: `LOG/8869084b….jsonl:1124`、`LOG/8869084b…/subagents/agent-a5ce9308adcad5b17.jsonl:311`。
  Python のソースでも確認した

### 5. 壊れた `SHA256SUMS.txt` の行を捨てて「全部 OK」に見せる

- **どこ**: `bin/status.py:116 if len(parts) == 2` / `go/internal/status/`
- **何が起きる**: ハッシュと名前に分かれない行（切れた行・別の区切り文字）を、
  エラーを出さずに読み飛ばす。**基準ファイルが半分壊れていても「全部 OK」と表示される**
- **実害**: 誤判定（止めるべき物を通す）。退行検知そのものが無効になる
- **いま**: そのまま写した
- **直すなら**: 読めない行を赤にする。status には見本が無いので `testdata/lint/` は動かない
- **出どころ**: `LOG/8869084b….jsonl:1288`、`LOG/8869084b…/subagents/agent-a8893d5dc636697c3.jsonl:300`。
  Python のソースでも確認した

### 6. `reference/TITLE.PNG` のような大文字の絵が「置き場の外」と裁かれる

- **どこ**: `bin/precommit.py:106` `imgs = [p for p in staged if p.lower().endswith(li.IMAGE_EXTS)]`
  と `allowed()` / `go/internal/precommit/`
- **何が起きる**: 絵かどうかの判定は `p.lower()` で大文字小文字を無視するのに、
  許可リストとの照合は大文字小文字を区別する。`reference/TITLE.PNG` は「絵」と見なされる
  のに許可リストに当たらず、正しい置き場にあるのにコミットが止まる
- **実害**: 誤判定（通すべき物を止める）
- **いま**: そのまま写した
- **直すなら**: 許可リストの照合も小文字にそろえる。見本は precommit の 17 件の中
- **出どころ**: `LOG/8869084b….jsonl:1408`、`LOG/8869084b…/subagents/agent-ac3b949fed474c5c2.jsonl:172`。
  Python のソースでも確認した

### 7. `--files` にファイルを 1 つも渡さないと、ステージ全部が裁かれる

- **どこ**: `bin/precommit.py` の `len(sys.argv) > 2` 判定 / `go/internal/precommit/`
- **何が起きる**: `precommit.py --files`（後ろに何も無い）は「対象 0 件」ではなく
  「対象の指定なし＝ステージ全部」に化ける。何も裁かせないつもりがコミット全体が裁かれる
- **実害**: 誤判定（対象を絞ったつもりが絞られていない）
- **いま**: そのまま写した
- **直すなら**: `--files` があれば、後ろが空でも対象 0 件として扱う。見本は precommit の 17 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-ac3b949fed474c5c2.jsonl:172`

### 8. 相対パスで渡すと Genesis の照合が知らせなく飛ばされる

- **どこ**: `bin/check-refs.py` の `find_genesis` の `[:6]` / `go/internal/checkrefs/`
- **何が起きる**: 親をたどる回数を `[:6]` で打ち切っているので、相対パスで渡すと `.` の
  時点で打ち止めになる。深い所にあるバンドルを相対パスで渡すと、Genesis との照合が
  エラーも警告も無しに飛ばされる
- **実害**: 誤判定（検査すべき物が検査されないまま緑になる）
- **いま**: そのまま写した
- **直すなら**: 絶対パスに直してからたどる。見本は check-refs の 28 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-ac84c2acee5d484cc.jsonl:204`

### 9. 索引のどこかに名前があれば「載っている」と見なす

- **どこ**: `bin/check-api-index.py` の `word_in` / `go/internal/apiindex/`
- **何が起きる**: 1 行の紹介が無くても、`Mod.func` という参照やコードブロックの中に
  その語が 1 回出ているだけで「索引に載っている」と判定される
- **実害**: 誤判定（止めるべき物を通す）。索引の抜けを見つけるという狙いに届かない
- **いま**: そのまま写した
- **直すなら**: 紹介の行の形（見出し・表の行）に限って照合する。見本 9 件のうち
  何件が動くかは実際に走らせないと分からない
- **出どころ**: `LOG/8869084b….jsonl:1158`、`LOG/8869084b…/subagents/agent-a35bd48d569100ea4.jsonl:195`

### 10. 色の検査の基準が front ではなく「名前順で最初の方向」になっている

- **どこ**: `bin/lint-anim.py:245` `for d, rows in sorted(views.items())` / `go/internal/anim/`
- **何が起きる**: `back` があると `back` が基準になる。「back にだけ色がある」という
  本当の違反は鳴らず、代わりに front と side が「その方向にだけ色がある」と名指しされる
- **実害**: 誤判定（止めるべき物を通し、通すべき物を止める）。しかも名指しの相手が逆になる
- **いま**: そのまま写した
- **直すなら**: front を基準に固定する。見本は anim の 13 件の中
- **出どころ**: `LOG/8869084b….jsonl:610`、`LOG/8869084b…/subagents/agent-a3d0504e627ff6911.jsonl:122`。
  Python のソースでも確認した

### 11. 上限ちょうどは赤、ドリフト上限ちょうどは緑という境界の食い違い

- **どこ**: `bin/check-render-budget.py:163 付近`（上限は `>=`・ドリフトは `>`）
  / `go/internal/renderbudget/`
- **何が起きる**: 同じ「超えたら赤」のはずの 2 つの判定が、ちょうどの値で逆の答えを出す
- **実害**: 誤判定（境界の値で通す / 止めるが入れ替わる）
- **いま**: そのまま写した
- **直すなら**: どちらかにそろえる。見本 10 件のうち境界ちょうどの物は無いので
  期待値は動かない見込み
- **出どころ**: `LOG/8869084b…/subagents/agent-a5ce9308adcad5b17.jsonl:311`

### 12. `foo.png` という名前のフォルダが「場面」として拾われる

- **どこ**: `bin/check-render-budget.py` の `scene_names`（`os.listdir` の結果を種類で絞らない）
  / `go/internal/renderbudget/`
- **何が起きる**: ファイルかフォルダかを見ないので、`foo.png` という名前のフォルダが
  場面の一覧に入り、サイドカーが無いという注意が出る
- **実害**: 誤判定（本来の対象でない物を対象にする）
- **いま**: そのまま写した
- **直すなら**: フォルダだけを拾う。見本 10 件は動かない見込み
- **出どころ**: `LOG/8869084b…/subagents/agent-a5ce9308adcad5b17.jsonl:311`

### 13. 消えたルールの `.md` が残り続け、`--check` もそれに気づかない

- **どこ**: `bin/gen-rules.py` / `go/internal/genrules/`
- **何が起きる**: `RULES` から 1 本外しても、生成先の古い `.md` は消されない。
  `--check`（生成物とソースのずれを見る検査）もこのずれを見つけられない
- **実害**: 誤判定（止めるべきずれを通す）。取り下げたはずのルールが配布先で生き続ける
- **いま**: そのまま写した
- **直すなら**: 生成先にあって `RULES` に無い `.md` を赤にする。gen-rules には見本が無い
- **出どころ**: `LOG/8869084b….jsonl:1124`、`LOG/8869084b…/subagents/agent-a5ce9308adcad5b17.jsonl:311`

### 14. `--strict` が何も知らせずに捨てられる

- **どこ**: `bin/lint-fallback.py`（`--` で始まる引数を全部捨てる引数処理）/ `go/internal/fallback/`
- **何が起きる**: `lint-fallback --strict` の `--strict` が無視される。
  厳しくしたつもりが、既定の「ステージの差分だけを見る」ままになる
- **実害**: 誤判定（止めるべき物を通す）。`lint-view` にも同じ罠があると記録にある
- **いま**: そのまま写した
- **直すなら**: 知っている旗として受け取る。見本は fallback の 3 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a8f861c0b2b071de6.jsonl:179`

### 15. `"frames": null` で例外落ちする

- **どこ**: `bin/lint-anim.py:264` `spec.get("frames", {})` と `:289` `spec.get("frames") or {}`
  / `go/internal/anim/`
- **何が起きる**: 同じ物を 2 通りに読んでいて、`:264` の方は `null` を既定値へ落とせない。
  `"frames": null` と書いた Doc で `TypeError: 'NoneType' object is not iterable` になる
  （実際に再現したと記録にある）
- **実害**: 検査が結果を出さずに落ちる
- **いま**: そのまま写した
- **直すなら**: 2 か所とも `or {}` にそろえる。見本は anim の 13 件の中
- **出どころ**: `LOG/8869084b….jsonl:610`、`LOG/8869084b…/subagents/agent-a3d0504e627ff6911.jsonl:122`。
  Python のソースでも確認した

### 16. UTF-8 でない `ui.json` で例外落ちする

- **どこ**: `bin/lint-ui-overflow.py` の `open(path, encoding="utf-8")`
  / `go/internal/uioverflow/`
- **何が起きる**: `UnicodeDecodeError` は `ValueError` の仲間で、`OSError` でも
  `JSONDecodeError` でもないので、用意してある `except` をすり抜けて未処理のまま落ちる。
  「読めません」という案内が出るはずの所で Python のトレースバックが出る
- **実害**: 検査が結果を出さずに落ちる
- **いま**: そのまま写した（`go/internal/uioverflow/uioverflow_test.go:198` が字面を固定）
- **直すなら**: `UnicodeDecodeError` も拾う。見本は ui-overflow の 3 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a8f861c0b2b071de6.jsonl:179`

### 17. `"use"` に配列やオブジェクトを書くと例外落ちする

- **どこ**: `bin/lint-ui-overflow.py` の `resolve_use` / `go/internal/uioverflow/`
- **何が起きる**: ハッシュ化できない値を `dict.get` に渡してしまい `TypeError` で落ちる
- **実害**: 検査が結果を出さずに落ちる
- **いま**: そのまま写した
- **直すなら**: 文字列でない `use` を赤にする。見本は ui-overflow の 3 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a8f861c0b2b071de6.jsonl:179`

### 18. git が無い場所で例外落ちする

- **どこ**: `bin/lint-fallback.py` の `git()`（`check=True`）/ `go/internal/fallback/`
- **何が起きる**: git が入っていない機械や、リポでないフォルダで走らせるとトレースバックで落ちる
- **実害**: 検査が結果を出さずに落ちる
- **いま**: そのまま写した
- **直すなら**: git が使えないときは全ファイルを見る側へ落とす。見本は fallback の 3 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a8f861c0b2b071de6.jsonl:179`

### 19. `staged_files()` だけが、失敗したときコミットを止める側になっている

- **どこ**: `bin/precommit.py` の `staged_files()`（`check=True`）/ `go/internal/precommit/`
- **何が起きる**: git が失敗するとトレースバック + 終了コード 1 でコミットが止まる。
  **このファイルの他の 5 経路は全部「失敗したら通す」側**なのに、ここだけ逆
- **実害**: 誤判定（通すべきコミットを止める）
- **いま**: そのまま写した
- **直すなら**: 他の 5 経路と同じく、失敗したら通す。見本は precommit の 17 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-ac3b949fed474c5c2.jsonl:172`

### 20. 実在を見る相手と実際に走らせる相手が違う

- **どこ**: `bin/precommit.py` の `run_lint` / `go/internal/precommit/`
- **何が起きる**: `run_lint` は `bin/<道具>.py` の実在を見てから走らせるかを決めるのに、
  実際に走らせるのは `bin/fge`。`bin/fge` だけが欠けた配布物では `FileNotFoundError` の
  トレースバックが出てコミットが止まる。「無ければ通す」つもりが「無ければ止まる」になっている
- **実害**: 誤判定（通すべきコミットを止める）
- **いま**: 直っている。`7a180747` で「各検査が `bin/<道具>.py` の実在を見てから走る作り」を
  やめた（コミットメッセージの「塞いだ穴」3 つのうちの 1 つ）
- **直すなら**: 済み
- **出どころ**: `LOG/8869084b…/subagents/agent-ac3b949fed474c5c2.jsonl:172`、
  コミット `7a180747` のメッセージ

### 21. `Makefile` / `AGENTS.core.md` が読めないと、違反 1 件と見分けが付かない落ち方をする

- **どこ**: `bin/check-refs.py` の `read_text(encoding="utf-8")`（例外を拾っていない）
  / `go/internal/checkrefs/`
- **何が起きる**: ファイルが無い・UTF-8 でないとき、検査の言葉ではなく Python の
  トレースバックが出る。しかも終了コードが 1 なので、**違反が 1 件見つかったときと
  区別が付かない**
- **実害**: 検査が結果を出さずに落ち、しかもそれが分からない
- **いま**: Go 版はここだけ終了コードを 2 に変えたと記録にある（意図した差）
- **直すなら**: 済み（Go 側）。Python 側の字面を残す必要が無くなったので、案内文も直せる
- **出どころ**: `LOG/8869084b…/subagents/agent-ac84c2acee5d484cc.jsonl:204`

### 22. `manifest.json` の中身がオブジェクトでないと例外落ちする

- **どこ**: `bin/check-refs.py` の `sync_agents_dist`（拾う例外が `(OSError, ValueError)` だけ）
  / `go/internal/checkrefs/`
- **何が起きる**: JSON として正しくても中身が配列だったり、`copy` の要素が辞書でないと
  `AttributeError` でトレースバックする
- **実害**: 検査が結果を出さずに落ちる
- **いま**: そのまま写した
- **直すなら**: 型が違う manifest を赤にする。見本は check-refs の 28 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-ac84c2acee5d484cc.jsonl:204`

### 23. UTF-8 でない索引で例外落ちする

- **どこ**: `bin/check-api-index.py` の `read_text(encoding="utf-8")`（`errors="replace"` が無い）
  / `go/internal/apiindex/`
- **何が起きる**: `UnicodeDecodeError` は `except OSError` に拾われないので、
  「読めません」という案内が出るはずの所でトレースバックが出る
- **実害**: 検査が結果を出さずに落ちる
- **いま**: そのまま写した
- **直すなら**: `errors="replace"` 相当にする。見本は check-api-index の 9 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a35bd48d569100ea4.jsonl:195`

### 24. 「失敗したら通す」と説明文に書いてあるのに、失敗すると落ちる

- **どこ**: `bin/check-api-released.py` の `version()`（`ROOT/Makefile` を例外を拾わずに読む）
  / `go/internal/apireleased/`
- **何が起きる**: `Makefile` が無い配布先では `OSError` でトレースバック。git 自体が
  入っていない機械でも `FileNotFoundError` で落ちる。説明文が約束している
  「失敗したら通す」に届いていない
- **実害**: 誤判定（通すべき物を止める）
- **いま**: そのまま写した
- **直すなら**: `version()` の失敗も「通す」側へ落とす。見本は check-api-released の 9 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a35bd48d569100ea4.jsonl:195`

### 25. manifest が壊れているとき、検査では丁寧な NG が出るのに、配るときは落ちる

- **どこ**: `bin/sync-agents.py` の `sync()`（`load_manifest()` を例外を拾わずに呼ぶ）
  / `go/internal/syncagents/`
- **何が起きる**: `--check-manifest` は読めない理由を文章で出すのに、実際に配るときは
  同じ壊れ方でトレースバック（終了コード 1）になる。同じ形の経路が 4 つある
  （manifest が辞書でない / `agents-pack/skills` が無い / `agents-pack/rules` が無い /
  `.md` が UTF-8 でない）
- **実害**: 検査が結果を出さずに落ちる。配布が途中で止まる
- **いま**: そのまま写した
- **直すなら**: `sync()` も `--check-manifest` と同じ文章を出す。sync-agents には見本が無い
- **出どころ**: `LOG/8869084b….jsonl:1386`、`LOG/8869084b…/subagents/agent-aabc89798b296e5af.jsonl:225`

### 26. `check_manifest()` の例外の拾い方が足りない

- **どこ**: `bin/sync-agents.py` の `check_manifest()`（try が `load_manifest()` しか包んでいない）
  / `go/internal/syncagents/`
- **何が起きる**: その後の `check_skill_links()` は `agents-pack/skills` が無いだけで
  トレースバックする
- **実害**: 検査が結果を出さずに落ちる
- **いま**: そのまま写した
- **直すなら**: try の範囲を広げる。sync-agents には見本が無い
- **出どころ**: `LOG/8869084b…/subagents/agent-aabc89798b296e5af.jsonl:225`

### 27. symlink のフォルダの中身が配られない

- **どこ**: `bin/sync-agents.py` の `copy_dir`（`rglob` は symlink のフォルダへ入らない）
  / `go/internal/syncagents/`
- **何が起きる**: `agents-pack/skills/` の下に symlink のフォルダを置くと、
  配った先には空のフォルダだけができて中身がエラーも出さずに消える
- **実害**: 誤判定（欠けたまま「配った」と表示される）
- **いま**: そのまま写した
- **直すなら**: symlink を追う。sync-agents には見本が無い
- **出どころ**: `LOG/8869084b….jsonl:1386`、`LOG/8869084b…/subagents/agent-aabc89798b296e5af.jsonl:225`

### 28. 壊れた PNG で例外落ちする

- **どこ**: `bin/lint-style.py` の `read_png`（拾う例外が「PNG でない / インターレース /
  8bit 以外」の 3 つだけ）/ `go/internal/style/`
- **何が起きる**: IHDR が欠けている・zlib が壊れているといった壊れ方は `ValueError` に
  ならず、トレースバックで落ちる
- **実害**: 検査が結果を出さずに落ちる
- **いま**: そのまま写した
- **直すなら**: 読み込みの失敗をまとめて拾う。見本は style の 2 件の中
- **出どころ**: `LOG/8869084b….jsonl:1085`、`LOG/8869084b…/subagents/agent-aa246c7713f2a1547.jsonl:172`

### 29. `assets/chars` を作らずに書きに行って、PNG を全部書いた後で落ちる

- **どこ**: `bin/carve/adopt.py`（`os.makedirs` が無い。`carve.py` の方は作っている）
  / `go/internal/carve/adopt.go`
- **何が起きる**: 書き出し先のフォルダが無いと、PNG を全部書き終えた後で
  `FileNotFoundError` になる。途中まで書けた状態が残る
- **実害**: 処理が途中で落ちて、中途半端な生成物が残る
- **いま**: そのまま写した
- **直すなら**: 書く前にフォルダを作る。carve には見本が無い
- **出どころ**: `LOG/8869084b….jsonl:1347`、`LOG/8869084b…/subagents/agent-a9487d9efe108808d.jsonl:292`

### 30. 生成物の書き出し先が `bin/gallery/` `bin/assets/chars/` になっている

- **どこ**: `bin/carve/adopt.py` `render.py` `gifs.py` `sheet.py` の
  `root = os.path.dirname(HERE)`（`HERE` が `bin/carve/` なので親は `bin/`）
  / `go/cmd_carve.go:32` `return filepath.Join(repoRoot(), "bin")`
- **何が起きる**: リポの根の `gallery/` `assets/chars/` ではなく、`bin/` の下に書く。
  4 本とも `bin/carve/` へ移したときの直し忘れ。説明文も今なお `python3 bin/adopt.py` のまま
- **実害**: 生成物が誰も見ない場所に置かれる。31 番と合わせて carve 一式の配線が切れている
- **いま**: そのまま写した（`carveScriptDir()` が `repoRoot()/bin` を返す）
- **直すなら**: `repoRoot()` を直接使う。carve には見本が無い
- **出どころ**: `LOG/8869084b….jsonl:1347`、`LOG/8869084b…/subagents/agent-a9487d9efe108808d.jsonl:292`。
  Python と Go のソースでも確認した

### 31. `gifs` と `sheet` は、このリポの生成物を原理的に拾えない

- **どこ**: `bin/carve/sheet.py:15` `VIEWS = ("front", "east", "back", "west")` と区切り `_`
  / `bin/carve/carve.py:375` は `("front", 0), ("right", 90), ("back", 180), ("left", 270)`
  と区切り `-` / `go/internal/carve/sheet.go:20 SheetViews`
- **何が起きる**: 探す名前と実際に書かれる名前が食い違っている。`carve` / `adopt` が
  書いた絵を `gifs` / `sheet` は 1 枚も見つけられない
- **実害**: この 2 本が完全に働いていない
- **いま**: そのまま写した（Go の `SheetViews` も `front/east/back/west`）
- **直すなら**: `carve.py` 側の名前と区切りにそろえる。carve には見本が無い
- **出どころ**: `LOG/8869084b….jsonl:1347`、`LOG/8869084b…/subagents/agent-a9487d9efe108808d.jsonl:292`。
  Python と Go のソースでも確認した

### 32. パレットが `rgb` 表記のテンプレでは、色の近さの検査がほとんど働いていない

- **どこ**: `bin/lint-sprite.py` の `hex_of_value`（`#rrggbb` しか読めない）
  / `go/internal/sprite/`
- **何が起きる**: `make palette` が生成するパレットは `{"rgb": [0〜1 の 3 つ]}` の形なのに、
  `hex_of_value` は 16 進の文字列しか読めない。`rgb` 表記を使うテンプレ
  （rpg・platformer）では ΔE の検査が実質働かない。試しに `rgb`/`hsv` に対応させたら
  注意が **26 件 → 53 件**に増えた（その多くは、意味の名前が違うだけで実は同じ色 ΔE 0.0 の組）
- **実害**: 誤判定（止めるべき物を通す）
- **いま**: そのまま写した。移行より前に一度直しかけたが「今回の変更の範囲外」として
  戻してある
- **直すなら**: `rgb`/`hsv` 表記も読む。見本は sprite の 12 件の中。
  実リポの注意が 26 → 53 件に増えるので、増えた分をどう扱うかの判断が先に要る
- **出どころ**: `LOG/63138ad7….jsonl:1843-1845`

### 33. `lint-palette.py` が壊れると、色の近さの検査が注意 1 行だけ残して消える

- **どこ**: `bin/lint-sprite.py:72-81`（`lint-palette.py` を動的に読み込む所が
  `except Exception: return None`）/ `go/internal/sprite/`
- **何が起きる**: `lint-palette.py` が壊れると `LP is None` になり `hex_of_value` が
  全部 `None` を返す。ΔE の検査は注意 1 行を出すだけで消え、**検査が死んでも
  終了コードは緑のまま**
- **実害**: 誤判定（止めるべき物を通す）
- **いま**: そのまま写した
- **直すなら**: 読み込みに失敗したら赤にする。見本は sprite の 12 件の中
- **出どころ**: `LOG/63138ad7….jsonl:1692`、`LOG/63138ad7….jsonl:1778-1780`

### 34. ファイル名から画風を当てられないと、判定を丸ごと飛ばす

- **どこ**: `bin/lint-style.py` の `guess_hand` / `go/internal/style/`
- **何が起きる**: ファイル名から画風を推測できないと `judge` に入らない。
  **ファイル名を変えるだけで検査が何も言わなくなる**
- **実害**: 誤判定（止めるべき物を通す）
- **いま**: そのまま写した
- **直すなら**: 画風が分からないときは既定の画風で判定するか、赤にする。
  見本は style の 2 件の中
- **出どころ**: `LOG/63138ad7….jsonl:1762`、`LOG/63138ad7….jsonl:1782`

---

## B: 出力の字面や並び順がおかしい（18 件）

### 35. 面積が減ったコマも「+25% ずれる」と表示される

- **どこ**: `bin/lint-anim.py:161` `drift = abs(...)` と `:164` `f"{drift:+.0%}"`
  / `go/internal/anim/anim.go:428-441`
- **何が起きる**: 絶対値を取った後に符号付きで出すので、痩せたコマも太ったコマも `+` になる。
  読み手はどちらへずれたのか分からない
- **実害**: 見つける判定そのものは合っている。字面だけが誤解を招く
- **いま**: そのまま写した。`go/internal/anim/anim.go:434` に
  「符号を戻して出さないのは、ずれの大きさだけを見せたいため。減った側も + と出るが、
  直すと字面が変わって golden が落ちる」という WhyNot が残っている
- **直すなら**: 符号を残して出す。`testdata/lint/` で「面積が」を含む期待値は **1 件**
- **出どころ**: `LOG/8869084b….jsonl:610`、`LOG/8869084b…/subagents/agent-a3d0504e627ff6911.jsonl:122`。
  Python と Go のソースでも確認した

### 36. `view` の出力の並びが JSON の書き順で変わる

- **どこ**: `bin/lint-anim.py` の `view` の出力 / `go/internal/anim/`
- **何が起きる**: `{'front':5,'side':7}` の並びは Doc に書いた順そのまま。
  中身が同じでもキーを書き換えると出力の字面が変わる
- **実害**: 字面だけ。判定は同じ
- **いま**: そのまま写した
- **直すなら**: 名前順にそろえる。見本は anim の 13 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a3d0504e627ff6911.jsonl:122`

### 37. `note` を書き忘れた `cap` の行に「（既定）」と表示する

- **どこ**: `bin/check-render-budget.py` / `go/internal/renderbudget/`
- **何が起きる**: `note` の無い `cap` の行は赤にした上で、その場面の上限を既定値へ戻し、
  さらに表示上「（既定）」と出す。ファイルには `cap` が書いてあるのに「既定です」と
  出るので読み手が混乱する
- **実害**: 字面だけ。赤にするという判定は合っている
- **いま**: そのまま写した
- **直すなら**: 「note が無いので既定に戻した」と書く。`testdata/lint/` で「（既定）」を
  含む期待値は **2 件**
- **出どころ**: `LOG/8869084b…/subagents/agent-a5ce9308adcad5b17.jsonl:311`

### 38. 案内文に空白の抜けが 2 か所ある

- **どこ**: `bin/check-render-budget.py:163` 付近（暗黙の文字列連結）/ `go/internal/renderbudget/`
- **何が起きる**: 「基準 100 個から300 個を超えて」（「から」の後ろに空白が無い）と
  「ITEMS.caps.tsv にcap と note を」の 2 か所
- **実害**: 字面だけ
- **いま**: そのまま写した
- **直すなら**: 空白を足す。`testdata/lint/` で「個から」は **2 件**、「にcap」は **1 件**
- **出どころ**: `LOG/8869084b…/subagents/agent-a5ce9308adcad5b17.jsonl:311`。
  Python のソースでも確認した

### 39. `NG(render):` の並びが機械によって変わる

- **どこ**: `bin/status.py:94` `glob.glob(os.path.join(".test-logs", "render-*.fail"))`
  （`sorted()` が無い。`.log` の方は付いている）/ `go/internal/status/status.go:174`
- **何が起きる**: OS がフォルダを読む順そのままなので、同じ状態でも機械が違えば並びが変わる
- **実害**: 字面だけ。ただし「同じ検査なのに人によって出力が違う」という、
  この移行そのものが無くそうとしていた問題と同じ形
- **いま**: そのまま写した（Go の `pyGlob` も並べ替えない）
- **直すなら**: `sorted()` を足す。status には見本が無い
- **出どころ**: `LOG/8869084b….jsonl:1288`、`LOG/8869084b…/subagents/agent-a8893d5dc636697c3.jsonl:300`。
  Python と Go のソースでも確認した

### 40. 3 種類の別物を 1 つの数にまとめて出す

- **どこ**: `bin/status.py` の `check_reference` の `bad` / `go/internal/status/`
- **何が起きる**: 「基準にあるのに絵が無い」「絵はあるが基準に無い」「ハッシュが違う」の
  3 つを 1 つの数にする。`他N` の N もこの 3 種類の混ざり物になる
- **実害**: 字面だけ。何が起きているのかが読み手に伝わらない
- **いま**: そのまま写した
- **直すなら**: 3 つを分けて数える。status には見本が無い
- **出どころ**: `LOG/8869084b…/subagents/agent-a8893d5dc636697c3.jsonl:300`

### 41. 検査が例外で落ちても「予算を超えています」と表示する

- **どこ**: `bin/status.py` の `section_budget` / `go/internal/status/`
- **何が起きる**: `check-render-budget` の終了コードが 0 でなければ、理由に関わらず
  「予算を超えています」と出す。例外で落ちた場合も同じ行が出て、しかもトレースバックの
  `  File "…"` が先頭 2 空白なので「詳細 3 行」として並べて表示される
- **実害**: 字面だけ。ただし本当の理由が読めなくなる
- **いま**: そのまま写した
- **直すなら**: 終了コードで理由を分ける。status には見本が無い
- **出どころ**: `LOG/8869084b…/subagents/agent-a8893d5dc636697c3.jsonl:300`

### 42. 更新時刻が未来のファイルを「たった今」と表示する

- **どこ**: `bin/status.py` の `age()` / `go/internal/status/`
- **何が起きる**: 経過時間が負になっても場合分けが無いので「たった今」になる
- **実害**: 字面だけ
- **いま**: そのまま写した
- **直すなら**: 負のときは別の言葉にする。status には見本が無い
- **出どころ**: `LOG/8869084b…/subagents/agent-a8893d5dc636697c3.jsonl:300`

### 43. `#!/bin/sh` が `!/bin/sh` になる

- **どこ**: `bin/status.py:54` `s = line.strip().lstrip("#").strip()` / `go/internal/status/`
- **何が起きる**: 先頭の `#` を全部取るので、シバンの行を表示すると `!` から始まる
- **実害**: 字面だけ
- **いま**: そのまま写した
- **直すなら**: 見出しの行だけに当てる。status には見本が無い
- **出どころ**: `LOG/8869084b…/subagents/agent-a8893d5dc636697c3.jsonl:300`。
  Python のソースでも確認した

### 44. 同じフックが 2 回書いてあると、同じ問題行が 2 回出る

- **どこ**: `bin/check-refs.py` の `check_agents_pack`（重複をまとめない。
  バンドル側の `hooks_in_settings` は `set` でまとめているので非対称）/ `go/internal/checkrefs/`
- **何が起きる**: `settings.json` が同じフックを 2 回名指しすると、同じ指摘が 2 行出る
- **実害**: 字面だけ
- **いま**: そのまま写した
- **直すなら**: 重複をまとめる。見本は check-refs の 28 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-ac84c2acee5d484cc.jsonl:204`

### 45. 索引が読めないと、その手前で集めた「除外:」の行が出ないまま終わる

- **どこ**: `bin/check-api-index.py` の早期 return / `go/internal/apiindex/`
- **何が起きる**: 2 つ目の索引が読めないと、1 つ目で集めた「除外:」を出さずに終了コード 1 で終わる
- **実害**: 字面だけ（何を除外したのかが分からなくなる）
- **いま**: そのまま写した
- **直すなら**: 集めた分を先に出す。`testdata/lint/` で「除外:」を含む期待値は **6 件**
- **出どころ**: `LOG/8869084b…/subagents/agent-a35bd48d569100ea4.jsonl:195`

### 46. 除外したモジュールが 2 つの対象の下にあると、2 回出て 2 回数える

- **どこ**: `bin/check-api-index.py` の EXEMPT の扱い / `go/internal/apiindex/`
- **何が起きる**: 同じモジュールが 2 つの対象フォルダの下に見つかると「除外」が 2 行出て、
  件数も 2 として数えられる
- **実害**: 字面と件数。赤か緑かは変わらない
- **いま**: そのまま写した
- **直すなら**: モジュール名でまとめる。「除外:」を含む期待値 **6 件**の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a35bd48d569100ea4.jsonl:195`

### 47. 説明文の引用符の閉じ忘れを、片側だけ取って通す

- **どこ**: `bin/sync-agents.py` の `skill_description` / `go/internal/syncagents/`
- **何が起きる**: `description: "abc`（閉じ忘れ）が、エラーも出さずに `abc` になる
- **実害**: 字面だけ。書き手の誤りに気づけない
- **いま**: そのまま写した
- **直すなら**: 片側だけの引用符を赤にする。sync-agents には見本が無い
- **出どころ**: `LOG/8869084b…/subagents/agent-aabc89798b296e5af.jsonl:225`

### 48. 説明文に句点を勝手に足す

- **どこ**: `bin/sync-agents.py` の `trigger_sentence` / `go/internal/syncagents/`
- **何が起きる**: 「。」で終わっていない説明文の後ろに「。」を足す
- **実害**: 字面だけ
- **いま**: そのまま写した
- **直すなら**: 足さない。sync-agents には見本が無い
- **出どころ**: `LOG/8869084b…/subagents/agent-aabc89798b296e5af.jsonl:225`

### 49. manifest から外しても「配った」と表示し続ける

- **どこ**: `bin/sync-agents.py` の `[sync-agents] skill:` の行 / `go/internal/syncagents/`
- **何が起きる**: この行は `copyDirs` の中身と関係なく `agents-pack/skills` から作るので、
  manifest から skills を外しても「配った」と出る
- **実害**: 字面だけ。ただし表示が事実と違う
- **いま**: そのまま写した
- **直すなら**: 実際に配った物から作る。sync-agents には見本が無い
- **出どころ**: `LOG/8869084b…/subagents/agent-aabc89798b296e5af.jsonl:225`

### 50. 値を書き忘れたときのエラーが「知らないオプション」になる

- **どこ**: `bin/lint-style.py` の引数処理 / `go/internal/style/`
- **何が起きる**: `--hand` や `--unit` の後ろに値を書き忘れると、「値がありません」ではなく
  `知らないオプション: --hand` と出る。書いたはずのオプションを知らないと言われる
- **実害**: 字面だけ
- **いま**: そのまま写した
- **直すなら**: 値の無いオプションを別の言葉にする。`testdata/lint/` で
  「知らないオプション」を含む期待値は **0 件**なので、見本は動かない
- **出どころ**: `LOG/8869084b…/subagents/agent-aa246c7713f2a1547.jsonl:172`

### 51. `--bundle` の後ろが旗でも値として受け取る

- **どこ**: `bin/check-refs.py` の引数処理 / `go/internal/checkrefs/`
- **何が起きる**: `check-refs.py --bundle --windows` は `bundle_dir = "--windows"` になり、
  「バンドルが見つかりません: --windows」と出る。使い方の誤りとして案内されない
- **実害**: 字面だけ
- **いま**: そのまま写した
- **直すなら**: 次が `--` で始まるなら値が無いと判断する。`testdata/lint/` で
  「バンドルが見つかりません」を含む期待値は **1 件**
- **出どころ**: `LOG/8869084b…/subagents/agent-ac84c2acee5d484cc.jsonl:204`

### 52. 生成物のメモに実在しないパスを書く

- **どこ**: `bin/carve/carve.py` が `sprite.json` へ書く note / `go/internal/carve/carve.go`
- **何が起きる**: 「`bin/carve.py` の生成物」と書くが、実体は `bin/carve/carve.py`
- **実害**: 字面だけ
- **いま**: そのまま写した
- **直すなら**: 正しいパスにする。carve には見本が無い
- **出どころ**: `LOG/8869084b…/subagents/agent-a9487d9efe108808d.jsonl:292`

---

## C: 理屈上おかしいだけで、いまの使い方では表に出ない（22 件）

### 53. 背面図を組み立ててから捨てている

- **どこ**: `bin/carve/carve.py:137-141`
  （`if back_xs and x not in back_xs and len(back_xs) > 2: pass`）/ `go/internal/carve/carve.go:112-131`
- **何が起きる**: コメントは「背面にも有る x だけ残す」と書いてあるのに、中身が `pass` なので
  彫り出す結果に一切反映されない
- **実害**: 無し（何もしないので結果は変わらない）
- **いま**: Go は写していない。何もしないコードなので落としても結果が同じになる
  （`Carve` に `backXs` が無い）
- **直すなら**: コメントに合わせて実装するか、コードごと取り下げる。carve には見本が無い
- **出どころ**: `LOG/8869084b….jsonl:1347`、`LOG/8869084b…/subagents/agent-a9487d9efe108808d.jsonl:292`。
  Python と Go のソースでも確認した

### 54. 結果を使わないループがある

- **どこ**: `bin/carve/adopt.py`
  （`for pose in ("idle",): strip = []; for k in (1,2,3): strip.append(k)`）/ `go/internal/carve/adopt.go`
- **何が起きる**: 作ったリストをどこにも使っていない
- **実害**: 無し
- **いま**: 判断保留（Go 側に同じ形があるかは確認していない）
- **直すなら**: 取り下げる。carve には見本が無い
- **出どころ**: `LOG/8869084b…/subagents/agent-a9487d9efe108808d.jsonl:292`

### 55. 同じ枝が 2 回書いてある

- **どこ**: `bin/carve/png_read.py` の `_unfilter`（`elif filt == 2` が 2 回）
  / `go/internal/carve/pngread.go`
- **何が起きる**: 2 つ目には決して届かない。中身は同じなので結果は変わらない
- **実害**: 無し
- **いま**: 判断保留
- **直すなら**: 片方を取り下げる。carve には見本が無い
- **出どころ**: `LOG/8869084b…/subagents/agent-a9487d9efe108808d.jsonl:292`

### 56. legend の値が辞書だと例外になりうる

- **どこ**: `bin/carve/render.py` の `hex_of` / `go/internal/carve/render.go`
- **何が起きる**: legend の値が辞書で `hex` `color` `value` のどれも持たないと
  `palette.get(dict)` に落ちて `TypeError` になる。いまは `direct or …` の短絡で
  そこまで届かない
- **実害**: 無し（今の Doc の書き方では届かない）
- **いま**: そのまま写した
- **直すなら**: 辞書の値を先に弾く。carve には見本が無い
- **出どころ**: `LOG/8869084b…/subagents/agent-a9487d9efe108808d.jsonl:292`

### 57. `change_share` のゆとり ±2px が画素の大きさに追随しない

- **どこ**: `bin/lint-anim.py` の `slack=2` / `go/internal/anim/`
- **何が起きる**: 閾値のコメントは「64px 級なら px 系を 2 倍に」と言っているのに
  `slack` は 2 のまま。64px 級では 2px しか吸収できず、`pop` が鳴りやすい側へ寄る
- **実害**: 今のリポには 64px 級のキャラが無いので表に出ない
- **いま**: そのまま写した
- **直すなら**: 画素の大きさに合わせて `slack` を変える。見本は anim の 13 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a3d0504e627ff6911.jsonl:122`

### 58. 左右反転の判定だけが別のデータを見ている

- **どこ**: `bin/lint-anim.py`（他の判定は `masks` を見るのに、ここだけ `views` を見る）
  / `go/internal/anim/`
- **何が起きる**: 直後に `if east and west` があるので結果は変わらない。
  読む人を必ず誤らせる非対称さだけが残っている
- **実害**: 無し
- **いま**: そのまま写した
- **直すなら**: `masks` にそろえる。見本は anim の 13 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a3d0504e627ff6911.jsonl:122`

### 59. `view` の判定が各 sprite の最初のコマ 1 枚しか見ない

- **どこ**: `bin/lint-anim.py` の `view` / `go/internal/anim/`
- **何が起きる**: `walk_0` `walk_1` … があっても比べるのは Doc に最初に書かれた 1 枚だけ。
  歩きの途中のコマで接地がそろっていなくても見つけられない
- **実害**: 取りこぼしはあるが、いまのリポでは `view` 自体が 1 度も鳴っていない
- **いま**: そのまま写した
- **直すなら**: 全コマを見る。見本は anim の 13 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a3d0504e627ff6911.jsonl:122`

### 60. `ground` は相対で見るので「全コマが同じだけ浮いている」を見つけられない

- **どこ**: `bin/lint-anim.py` の `ground`（`floor` を一番下の行の最大値として取る）
  / `go/internal/anim/`
- **何が起きる**: 全部のコマが同じ高さで浮いていると、ずれが 0 になって鳴らない。
  `bob` が絶対座標を見るのと非対称
- **実害**: 取りこぼし。いまのリポでは鳴っていない
- **いま**: そのまま写した
- **直すなら**: 絶対座標で見る。見本は anim の 13 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a3d0504e627ff6911.jsonl:122`

### 61. `--gate` のときパスの基準がリポの根とカレントで混ざっている

- **どこ**: `bin/check-render-budget.py` の `--gate` / `go/internal/renderbudget/`
- **何が起きる**: gallery はリポの根から、基準の tsv はカレントから解く。
  呼ぶ場所によって見る先が変わる
- **実害**: いまは常にリポの根から呼ぶので表に出ない
- **いま**: そのまま写した
- **直すなら**: どちらかにそろえる。見本は check-render-budget の 10 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a5ce9308adcad5b17.jsonl:311`

### 62. 元の doc が 1 本無いと、書きかけの状態で終わる

- **どこ**: `bin/gen-rules.py` / `go/internal/genrules/`
- **何が起きる**: その手前まで書いた状態で `return 1` する。`.claude/rules` には新しい物、
  `agents-pack/rules` には古い物が残る食い違った状態になる
- **実害**: doc が欠けることが無いので今は表に出ない
- **いま**: そのまま写した
- **直すなら**: 全部読めてから書き始める。gen-rules には見本が無い
- **出どころ**: `LOG/8869084b…/subagents/agent-a5ce9308adcad5b17.jsonl:311`

### 63. `--check` が同じファイルの存在確認を 6 回する

- **どこ**: `bin/gen-rules.py`（doc の存在確認が `OUT_DIRS` のループの内側にある）
  / `go/internal/genrules/`
- **何が起きる**: 同じ `stat` を 6 回打つ
- **実害**: 無し（速さの話だけ）
- **いま**: そのまま写した
- **直すなら**: ループの外へ出す。gen-rules には見本が無い
- **出どころ**: `LOG/8869084b…/subagents/agent-a5ce9308adcad5b17.jsonl:311`

### 64. `md` `sh` `py` という名前の pub def が永久に照合されない

- **どこ**: `bin/check-api-index.py` の `FILE_EXTS` の判定（関数名の側だけを見る）
  / `go/internal/apiindex/`
- **何が起きる**: 拡張子と同じ名前の関数を書くと、索引との照合から外れる
- **実害**: そういう名前の関数がいま無いので表に出ない
- **いま**: そのまま写した
- **直すなら**: ファイル名の側を見る。見本は check-api-index の 9 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a35bd48d569100ea4.jsonl:195`

### 65. 字下げした `mod` の中の宣言が、作業ツリー側からもタグ側からも見えない

- **どこ**: `bin/check-api-released.py`（作業ツリー側は `re.split` で平ら、
  タグ側は `git grep` の 1 行ずつと、別々の読み方をしている）/ `go/internal/apireleased/`
- **何が起きる**: 字下げした `mod` の中に書いた宣言はどちらの読み方でも拾われず、
  検査から外れる
- **実害**: いまのコードに字下げした `mod` が無いので表に出ない
- **いま**: そのまま写した
- **直すなら**: 読み方を 1 つにそろえる。見本は check-api-released の 9 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a35bd48d569100ea4.jsonl:195`

### 66. 空の検索語が全件に当たる

- **どこ**: `bin/check-api-released.py`（空文字は `None` ではないので絞り込みが働かない）
  / `go/internal/apireleased/`
- **何が起きる**: `check-api-released ""` が全件に当たる
- **実害**: そんな呼び方をしないので表に出ない
- **いま**: そのまま写した
- **直すなら**: 空文字を絞り込み無しとして扱う。見本は check-api-released の 9 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a35bd48d569100ea4.jsonl:195`

### 67. 親フォルダをたどるときに 1 階層抜ける

- **どこ**: `bin/check-refs.py` の `sync_agents_dist`
  （`re.sub(r"/[^/]+$", "", rel)` の後で `while "/" in parent`）/ `go/internal/checkrefs/`
- **何が起きる**: `bin/githooks/pre-commit` からは `bin/githooks` は判定に入るが `bin` は
  入らない。`bin/fge` のように 1 階層しかないパスの親も入らない
- **実害**: 「フォルダを指す参照も配布済みとして扱う」という狙いが、パスの深さで変わる。
  いまの配布物では表に出ない
- **いま**: そのまま写した
- **直すなら**: 根まで全部たどる。見本は check-refs の 28 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-ac84c2acee5d484cc.jsonl:204`

### 68. `bug!` を付ける相手が実装の都合でずれることがある

- **どこ**: `bin/lint-fallback.py` の `scan` / `go/internal/fallback/`
- **何が起きる**: 囲んでいる def と同じ深さに書いた `bug!` を、外側の関数（無ければ `?`）に
  付ける。`elif BUG.search(...)` の前にスタックを取り出しているため
- **実害**: 記録は「狙い通りとも読める」と留保している
- **いま**: そのまま写した
- **直すなら**: 判断が先に要る。見本は fallback の 3 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a8f861c0b2b071de6.jsonl:179`

### 69. 同じ相対パスが 2 つの別ファイルを指しうる

- **どこ**: `bin/lint-fallback.py` の `read_file`（まずカレント基準、次にリポの根の基準で解く）
  / `go/internal/fallback/`
- **何が起きる**: リポの根から呼べば 1 通りに決まるが、別の場所から呼ぶと同じ文字列が
  違うファイルを指す
- **実害**: いまは常にリポの根から呼ぶので表に出ない
- **いま**: そのまま写した
- **直すなら**: どちらかにそろえる。見本は fallback の 3 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-a8f861c0b2b071de6.jsonl:179`

### 70. `--strict` が緑のときだけ反映される

- **どこ**: `bin/lint-style.py` / `go/internal/style/`
- **何が起きる**: NG があるときは `strict` を見ないので、`--strict` の有無で結果が変わるのは
  注意だけのときに限られる
- **実害**: 記録は「意図どおりかもしれないが、名前からは読めない」と留保している
- **いま**: そのまま写した
- **直すなら**: 判断が先に要る。見本は style の 2 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-aa246c7713f2a1547.jsonl:172`

### 71. `--unit 0` や `--unit -3` を受け取ってしまう

- **どこ**: `bin/lint-style.py` の引数処理 / `go/internal/style/`
- **何が起きる**: `int()` が通れば何でも受け取る。`grid_score` が `None` を返して
  「格子適合 —」と `unit=0` が並び、自動判定にも落ちない
- **実害**: そんな値を渡さないので表に出ない
- **いま**: そのまま写した（`go/internal/style/measure_test.go:42` が
  「unit=1 で格子適合率が出ている (Python は None)」を固定している）
- **直すなら**: 1 未満を弾く。見本は style の 2 件の中
- **出どころ**: `LOG/8869084b…/subagents/agent-aa246c7713f2a1547.jsonl:172`

### 72. `local.mk` の探し始めが 2 つの関数で食い違い、説明文が事実と違う

- **どこ**: `bin/fge` の `read_engine_dir`（リポの根から読む）と
  `bin/status.py` の同名の関数（カレントから読む）/ `go/internal/status/`
- **何が起きる**: `bin/fge` の説明文は「bin/status.py と同じ解決順」と書いているが、
  実際には違う。呼ぶ場所によって engine の場所が変わりうる
- **実害**: いまは常にリポの根から呼ぶので表に出ない
- **いま**: そのまま写した
- **直すなら**: どちらかにそろえて説明文も直す。status には見本が無い
- **出どころ**: `LOG/8869084b…/subagents/agent-a8893d5dc636697c3.jsonl:300`

### 73. 見出しの数え方がコードブロックや引用の中まで数える

- **どこ**: `bin/status.py` の `section_style` の `line.startswith("## この")`
  / `go/internal/status/`
- **何が起きる**: コードブロックの中や引用の中に書いた見出しも数に入る
- **実害**: いまの `AGENTS.local.md` にそういう行が無いので表に出ない
- **いま**: そのまま写した
- **直すなら**: コードブロックの中を除く。status には見本が無い
- **出どころ**: `LOG/8869084b…/subagents/agent-a8893d5dc636697c3.jsonl:300`

### 74. `lint-jargon --self-test` が Makefile から 1 度も呼ばれていない

- **どこ**: `bin/lint-jargon.py --self-test`（`make` は `--all` しか呼ばない）
  / `go/internal/jargon/`
- **何が起きる**: `--self-test` を持つ 7 本のうち 6 本は `make` から走るのに、
  一番手厚い（20 個の assert とルール数の上限を見る）jargon の分だけ走らない
- **実害**: 検査そのものの退行を捕まえられない。記録は「おそらく意図しない配線漏れ」としている
- **いま**: Go では `go/internal/jargon/` の単体テストが引き継いでいる。
  `testdata/lint/jargon/` にも 19 件の見本がある
- **直すなら**: 済みと見てよい
- **出どころ**: `LOG/ea774b8f….jsonl`（`older_ab` の 3610 行目・3648 行目の断片）

---

## 併せて記録に残っていた「配線」の問題（上の 74 件とは別）

不具合というより、検査が呼ばれていない・呼べない話。数には入れていない。

- **`lint-composition.py`（534 行）は 1 度も動いたことが無い。** 入力の
  `debug/thumb/*-figure.png` を書き出す `make thumb` がどのコミットにも存在せず、
  Python の出力が 1 度も取れない。よってバイト一致の比較も原理的に組めなかった。
  **Go へは移さず削除した**（`go/` に composition は無い）。
  出どころ: `LOG/8869084b….jsonl:278`
- **`lint-anim.py`（419 行・7 ルール）は実リポで 1 度も鳴っていない。**
  `loop`（輪の継ぎ目）と `view` の失敗側は `--self-test` にも例が無く、
  コードが 1 度も実行されたことが無かった。移行で負の見本 13 件を作って埋めた。
  出どころ: `LOG/8869084b….jsonl:610`、`LOG/8869084b…/subagents/agent-a234702423e0991a1.jsonl:83`
- **`lint-sprite` / `lint-anim` / `lint-style` / `lint-composition` / `lint-loop` の 5 本
  （3,300 行・`bin/` の Python の 45%）が、保存時のフックにもコミット時のゲートにも
  配線されていなかった。** `*.sprite.json` を保存して実際に走るのは `lint-palette` だけで、
  AGENTS.md の記述と食い違っていた。
  出どころ: `LOG/63138ad7….jsonl:1770-1776`
- **`lint-fallback` と `lint-f32` は違反の判定に 1 度も到達していない。**
  `bug!` 23 件・`Float32` 1 件が全部 EXEMPT に吸収されていた。
  出どころ: `LOG/8869084b….jsonl`（NOTES.md の棚卸しの表と同じ内容）
- **`lint-jargon` の error 段階の語 14 個のうち 13 個が 0 回。** しかも
  `器` `札` `降ろす` `拍` は否定の先読みを使っていて、Go の RE2 には後読みが無い。
  `bin/lint-rules/jargon.json` の note にこの読み替えが書いてある。
  出どころ: `NOTES.md:222` の棚卸し
- **`check-api-released` は判定の本体に到達していない。** `git タグ v0.30.0` が無いので
  `declarations_in_release` が `None` を返し、「失敗したら通す」経路で終わっていた。
  出どころ: `LOG/8869084b…/subagents/agent-ac9edf296503ae5ca.jsonl:48`
- **`docs/checkd.md` は「load 平均が CPU 数の 2 倍を超えたら見送る」と書いているが、
  実装は 1 倍（`> NumCPU()`）。** doc と実装の食い違い。
  出どころ: `LOG/8869084b…/subagents/agent-aab8ff05a2d3e754e.jsonl:1`

---

## 未確認（記録はあるが、確証が足りない物）

1. **`lint-sprite.py` の `delta_e()` が CIEDE2000 ではなく CIE76 だった。**
   閾値 `DELTA_E_MIN = 5.0` は CIEDE2000 の目安として語られる数字で、CIE76 は
   彩度の高い色（特に青系）で差を大きく見積もる。鮮やかな青 2 色が「十分離れている」と
   誤判定されて通っていた。**ただしこれは Go 移行より前にコミット `e16e8a38`
   「色の近さを CIEDE2000 で測り、塊の分裂を見る」で直っている**ので、
   Go へは引き継がれていないはず。移行時点で残っていたかを確かめていない。
   出どころ: `LOG/63138ad7….jsonl:1649`
2. **`lint-sprite.py` の `jaggy_count()` が内側の輪郭（穴のふち）を取りこぼす。**
   最外郭の高さの列しか見ておらず、1 列に複数の塊があるときの奥側も落ちる。
   記録は「仕様上の割り切り」と評していて、不具合とは言い切っていない。
   出どころ: `LOG/63138ad7…/subagents/agent-a28e1320b9145a16a.jsonl:3444`
3. **`bin/status.py:253` 付近のバージョンの刻印の検査が、読めないときに何も言わない。**
   `agents-pack (engine vX)` を正規表現で拾って engine の `VERSION` と比べる作りだが、
   拾えないときの場合分けが無い。誤って鳴った例は記録に無い。
   出どころ: `LOG/ea774b8f….jsonl`（`older_ab` の 3520 行目の断片）
4. **`check-refs.py` の `strip_mk_comments` が入れ子の引用符・複数行の文字列に対応していない。**
   「素朴な正規表現」と評されているが、実際に誤判定した例は記録に無い。
   出どころ: `LOG/8869084b…/subagents/agent-a2cadae5be848bc97.jsonl:21`
5. **`lint-sprite` の `orphan` と `connect` が閾値の偶然の一致で必ず同時に鳴る。**
   「1 ケース 1 ルールにしたくても物理的に不可能」という作りの癖として記録されているが、
   誤判定を生むとは書かれていない。
   出どころ: `LOG/8869084b…/subagents/agent-a234702423e0991a1.jsonl:269`
6. **`lint-sprite` の `structure` の 2 つの下位ケース（`rows` が配列でない・`frames` の
   キーが無い）が、実リポにも `--self-test` にも例が無い。** 未検証というだけで、
   誤判定の記録は無い。
   出どころ: `LOG/8869084b…/subagents/agent-a234702423e0991a1.jsonl:83`

---

## この一覧の限界

- **「50 件超」という数は裏が取れていない。** 掘って確証を持って拾えたのが 74 件で、
  記録に書かれた数より多い。ただし数え方（`lint-anim` の 8 件を 1 件と数えるか 8 件と
  数えるか）で増減するので、この 74 という数もそこまで固い物ではない
- **1 件ずつの「直すなら」で挙げた見本の件数は、字面を `grep` した数**。実際に直して
  走らせるまで正確な数は分からない。`grep` で数えた物にはその旨を書いた
- **`status` `carve` `sync-agents` `gen-rules` `api-digest` には見本が 1 件も無い。**
  この 5 本（全 74 件のうち 21 件）は直しても `testdata/lint/` が動かない代わりに、
  直した結果が正しいかを機械で確かめる手立ても無い
- **移行の最初の方（`ea774b8f` `4bf17586` の 2 セッション）の記録は薄い。**
  この 2 つから拾えたのは `lint-sprite` と `lint-style` の数件だけで、
  ここで見つかった物が他にもあった可能性は残る
