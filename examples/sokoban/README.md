# Sokoban

`flix_game_engine` の上に構築された、完結した小さな sokoban であり、**Worldline
アーキテクチャ**の実演例として書かれている: 1つの不変な World、純粋な `tick`、
画面・UI・耳のための投影、そして無制限アンドゥを2回の関数呼び出しにする、過去の
Worlds の Worldline。

![ゲーム1周分の様子](gallery/full_clear.gif)

スライドベースの移動、回転するアラーム時計による巻き戻し、2つのレベル、
`ui.json` で宣言されたタイトルと CLEAR のページ（F1 でホットリロード）、パーテ
ィクルシステムなしの紙吹雪、そして4つの手続き生成された効果音。

## 実行方法

リポジトリのルートから、エンジンライブラリを一度だけ配布する:

```sh
make sync
```

続いて、このディレクトリで（最初のテスト実行時に、生成アセット —— 音とギャラリ
ー —— も焼き込まれる）:

```sh
java -XstartOnFirstThread -jar bin/flix.jar test
java -XstartOnFirstThread -jar bin/flix.jar run
```

矢印キーで移動、Z で巻き戻し、Enter でページをめくる、X でレベルを放棄、F1 で
UI Spec を再読み込み、Esc で終了。

## 学ぶ

このゲームはチュートリアルの中で章ごとに、一度に1つの概念ずつ、Flix の事前知識
なしで組み立てられる:

- [TUTORIAL.md](TUTORIAL.md)（英語）
- [TUTORIAL.ja.md](TUTORIAL.ja.md)（日本語）

上のスクリーンショットと GIF はすべてテストの成果物である: `flix test` が
[ギャラリー](gallery/index.html) 全体を再生成し、両レベルの同梱の解答をリプレイ
して、その結末を固定する。
