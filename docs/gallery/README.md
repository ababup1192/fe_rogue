# docs/gallery — 人に見せる絵の置き場

**ここはリポジトリで唯一、絵を git に入れてよい展示場です。**

`make render` が描き出す各ゲームの `gallery/` は git 管理外です（生成し直すたびに PNG/GIF は
丸ごと別の実体になり、差分圧縮も効かないまま履歴に積み上がるため）。README やドキュメントに
載せたい絵は、生成した中から**選んでここへコピー**します。

## 決まり

| 項目 | 上限 |
|---|---|
| 枚数 | 20 枚 |
| 1 枚の大きさ | 300KB |
| 合計 | 4MB |

- 足すときは、先に**古いものを 1 枚落とせないか**を考える。展示場は増える一方にしない
- GIF が重いときは寸法を整数分の 1 に縮める（ドット絵が崩れないよう最近傍で。
  例: `ffmpeg -i in.gif -vf "scale=320:240:flags=neighbor,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=none" out.gif`）
- 名前は「どのゲームの何か」がわかる形にする（例 `rpg_town.png`）
- ロゴ・バナーなど、絵でなくブランド素材は `docs/brand/` へ

守れているかは `python3 bin/lint-images.py` で確かめます。

## いまある絵

- `cards.gif` / `farm.gif` / `dungeon.gif` / `novel.gif` / `village.gif` / `puzzle.gif` /
  `horror.gif` — ルート README のジャンル一覧
