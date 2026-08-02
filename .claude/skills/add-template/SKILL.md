---
name: add-template
description: "templates/ にスターターを足す・更新する手順。golden/title.png・lint-palette・Doc 外形規約・画風の宣言・Studio への登録と swap-jar まで、どれか 1 つ欠けると Studio で「出ない / 絵がない / 作れない」になる 7 手順を出す。新しいジャンルのテンプレを作るとき、templates/ 配下を直すとき、make new-game が動かないとき、Studio のジャンル札に絵が出ないときに使う。"
allowed-tools: Read, Grep, Glob, Bash, Edit, Write
---

# テンプレートを足す・更新する

`templates/` の各スターターは `make new-game` の複製元であり、Studio の「ジャンル」の顔でもある。

## 2 系統ある

- **具体値式**（rpg / novel / race / tetris-starter）: 値をそのまま書く。**in-repo で
  `make -C templates/<name> check / test / bake` が通り golden を持つ**作り込み例。
  凝った演出もテストも載せられる。Studio の「はじめる」は複製で始まる。
- **トークン式**（game-starter）: `__NAME__` `__W__` などを埋めた最小の骨組み。
  in-repo ではビルドしない（`make new-game` が置換して初めて動く）。W/H を引数で決める素体。

## 空の抜け殻を置かない

`src/` の無いディレクトリを `templates/` に残すと、Studio の札からは選べるのに複製しても動かない。
中身を作れないうちは Studio 側の `starter` を空にしておき、**ディレクトリごと作らない**
（存在しないパスを `starter` に書くのも同じ事故になる）。

## 手順

このチェックリストを回答にコピーし、埋めながら進める。
**どれか欠けると Studio で「出ない / 絵がない / 作れない」になる。**

```
- [ ] 1. templates/<genre>-starter/ を作った（rpg-starter を写経元に。具体値式なら golden も焼く）
- [ ] 2. golden/title.png を用意した
- [ ] 3. make lint-palette が通った
- [ ] 4. Doc の外形規約を守った（全 Doc に version・schema は sections 方言）
- [ ] 5. 画風を宣言した（AGENTS.local.md + View.flix 冒頭の層の並び）
- [ ] 6. Studio に登録した（Genesis.flix の families の starter）
- [ ] 7. make swap-jar して Studio を Cmd+Q → 開き直した
```

### 2. `golden/title.png` を必ず用意する

Studio のジャンル札のサムネは `GET /genesis/title` がこれを読む（無いと空絵に倒れる）。
bake に `title` シーンを 1 枚足して祝福する。

### 3. `make lint-palette` を通す

ドット絵（`*.sprite.json`）の `legend` に書いた意味色キーは、`*.theme.json` のトップレベル・
`paletteFile` の指す色票・直下の `palette` のどれかに実体が無いと Studio が仮色で塗り、
編集画面と実機で配色が食い違う。

派生色をコードで導いているなら、色票 JSON を生成する `make` ターゲットを作り、
`paletteFile` でそれを指す（`kaidan` の `Palette` モジュール + `palette` ターゲット +
テストが手本。テストで生成物と実機の色を pin する）。

### 4. Doc の外形規約を守る

[docs/doc-conventions.md](../../../docs/doc-conventions.md) に従う。全 Doc ファイルに `version` を入れる
（無いと Studio の健康診断が「version がありません」を出す）。

`*.schema.json` は Studio の **sections 方言**で書く（語彙リファレンス形式で書くと
Studio のフォームが「Expecting an OBJECT with a field named `sections`」で読めない。
語彙の解説は docs/ 側に置く）。詳しくは `/doc-design`。

### 5. 画風を宣言する

`AGENTS.local.md` に「## この画面の画風」を書き（色 3 つ・やらないこと 1 つ）、
`src/View.flix` の頭に層の並びと、各層が「絵の下限」の 4 性質のどれを受け持つかを書く。

**テンプレどうしで画風をそろえない** — 揃えると「この画風が正解」という手本になってしまう
（夜のネオン・紙の刷り物・霧の夕暮れ・雨の夜、と別々にしてあるのはそのため）。

**音と粒（パーティクル）も絵と同じ強さで意識する**。詳しくは [docs/audio.md](../../../docs/audio.md) と
`/visual-dict`。粒を出すときはまず [docs/module-index.md](../../../docs/module-index.md) の逆引きを引く。

### 6. Studio に登録する

`flix_ge_studio` の `server/src/Genesis.flix` の families で、該当ジャンルの
`starter = "templates/<genre>-starter"` にする（starter が空だとゼロ生成フローのまま）。

### 7. Studio に反映する

`flix_ge_studio` で **`make swap-jar`**（動いている `.app` の同梱 jar を差し替え + 再署名）
→ Studio を Cmd+Q して開き直し。**`make jar` だけでは動いている .app に効かない**。

## 複製する

`make new-game GAME=/abs NAME=x TITLE=題名 TEMPLATE=<genre>-starter`

TITLE は自由文でよい（アポストロフィ・空白・記号も通る）。具体値式テンプレは自身の W/H・題名を
使う（引数の W/H・TITLE は反映されない — 作成後に project.json の「ゲームの題・画面」Doc で変える）。
