# 絵の下限

`Render.box` を並べただけの画面は未完成として扱う。次の 4 性質をすべて満たすこと。
**どの画風で満たすかは自由**。下は手の一例で、選択肢の全部ではない。

| 満たす性質 | 手の例 |
|---|---|
| 面に階調か質感がある | `ShaderDoc` + `Render.shaderFill` / `Render.vgrad`・`gradPolygon` / `Material`（粒・きらめき・染み）/ `Render.striped`・`checker` / `PxShade` のディザ |
| 主役が背景から分離して読める | `PxShade`（ふち光・接地影）/ `Render.glowAt` / `Render.outline` / 明度差・色相差 |
| 層が分かれている（奥・主役・手前） | `Render.zShifted`・`zShiftedAll` / `Depth` / `Transition` の覆い |
| 時間が流れている | `Fx`・`FxDoc`（粒）/ `Sway`（揺れ）/ `Anim`（コマ替え）/ `Scatter` / `Daylight` |

光と影で色そのものを分けたいときは `Color.warm` / `Color.cool`。

## 部品を選ぶ前に辞書を引く

box と circle だけで組み始めたら、それは辞書を引かなかった証拠。
`Render.star` / `ellipse` / `sector` / `ngon` / `vgrad` / `gradPolygon` / `striped` /
`checker` / `turned` / `clipped`、`PxShade`、`Material`、`Scatter`、`Mirror`、`Daylight` は
**すでに実装もテストもある**。「無いから手組み」の前に必ず一覧を見る。

- 技法 → 部品の翻訳表: `.claude/skills/visual-dict/reference.md`
- 採用ゼロ〜1 の部品一覧: `.claude/skills/visual-dict/unused-parts.md`
- 画風の決め方と手順: `.claude/skills/visual-dict/SKILL.md`
- シェーダーの語彙（Field / Shade の全 kind）: `docs/shader-doc.md`
- 逆引き全体: `docs/module-index.md`

## この画面の画風

同じゲームの `AGENTS.local.md` の「この画面の画風」が正（色 3 つ・やらないこと 1 つ）。
無ければ**先に書いてから**描き始める。

画風はゲームごとに決め直す物で、既定は無い。**テンプレどうしで画風をそろえない** —
揃えると「この画風が正解」という手本になってしまう。

## ドット絵（`*.sprite.json`）

`legend` に書いた意味色キーは、`*.theme.json` のトップレベル・`paletteFile` の指す色票・
sprite Doc 直下の `palette` のどれかに**実体が無いと Studio が仮色で塗る**
（編集画面と実機で配色が食い違う）。

## 良し悪しを決めるのは人（必ず確認を取る）

**下限を満たしたことと、絵が良いことは別。** いけてるかどうかを判定できるのは、
実際に画面を見る人だけ。エージェントが「良い絵になりました」と締めない。

- 絵・背景・見た目を作った / 変えたら、**焼いて人に見せて確認を取る**
  （`make bake DIR=<game>`、直した物は `make diff DIR=<game>` で左=前・右=後）
- **ファイル名や層の一覧を並べるだけにしない** — 人が絵を探す羽目になる
- 直す所が複数見えたら、目立つ順に**候補を 3 つまで**出して番号で選んでもらう。
  自分で選んで手を広げない（一度に直すのは 1 つだけ）
- **壊れている物だけは聴かずに先に直す** — 落ちる・黒い穴・golden の退行は好みの問題ではない

進め方の詳しくは `.claude/skills/bake-loop/SKILL.md`。

## 機械で確かめる（人に見せる前の下ごしらえ）

下限を満たしているかだけは、どの OS・どのエージェントでも機械が見られる。
**これが通っても「絵が良い」ことにはならない。**

```
python3 bin/lint-view.py [ファイル...]   # 矩形と円だけになっていないか
python3 bin/lint-palette.py              # 意味色キーが色票から解けるか
```

`make lint-view` / `make lint-palette` でも同じ。
