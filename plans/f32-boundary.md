# ゲームを書く側から Float32 を消す — 計画

## 問題

**性能の話ではない。手戻りの話。**

Flix のデフォルトは Float64（`1.0` は Float64、Float32 には `1.0f32` サフィックスが要る）。
ゲームを書いていると、型が合わないコンパイルエラーで初めて「ここは Float32 だった」と分かり、
`f32` を足して再コンパイル、という往復が生じる。

目標は「**App（ゲーム）側は Float64 と Int32 だけ書けばよく、Float32 への変換は
エンジンの入り口・出口だけでやる**」。

## 現状の数字

templates 6 本の `f32` リテラルは **91 箇所**。外部の実利用リポでは **約 95 行 + α**。

| 出どころ | templates | 外部 |
|---|---|---|
| alpha 群（`GradVertex` ほか 20 の pub 宣言） | 51 | fbo_lab 43 / harbor_town 23 / internet_dungeon 14 / town_lab 13 |
| `Color` をレコード直書き | 36 | 各リポの ThemeDoc / Palette に散在 |
| 音（`Sustain` / `Audio.setVolume` ほか） | 4 | internet_dungeon 2 ほか |

`docs/api-digest/*.md` を数えると、**pub 宣言に `Float32` が出るのは 26 件**。これが全体像。

`Int32.toFloat64` は templates に 165 箇所あるが、**ほとんどは「タイル座標（Int32）→
画素座標（Float64）」で型として正しい区別**なので触らない。

---

## 案

### 案 A — 効果の大きい 3 フィールドだけ直す

外部 15 リポを壊す代償を払って、**pub 面に 20 箇所以上の Float32 が残る**。
規則が「この 3 つだけ Float64」では検査対象を定義できず、機械で防げない。**採らない。**

### 案 B — pub 面から Float32 を全部消す（1 リリースで）

規則は立つが **11〜12 日の大工事**で、途中で止まると「alpha は Float64、Color は Float32、
音は未定」という**言葉にできない状態**になる。案 A を「中途半端」として退けた論法が、
そのまま自分に返ってくる。**採らない。**

### 案 C — pub 面から Float32 を消す。ただし 2 リリースに割る（**推薦**）

規則「**エンジンの pub 面に Float32 を出さない。Float32 は GL / OpenAL / STB の境界の内側だけ**」を
立て、それを `bin/lint-f32.py` で機械が裁く。**ただし `Color` は 2 本目のリリースへ回し、
1 本目では lint の EXEMPT に 1 件だけ残して「宿題の一覧」にする**
（`bin/lint-fallback.py` の EXEMPT が既にこの使い方をしている）。

- **0.24.0** — alpha 群 + 音 + lint 導入（7 日）。templates の 91 → **40**（51 箇所が消える）
- **0.25.0** — `Color`（4〜5 日）。40 → **0**

割る理由は 3 つ。

1. **絵が変わる範囲が 1 対 1 で追える。** 後述のとおり両方の段階で reference が割れる。
   1 リリースにまとめると、割れた絵がどちらの変更のせいか分離できない（`make diff` は
   前と後の 2 状態しか比べられない）
2. **外部リポの追随の手間が違う。** alpha は `f32` を 1 トークン消すだけ。
   `Color` のレコード直書きは 3 箇所を同時に直す。分ければ「今回は alpha だけ」と案内できる
3. **Color を後回しにしても規則は立つ。** lint に 1 件 EXEMPT を置けば、
   それがそのまま次リリースの宿題になる

**「今回の変更でおおかた防げるか」への答え**: 案 C なら防げる。**lint が裁くので、
skill への「Float32 は慎重に」という追記は不要**。むしろ既存の記述
（`.claude/rules/flix.md` 末尾の「Float32 が要る所のリテラルには `f32` サフィックスが要る」と
`.claude/skills/compile-fix` の description）は**古くなるので消す作業が要る**。

---

## 段階 — 「層で切る」のではなく「群を縦に貫く」

層（engine → engine_world → templates）で切ると、その間ずっと templates が型エラーで赤くなり、
**全量ゲート `make test-par` が使えない**。群ごとに全パッケージを貫いて、
**各段階の終わりで `make test-par` が緑**になる形にする。

### リリース 1 本目（0.23.5 → 0.24.0）

| 段階 | 内容 | 日 |
|---|---|---|
| 0 | `bin/lint-f32.py` + `make lint-f32` 配線。この時点では違反 26 件を全部 EXEMPT に入れて緑 | 0.5 |
| 1 | **alpha 群を縦に貫く** — engine 8 宣言 / `engine_world` の `Render.flix` 10 箇所 + `UiWidget` + `UiShape` + `UiStore` + `UiDoc` / `render_gl` の `Frame`・`Sprite`・**`Render.flix:23`** / `engine_tools` の `SoftRaster.lerp3` 分割 / **`editor_server`（23 件）** / **`bench/gl_parity` + `bench/sprite_stress`（14 件）** / templates 6 本の 51 箇所 | 3 |
| 2 | 段階 1 で割れた reference の焼き直しと目視（本命は race-starter） | 0.5 |
| 3 | **音を縦に貫く** — `Sustain` / `Audio.setVolume,setPitch,setMasterVolume`（eff の op）/ `AudioStreamPlayer` / `LwjglLayer` の `Float32.max` クランプ / templates 4 箇所 | 1 |
| 4 | シーングラフ `setAlpha` 群（`Rect` / `Arc` / `Polygon` / `drawable/Sprite`） | 0.5 |
| 5 | lint の EXEMPT を `Color` 関連だけに絞り、pre-commit へ配線 | 0.5 |
| 6 | 版上げ・`make api-digest`・docs 追随（`.claude/rules/flix.md` と compile-fix の古い記述を消す）・NOTES.md・リリース | 1 |
| | **合計** | **7** |

### リリース 2 本目（0.24.0 → 0.25.0）

| 段階 | 内容 | 日 |
|---|---|---|
| 7 | `Color` の r/g/b を Float64 に。engine 全域へ波及（`Color.flix` / `ShaderEval` の `mixColor`・`cosColor`・`gradientColor` / `Daylight` / `Material` / `SoftRaster` の `awtColor`・`byteOf` / `Frame.flix`）+ templates 36 箇所 | 1.5 |
| 8 | **割れた reference 26 枚を 1 枚ずつ判定**（精度が上がった結果か、間違いか） | 1.5〜2.5 |
| 9 | lint の EXEMPT を空にする。版上げ・リリース | 1 |
| | **合計** | **4〜5** |

**段階 8 が 2 本目の本体**。実装は 1.5 日で終わるが、絵の判定がその倍かかる。

`Color` の中でも**危ない API と安全な API を分ける**:

- **安全（値が 1 ビットも変わらない）**: `rgb` / `rgb8` / `hex` / `hsv`。
  今も Float64 で計算して最後に 1 回丸めるだけなので、丸めの回数が変わらない
- **危ない（丸めの回数が変わる）**: `mix` / `lighten` / `darken` / `warm` / `cool` と、
  `ShaderEval` / `Daylight` の補間。ここだけ慎重に見る

各段階の前に `make sync`（`sync-engine → sync-render-gl → sync-engine-world → sync-engine-tools →
sync-engine-full` の順序依存がある。部分 sync だと「engine は Float64、fpkg は Float32」で
意味の分からないエラーになる）。

---

## 検証 — 「SHA 全一致」は合格線にならない

**当初この計画は「値を変えないので 5 テンプレの reference SHA が全部一致するのが合格線」と
書いていたが、これは誤り。両方の段階で割れる。**

`engine_tools/src/SoftRaster.flix:939-941` の `lerp3` は
`f32(w0*f64(a) + w1*f64(b) + w2*f64(c))` の形で**色と alpha を共用**している。
alpha が Float64 になると最後の `f32()` が消え、出口の 8bit 量子化
（`byteOf`:966 の `round(値 × 255)`）で丸め境界をまたぐ画素が出る。

実測（レビューで tetris の `gradient` 背景を 120 万サンプル）:
**1 枚の PNG につき 3.8 チャンネル前後が変わる。**

| 段階 | 割れる見込み | 理由 |
|---|---|---|
| 段階 1（alpha） | **race-starter 8 枚**が本命 | `ViewRoad.flix` が大きなグラデーションを敷いている |
| 段階 7（Color） | **tetris-starter 5 枚**は確実 | `tetris.shader.json` の `gradient` は field が連続値 |
| | rpg / novel / platformer は割れない見込み | rpg の `town.shader.json` は field が `quantize` を通っていて色の候補が離散 |

**合格線を差し替える**: SHA 全一致ではなく、**`bin/img-digest.py` の差が数画素以内、
かつ `make diff` で目視して同一に見えること**。割れた枚数が事前の見込み
（race 8 / tetris 5）を超えたら止めて原因を見る。

その他のゲート: `make test-par`（`editor_server` と templates を含む）、
`make gl-parity`（`bench/gl_parity` が対象。段階 1 で bench 自体を直すので必須）、
`make lint-f32`、`make check-docs-sync`。

---

## lint の作り方

写経元は `bin/lint-fallback.py` **ではなく** `bin/gen-api-digest.py`。理由は 2 つ:

- lint-fallback は「関数の**本体**にある `bug!`」を探すのでインデントを追うだけで済む。
  今回要るのは**宣言のシグネチャ**で、`pub type alias GradVertex = { ..., alpha = Float32 }` は
  複数行にまたがる
- **`pub eff Audio { def setVolume(...) }` の op には `pub` が付かない**（`GameEngine.flix:376-382`）。
  行頭 `pub` の正規表現では拾えない

`gen-api-digest.py` は `extract_def_signature`(:123) と `extract_type_decl`(:188) で
これを既に全部解いていて、出力の `docs/api-digest/*.md` は 1 行 1 宣言で並んでいる。
**digest を作り直して `Float32` を含む pub 行を数えるだけ**なので、lint 本体は 30 行程度。
`make check-docs-sync` が既に `gen-api-digest.py --check` を呼んでいるので配線も既存。

**EXEMPT の数**: digest の対象パッケージは engine / engine_world / engine_tools の 3 つで、
**`render_gl` は対象外**（`gen-api-digest.py:52-54`）。GL 境界の `Array[Float32, Static]` 群は
そもそも検査に出ない。よって最終的な EXEMPT は **`RenderUtil.f32` の 1 件**
（Float64 → Float32 の変換そのものなので当然）。1 本目のリリース時点では
これに `Color` 関連が加わる。

---

## やらないこと

- **`Int32` → `Float64` の 165 箇所は触らない。** タイル座標と画素座標は違う物で、
  型で区別されているのが正しい
- ただし逆向きの `Float64.floor(v) |> Float64.tryToInt32 |> Option.getWithDefault(0)` は
  使い勝手が悪い。**engine 内部にも同じ形がある**（`ShaderEval.clampTexel:314` / `powProduct:330`、
  `platformer-starter/src/Physics.flix:211`）ので、`Num` に安全な API を 1 本足す価値はある。
  **これは engine API の追加なので別途相談**。この計画には含めない

## 破壊的変更の扱い

- 現行 `VERSION := 0.23.5`（`Makefile:33`）。**engine 5 パッケージ・templates・bench・editor_server は
  全部 0.23.5 で揃っている**（`make bump` が一括で書き換える実装なので、ずれる経路が無い）
- このリポジトリに「破壊的変更」を示す規約語・CHANGELOG は無い。過去の非互換変更
  （`beee6695` の RawDraw 移設で pub 21 関数を動かした例）も普通の minor 上げで通している
- 外部リポは版を固定しているので自動では壊れない。`make status` の版ズレ検知と
  `make engine-upgrade` で、上げたタイミングで各リポが個別に直す運用
- リリースノートに「pub 面から Float32 が消えた。ゲーム側は `f32` サフィックスを消すだけでよい」と書く

## 見落としやすい 3 つ（段階に組み込み済み）

1. **`bench/gl_parity` + `bench/sprite_stress`** — 14 件。`make gl-parity` は
   `make release` の一員なのでリリースが通らない
2. **`render_gl/src/Render.flix:23`** — render_gl 独自の `alpha = Float32`
3. **`templates/game-starter`** — `ThemeDoc.flix:75` に 3 件。`TEMPLATE_DIRS` から除外されていて
   **CI では永久に検出されない**。`make new-game` を打った人が最初に踏むので、手で確かめる
