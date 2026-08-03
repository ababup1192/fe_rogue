# assets/sfx

このフォルダの `.wav` は手で置いた録音ではなく、`make bake` が `src/bake/SfxBake.flix` から生成する成果物です。
音を変えたいときは `.wav` を直接編集せず、次のどちらかを直して `make bake` し直してください。

- 音量・高さ・長さ … `assets/race.sfxtune.json`（Studio のフォームからも触れます）
- 音そのものの組み立て … `src/bake/SfxBake.flix` の合成レシピ

どの出来事でどれが鳴るかは `src/Sfx.flix`、一覧は `README.md` の「音」の節にあります。
