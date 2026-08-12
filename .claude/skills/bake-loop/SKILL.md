---
name: bake-loop
description: "絵を直すときの進め方。ヘッドレス生成で場面を生成して目視で批評し、一度に 1 つだけ直して前後を並べて見せるループを出す。絵・演出・手触りを直すとき、「見た目を直して」「ここが変」と言われたとき、make bake / make diff を使うとき、どこから直すか候補を出すときに使う。"
allowed-tools: Read, Grep, Glob, Bash, Edit, Write
---

# 絵の開発ループ（生成）

決定的な場面をヘッドレス生成で `debug/` に生成し（golden の外）、目視で批評 → 修正 → 再生成を回す。

## 見る前に数値（bench → img-digest → 目視の順）

生成した絵を毎回目視すると 1 枚数千トークン燃える。じょうごで絞る:

1. まず `make -C templates/<name> bench`（golden とのハッシュ突き合わせ）。**全一致ならここで終わり** —
   digest も目視も要らない
2. 不一致の名前が出た時だけ、その名前を渡して数値で当たりを付ける:
   ```
   python3 bin/img-digest.py golden/ gallery/ battle.png   # 名前を挙げた絵だけ要約
   python3 bin/img-digest.py old.png new.png               # 2 枚だけ比べる
   ```
   差分画素率・変化した領域・色数・明るさが数行で出る
3. **画像を開くのは最終確認の 1 回だけ**

- 機械的リファクタ（分割・Doc 化）は「前後の PNG バイト一致」で見た目不変を証明する
- リグレッション防護は golden（`gallery/` vs `golden/` のバイト比較）に任せる

## 一度に 1 つだけ直す

直す所が複数見えても、**一度に 1 つだけ直す**。並びを揃えるため・リストを消化するために
手を広げない（絵に限らず、手触りやテンポも同じ）。

## どれを直すかは人が決める

**選ぶのは人の仕事。** 遊ぶ人から見て目立つ順に候補を**3 つまで**並べる
（1 つ 1 行 + 生成した絵か再現手順）。人は番号で答えれば済む。

コードを見ても、遊ぶ人に何が見えているかは判らない。だから**何を選ぶかをレビュー役に聴かない**。
レビュー役に聴くのは「選んだ 1 つの直し方が 90 点か」だけ。

**ただし壊れている物は聴かずに先に直す** — 落ちる・黒い穴・golden の退行は好みの問題ではない。

## 直したら前後を並べて見せる

`make diff DIR=<game>`。変わった絵だけ `debug/diff/` に「左=前・右=後」で生成できる。
**ファイル名を並べるだけにしない** — 人が 2 枚を切り替えて差を探す羽目になる。

## ループ GIF を生成したら継ぎ目を確かめる

完全ループを狙う GIF（コマ 0 に戻る演出）を生成したら、目視の前に
`make lint-loop`（または `python3 bin/lint-loop.py <framesディレクトリ>`）で
最終コマ→0 コマの継ぎ目が浮いていないか機械検査する。fade・wipe など
最初から戻らない演出は対象外。

## Bake / golden の作り方（まだ無いゲームに足すとき）

配管一式（Bake entrypoint・flix.toml・フォント・Bakery 呼び出し）の写経元は
docs/headless-bake-recipe.md。golden の祝福は `make -C templates/<name> golden`（bin/golden-bless.sh）、
比較は `make -C templates/<name> bench`（bin/golden-check.sh）。git に入るのは SHA256SUMS.txt と title.png だけ。
守ることは 2 つ: 調整中の画は `debug/` 行きの別 entrypoint に分けて golden を汚さない・
テストは検証だけ（生成は `Bake.all` の仕事）。

## 手順

```
- [ ] 1. 壊れている物（落ちる・黒い穴・golden 退行）が無いか見た。あれば聴かずに直す
- [ ] 2. 生成して目視した（make bake DIR=<game>）
- [ ] 3. 候補を 3 つまでに絞って人に出した（1 つ 1 行 + 絵か再現手順）
- [ ] 4. 選ばれた 1 つだけを直した（他に手を広げていない）
- [ ] 5. make diff DIR=<game> で前後を並べて見せた
```

絵の部品選びは `/visual-dict`。絵の下限 5 性質は docs/drawing-floor.md が正（`.claude/rules/drawing.md` はその生成物）。
