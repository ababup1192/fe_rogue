# 用語集 — UI の言葉と内部語の対応

Studio の画面に出す名詞と、その中身の対応表。**一つの概念に言い方は一つ。**
ここに無い名詞を UI に増やさない(増やすときはこの表に足してから使う)。

English の列は、将来この UI を英語化するときの対訳。日本語と 1 対 1 で対応させる。

使ってはいけない語の一覧はここに置かない(ここに載るのは使う語だけ)。
そちらの source of truth は `bin/lint-jargon.py` の WORDS。

## 文の決め方

- **それをするとどうなるかが分かる言葉を使う**。読んで意味が取れず、説明が要る言葉は使わない
- 内部語(bake / promote / family / entityId 等)はコード・ログ・make の世界のもの。UI に出さない
- ひらがなを多用しない。実在ゲーム名を説明に使わない
- 案内の文は、して欲しい**行動**を言う(機能の一覧にしない)
- 次の一歩が無い画面を作らない — 案内カードには必ず押せるボタンを添える
- 案内は普通の説明文で書く。セリフ調・体言止めの演出をしない
- 未実装には「◇これから」チップを付ける。押したら何になる予定かを一言で返す
  (押しても何も起きないボタンを置かない)
- Studio は名詞を発明しない。UI の名詞は、この表にある語か、ゲームが project.json の
  `editor.resources` で宣言したタイトルだけ。宣言されたタイトルは括弧前をそのまま使い、言い換えない

## 入口 — 新しいゲームを作る

| UI の言葉 | English | 意味 | 内部語・実体 |
|---|---|---|---|
| ジャンル | Genre | 新しいゲームの入口のカード。何を含むかは「含む: …」の行に書く | family(/genesis/families) |
| テンプレート | Template | 動く最小ゲーム。選ぶと複製される(ランダム生成はしない) | templates/(starter) |
| エッセンス | Essence | その世界を一行で表した文。遊びにも素材の方向性にも反映される | `AGENTS.local.md` |
| プロンプト | Prompt | AI に貼る依頼文。公式プロンプトは骨格と完了条件を書き込んだ下書き | /prompt/* |
| アレンジ | Customize | 生まれたゲームのパラメータを変えて、自分のものにしていく行為 | — |
| 昇格 | Add to templates | 良いテンプレートが templates/ 入りして、ジャンルが公式テンプレートつきになる | — |

## アトリエ — 素材と値を触る部屋

| UI の言葉 | English | 意味 | 内部語・実体 |
|---|---|---|---|
| アトリエ | Atelier | 下の 4 部屋の総称。部屋は迷わないための区切りで、行き来は妨げない | storehouse / picks / extend / archive |
| パラメータを変える | Tune parameters | 値を保存即反映で変える部屋 | storehouse |
| パラメータ | Parameter | そこで触れる値(速さ・色・文言など) | Doc のフィールド |
| 素材を切り替える | Swap assets | いまの素材を別の素材と見比べて切り替える部屋 | picks / swap |
| 素材スロット | Asset slot | assets/ のパス = 差し替え点。スロットは動かず、中身が替わる | slot |
| 候補 | Candidate | 採用前の試作 | atelier/*.json |
| 候補を作る | Generate candidates | AI に頼んで候補を増やす操作(プロンプトを作って渡す) | /prompt/atelier |
| これを使う(採用) | Use this | 候補の中身を素材スロットへ移す操作。移った候補は候補ではなくなる | promote(swap・候補ファイル削除) |
| バージョン(v1, v2…) | Version | 保存・採用のたび積まれる過去の中身。前の中身は消えない(「↩ v3 に戻す」) | `atelier/archive/<base>.vN.<kind>.json` / `draft/sketch/<名前>/vN.json` |
| 手直し | Quick edit | 素材をその場で直すポップアップ(グリッド・カーブ・音のスライダー) | PixelEditor / MapEditor |
| ゲームを広げる | Extend game | ゲームの構造(コードと Doc の形)が変わるプロンプト。検査つき | extend(/prompt/extend) |
| 場面を足す / 仕組みを足す / 素材の種類を足す | Add scene / mechanic / material | 「ゲームを広げる」の 3 つの入口 | kind=scene / mechanic / material |
| アーカイブ(する) | Archive | 使わない候補と過去バージョンの置き場(へ送る)。何も捨てない | atelier/archive/ |
| 候補に戻す | Restore | アーカイブから候補の列へ | /atelier/restore |
| 選んだ組み合わせで試す | Try combination | 複数の候補を、何も書き換えずに組み合わせて走らせて比べる(◇これから) | — |

## 絵を見る・直す

| UI の言葉 | English | 意味 | 内部語・実体 |
|---|---|---|---|
| ラフ | Sketch | 人が描く下描き。生成された絵と見比べる相手 | `draft/sketch/<名前>/` |
| 注釈チケット | Annotation ticket | 絵の上で矩形を囲って一言書いた直しの依頼。済んだら archive/ へ下げる | `debug/annotations/` |
| リファレンス画像 | Reference image | 前に「これで正しい」と決めた画面の絵。いまの絵と比べて、変わっていたら知らせる | `templates/*/reference/` |
| 見た目が変わりました | Visuals changed | リファレンス画像との自動比較の知らせ。前と今を見比べられる(見なくてもよい) | /journey/changes |
| 前 / 今 | Before / After | 見比べの 2 枚のラベル | `reference/archive/<scene>.vN.png` / `reference/<scene>` |

## 全体の道しるべ

| UI の言葉 | English | 意味 | 内部語・実体 |
|---|---|---|---|
| 次のやること | Next step | 状態検知から次の一歩を 1 枚だけ出す誘導 | journey(/journey/state) |
| すべてのファイル | All files | 全ファイルの一覧とコード編集への入口。どの部屋にも置く | /files |
| ミニプレイヤー | Mini player | 走っているゲームを Studio 内に小さく映す枠(アトリエの間だけ出る) | — |
