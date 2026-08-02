# 音の鳴らし方（audio.md）

ゲームに音を付けるための一枚。BGM・効果音（sfx）を「鳴らす」までの最短手順と、
迷いやすい「どっちのやり方で鳴らすか」「音そのものはどう作るか」をまとめる。

- 実体: `GameEngine.Audio`（engine/src/GameEngine.flix。再生・停止・音量・ループの effect）・
  `AudioStreamPlayer`（engine/src/render/AudioStreamPlayer.flix。上の薄いラッパ）・
  `AudioFade`（engine_world/src/AudioFade.flix。フェードの音量カーブを作る純関数）・
  `SfxSynth`（engine_tools/src/SfxSynth.flix。素材ファイル無しで効果音を合成する）
- 音は project.json の `sounds` に載せた名前で鳴らす。ファイルの場所はゲームコードから見えない。

## 最短手順

1. WAV を用意する（合成なら後述の SfxSynth を使う。録音・素材ならそのまま `assets/sfx/` に置く）。
2. project.json の `sounds` に登録する。

```json
"sounds": [
  { "name": "push", "path": "assets/sfx/push.wav", "looping": false }
]
```

3. 「前後の World から鳴らす音名を導く」純関数を書く（examples/sokoban/src/Sfx.flix を削った形）。

```flix
mod Sfx {
    pub def events(sessions: { before = Session, after = Session }): List[String] =
        sfxEvent(sessions#before, sessions#after) |> Option.toList

    def sfxEvent(before: Session, after: Session): Option[String] =
        if (pushed(before, after)) Some("push") else None
}
```

4. `App.withAudio` で Main に繋ぐ。

```flix
App.make(initialWorld)
    |> App.addSystem(Controls.step)
    |> App.withView(View.frame)
    |> App.withAudio(Sfx.events)
    |> App.launch
```

これで盤面が変わって `pushed` が真になったフレームだけ `push.wav` が鳴る。

## 経路の使い分け

音を鳴らす経路は2つある。**新しく作るゲームは `App.withAudio`（宣言的）を既定にする。**

- `App.withAudio(sfx)` — 1フレームの `{before, after}`（進める前後の World）から
  「鳴らす音名の List」を導く純関数を渡す。再生そのものは App が引き受ける。
  World の差分だけで判定が書けるので、テストは「何が鳴るか」を具体値で固定できる
  （sokoban / breakout / platformer / liars_room が採用）。
- `AudioStreamPlayer.play(name)` を直接呼ぶ命令的スタイルは、UI のカーソル移動やメニュー確定音のように
  「その場で入力に応じて鳴らす」以外の理由がないなら避ける。World の差分では表せない場面
  （効果を経由しない生の入力ハンドラの中など）だけで使う。

```flix
AudioStreamPlayer.play("cursor")
AudioStreamPlayer.stop("bgm")
AudioStreamPlayer.setVolume("bgm", 0.5f32)
AudioStreamPlayer.setLooping("bgm", true)
```

## project.json の sounds

```json
"sounds": [
  { "name": "move", "path": "assets/sfx/move.wav", "looping": false }
]
```

| フィールド | 意味 |
|---|---|
| `name` | ゲームコードから鳴らすときの論理名（`App.withAudio` が返す文字列・`AudioStreamPlayer.play` に渡す文字列） |
| `path` | project root からの相対パス（WAV/OGG） |
| `looping` | 起動時にロードした音源へ既定で付ける AL_LOOPING の初期値。実行中に変えるなら `AudioStreamPlayer.setLooping` |

パスは project root からの相対で書く（実行時に rootDir と結合される。engine/src/core/ProjectLoader.flix）。

## SfxSynth — 素材ファイル無しで効果音を作る

短い効果音は録音・サンプル素材を用意しなくてよい。`SfxSynth`（engine_tools）が
矩形波・雑音・減衰・重ね・連結だけの語彙で波形を作り、そのまま WAV バイト列にする。
各サンプルは番号だけで決まる純粋関数なので、毎回同じ音が焼ける（golden 比較にも使える）。

| 語彙 | 何を作るか |
|---|---|
| `tone(cfg, freq, amp, ms)` | 矩形波の生音（減衰なし）。「ピッ」の元になる音の高さと長さを決める |
| `noise(cfg, amp, ms)` | 擬似乱数の雑音の生音。「ザッ」「ドッ」のような質感の元 |
| `fade(samples)` | 先頭 1 倍→末尾 0 倍の直線減衰。生音を先細らせて余韻を付ける（重ねがけで急な減衰にもなる） |
| `blend(a, b)` | 2つの声を足し合わせる（短い方の長さに揃う）。tone と noise を重ねて「金属+衝撃」のような複合音を作る |
| `rasp(samples)` | 隣り合うサンプルの差分を取り、擦れた質感にする（noise にかけると太い「ドッ」が「シャッ」に変わる） |
| `sequence(voices)` | 複数の声を順につなげる。上昇音・下降音・ファンファーレのような音階の並びを作る |

ゲーム側は `src/bake/SfxBake.flix` に「音のデザイン」だけを書き、`Bake.all` から
`bakeAll` を呼んで `assets/sfx/` へ WAV を書き出す（`make bake`）。合成と WAV エンコードは
engine_tools 側の `SfxSynth.wavBytes` / `writeBytes` / `bakeSet` が持つので、ゲーム側は
波形の足し算だけ書けばよい。

`examples/breakout/src/bake/SfxBake.flix` からの抜粋:

```flix
def cfg(): SfxSynth.Config = { sampleRate = 22050 }

// パドル: 明るく短い高音のブリップ
def paddleBlip(): List[Float64] = SfxSynth.fade(SfxSynth.tone(cfg(), 880.0, 0.06, 50))

// ハードが耐えた: 低い矩形波の上に鋭いノイズ（金属を叩いた手応え）
def chipClang(): List[Float64] =
    SfxSynth.blend(
        SfxSynth.fade(SfxSynth.tone(cfg(), 180.0, 0.12, 70)),
        SfxSynth.fade(SfxSynth.fade(SfxSynth.noise(cfg(), 0.08, 60))))

// CLEAR: 上昇する4音のファンファーレ（C5, E5, G5, C6）
def clearFanfare(): List[Float64] =
    SfxSynth.sequence(
        SfxSynth.fade(SfxSynth.tone(cfg(), 523.25, 0.15, 90)) ::
        SfxSynth.fade(SfxSynth.tone(cfg(), 659.25, 0.15, 90)) ::
        SfxSynth.fade(SfxSynth.tone(cfg(), 783.99, 0.15, 90)) ::
        SfxSynth.fade(SfxSynth.tone(cfg(), 1046.5, 0.2, 240)) :: Nil)

pub def bakeAll(): Unit \ IO =
    SfxSynth.bakeSet(cfg(), "assets/sfx",
        ("paddle", paddleBlip()) :: ("chip", chipClang()) :: ("clear", clearFanfare()) :: Nil)
```

サンプルレートは 22050Hz で足りる（短いブリップ用途。ファイルも小さい）。

## AudioFade — フェードイン・アウト・クロスフェード

`AudioFade` は状態を持たない計算だけの道具箱。進行度 `t`（0〜1）を渡すと、その瞬間の
音量が決まる。毎フレーム `t` を進め、`AudioFade.volumeOf` の値を `AudioStreamPlayer.setVolume`
（や `GameEngine.Audio.setVolume`）へ流す。

```flix
// フェードイン: 無音 → 全開
let volume = AudioFade.volumeOf(AudioFade.fadeIn(), t);
AudioStreamPlayer.setVolume("bgm", Float64.toFloat32(volume))

// フェードアウト: 全開 → 無音
let volume = AudioFade.volumeOf(AudioFade.fadeOut(), t)

// クロスフェード: 消える曲・現れる曲の音量を同じ t から同時に決める（和は常に1.0）
let (outVol, inVol) = AudioFade.crossfadeOf(t)
```

イージングは持たない。ゆっくり立ち上げたいなら呼び側で `t` を変形して渡す（例: `t*t`）。
`t` そのものの進め方（何秒でフェードするか）は `Transition` に任せる。

## 音の下限（生成コードに必須）

「絵の下限」（AGENTS.md）と対になる、音の側の下限。ゲームを作るときは必ず満たす。

- **決定・キャンセル / 当たった・壊れた / 手に入れた / 場面が変わった、の4種には必ず音を当てる**。
  この4つが無音だと、操作しているのに手応えが無いゲームになる。
- **無音の画面を出荷しない**。BGM を置かないゲームでも、少なくとも上の4種の sfx は鳴る状態にする。
- **同じ音を1フレームに二重に鳴らさない**。`List.distinct` などで畳んでから `App.withAudio` へ返す
  （breakout の `hitSounds` が手本。同じ衝突が同フレームで複数回記録されても音は1回）。
- **音のデザインは SfxSynth かファイルのどちらかに寄せる**。1ゲームの中で合成と録音素材を
  同じ種類の音（例: 効果音どうし）で混在させない — 質感が揃わない。
