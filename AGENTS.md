## 会話ポリシー

日本語で会話してください。途中報告なども含めて、日本語で回答してください。
コメント・会話では、一般で広く使われるプログラミング、一般教養的な用語以外は、なるべく平易な中高生でも伝わるような言葉で書く。

## 設計・実装

- **絵の下限（矩形だけの画面から脱する 4 性質）**: [docs/drawing-floor.md](docs/drawing-floor.md)
- **Flix の決まり（予約語・コメントの流儀）**: [docs/flix-conventions.md](docs/flix-conventions.md)
- engine_world の「やりたいこと → モジュール」逆引きと全モジュール一覧: [docs/module-index.md](docs/module-index.md)
- engine/ 側（描画・音・入力などの土台）のモジュール索引: [docs/engine-module-index.md](docs/engine-module-index.md)
- 音の付け方（効果音づくり・鳴らす配線・音の下限チェックリスト）: [docs/audio.md](docs/audio.md)

複雑で大規模な変更の場合は、いきなり実装をせず、レビュー役を立てて、壁打ちして80~90点以上を目指してください。
実装はするだけで満足せず、レビュー役に仕様漏れ・リファクタリング余地が無いかを確認してもらいましょう。

エンジン（engine/ 配下）を拡張するときは、**実施前に必ず相談する**。判断軸は汎用性。

## コーディングポリシー

コードには **How** / テストコードには **What** / コミットログには **Why** / コードコメントには **WhyNot**

特にコードコメントは WhyNot を重視し、How・What を書かない。実装の由来や旧実装などの歴史背景も書かない。

命名の注意: Flix の予約語（`handler` / `do` / `resume` / `run` / `spawn` / `region` / `inject` /
`project` / `solve`）は変数・関数名だけでなく**レコードのフィールド名**にも使えない。
エラーは「Expected ',' before '='」のような間接的なパースエラーで出る。

## 絵と音

**`Render.box` を並べただけの画面は未完成。** 求めるのは 4 性質（面に階調か質感 / 主役が背景から
分離 / 層が分かれている / 時間が流れている）で、**どの画風で満たすかは自由**。
画風はゲームごとに決め直す（既定は無い。テンプレどうしでもそろえない）。

絵を書く前に必ず `/visual-dict` を引く（本文は `.claude/skills/visual-dict/`。
まず `SKILL.md` の手順、部品選びは `reference.md` と `unused-parts.md`）。
下限の全文は [docs/drawing-floor.md](docs/drawing-floor.md)。
音も絵と同じ強さで意識する（[docs/audio.md](docs/audio.md)）。

人に見せる前に自分で確かめる（OS・エージェントを問わず動く）:

```
python3 bin/lint-view.py [ファイル...]   # 矩形と円だけになっていないか
python3 bin/lint-palette.py              # ドット絵の意味色キーが色票から解けるか
python3 bin/lint-images.py               # git に入れる絵が増えすぎていないか
```

### 焼いた絵は git に入れない

`make bake` が焼く `gallery/` と `golden/*.png` は **git 管理外**。焼き直すたびに PNG/GIF は
丸ごと別の実体になり、差分圧縮も効かないまま履歴に積み上がるため。

- **人に見せる絵は [docs/gallery/](docs/gallery/README.md) にだけ置く**（枚数・大きさの上限あり）。
  焼いた中から選んでコピーする
- 退行検知は `templates/*/golden/SHA256SUMS.txt`（`make -C templates/<name> bench` が突き合わせ、
  `make golden` が作り直す）。PNG 本体は手元に残るので `make diff` の左右比較はそのまま効く
- `templates/*/golden/title.png` だけ実体を追跡する。Studio のジャンル札のサムネが読むため

## 検証

**テストは絞って速く回す。全量の検証はリリース直前の 1 回だけ。**
変更が波及したパッケージだけ `make test-<name>`、それ以外は `flix check` で足りる。
テストの範囲・書き方は `/quality-assurance`、リリース手順は `/release`。

## Doc（`*.kind.json`）の流儀

ゲームの値は、なるべくコードに直書きせず **Doc へ外に出す**。外に出せばエディタ
（flix_ge_studio）でフォームやスライダーから触れて、**走らせながらその場で変えられる**。

- **外に出す物**: 繰り返し調整する数値（テンポ・閾値・収支・確率）、個数が増減するデータ
  （配置・敵・アイテム）、色テーマ、文言
- **外に出さない物**: 描画アルゴリズム・演出の形、導出できる値、一度決めたら触らない構造。
  **振る舞い（ルール・当たり判定・生成）はコードのまま**

判断軸は「保存即反映で調整できると嬉しいか」。ロジックを JSON に書き始めたら設計の匂い。
外形規約・分け方・スキーマ方言は `/doc-design` と [docs/doc-conventions.md](docs/doc-conventions.md)。

## スキル

| いつ | 必ず引く |
|---|---|
| View / 背景 / キャラ / エフェクトを書く**前** | `/visual-dict` |
| Flix を書く前・テストを書く前 | `/flix-docs` |
| コンパイルエラーが出たら | `/compile-fix` |
| テストを設計するとき | `/quality-assurance` |
| Doc(JSON) を新設・拡張するとき | `/doc-design` |
| 絵・演出を直すとき | `/bake-loop` |
| templates/ を足す・直すとき | `/add-template` |
| 版を上げる・公開するとき | `/release` |
| fe_rogue のマップチップを直すとき | `/mapchip-debug` |

**絵を書き始める前に `/visual-dict` を引いていない場合、その作業は未着手として扱う。**

### スキルを持たないエージェントへ

`/名前` は Claude Code の呼び出し方だが、中身は**ただの markdown** なので、どのエージェントでも
`.claude/skills/<名前>/SKILL.md` を直接読めば同じ内容が手に入る。`.claude/rules/*.md` も同じで、
本文は `docs/` にある物と同一（`bin/gen-rules.py` の生成物）。

規約の本文の置き場は 1 つだけ:

| 内容 | 本文の在り処 | 各ツールへの配り方 |
|---|---|---|
| 全体方針 | `AGENTS.md`（このファイル） | `CLAUDE.md` は `@AGENTS.md` の 1 行 |
| 絵の下限 | `docs/drawing-floor.md` | `make rules` が `.claude/rules/drawing.md` を生成 |
| Flix の決まり | `docs/flix-conventions.md` | `make rules` が `.claude/rules/flix.md` を生成 |
| 作業ごとの手順 | `.claude/skills/*/SKILL.md` | そのまま読む |

`make check-docs-sync` が、この配線が崩れていないか（import・生成物のずれ・
存在しない skill への参照・frontmatter 欠け）を検査する。**規約を直したら本文の方を直す。**
