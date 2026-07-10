# リモートデバッグ（HTTP）

起動中のゲームを外部プロセス（AI エージェント・スクリプト・手元の curl）が操作・観測する口。
「キー入力の台本を N フレーム実行して、結果を受け取る」が curl 一発で完結する。

実時間を追いかけられない相手（判断に数秒かかる AI 等）でも、**ゲーム側が止まって待つ**
（lockstep = コマ送り）ことでフレーム精度の操作とデバッグができる。実績: ブロック崩しの
ステージ 1 を、着地予測ボットが約 220 往復でクリア（`scratchpad` の breakout_player.py 参照）。

## 起動

```sh
DEBUG=1 DEBUG_HTTP_PORT=7777 make run       # どの example でも同じ
```

- `App.withDebug` が有効 **かつ** `DEBUG_HTTP_PORT` がある時だけ立つ二重ゲート
  （本番ビルドには存在しない）。bind は 127.0.0.1 限定。
- 起動すると `[remote-debug] listening on http://127.0.0.1:7777 (GET /help)` が出る。

## プロトコル（全応答 text/plain・行指向）

| エンドポイント | 役割 |
|---|---|
| `GET /help` | 自己記述（このプロトコルの要約） |
| `POST /halt` | 時間を止めて lockstep モードへ |
| `POST /resume` | 実時間の進行へ戻す（スクラブ中ならその瞬間から再開） |
| `GET /state?view=&rect=` | 進めずに観測だけ |
| `POST /step?view=&rect=&until=&max=&trace=&dt=` | **主役**: ボディの台本を実行して結果を返す |

### /step の台本 DSL（ボディ・1 行 1 コマンド・`#` コメント）

```
press Enter      # 1 フレーム押して 1 フレーム離す（1 押下 = 1 発火）
idle 5           # 5 フレーム何もしない
hold Right 45    # 45 フレーム押しっぱなし
hold Left,Z 10   # 同時押し
```

### クエリパラメータ

| param | 意味 | 既定 |
|---|---|---|
| `view=` | `status`（1 行サマリ）/ `full`（worldDump）/ `scene`（矩形内の描画物一覧）/ `none` | `status` |
| `rect=x,y,w,h` | full / scene の関心矩形（デザイン座標） | 全画面 |
| `until=` | `sfx:any` / `sfx:name1,name2`（音で早期停止）/ `quiet:N`（N フレーム無音で停止） | 止めない |
| `max=N` | このリクエストのフレーム上限（安全弁） | 1200（最大 3600） |
| `trace=status:K` | K フレームごとに status を 1 行追記 | なし |
| `dt=MS` | 1 コマの経過ミリ秒（診断用。既定 1/60 秒） | 16.67 |

### 応答の形

```
ok stepped=88 frame=2454 mode=halted stopped=until:sfx consumed=88/600
[events]
f=1901 sfx=break        ← 実行中に鳴った音 = フレーム間に何が起きたかの主要観測
f=1969 sfx=miss
[trace]                  ← trace= を付けた時だけ
f=2465 phase=Playing ...
[status]                 ← view= で選んだ本文
phase=Playing state=Moving vel=(27.0,-127.2) ball=(161.8,205.5) ...
```

`stopped=` は `script`（台本を最後まで）/ `until:sfx` / `until:quiet` / `max` / `quit`。

## lockstep の意味論（知っておくこと）

- `/step` は **未停止なら自動で halt** してから実行する。実行後も halted のまま
  （続けて観測・巻き戻し・次の /step ができる）。実時間に戻すのは `/resume`。
- **dt は実時計でなく固定値**（既定 1/60 秒）。何度やっても同じ結果になる。
- **音は鳴らさず記録**して `[events]` に載せる（フレーム番号つき）。BGM 状態は壊さない。
- **途中フレームの描画は抑制**する（vsync 待ちが消え数百コマが一瞬で回る）。
  そのためウィンドウは「/step のたびにコマ飛びで更新される静止画」に見える —— 故障ではない。
- 実行した合成フレームも履歴（300 コマ）に積まれるので、人間が F8 の ← → で見返せる。
- HTTP が停止させている間、F8 での解除は効かない（/resume で返す）。人間の
  ズーム・パン・矩形注釈は halted 中もそのまま使える。
- ゲームループが 10 秒応答しなければ HTTP は 503 を返す（curl が永久に固まらない）。

## ゲーム側の配線（任意・あると観測が濃くなる）

| フック | 効果 | 例 |
|---|---|---|
| `App.withStatusLine(f)` | `view=status` と `trace=` の 1 行サマリ | breakout: `Field.statusLine`（フェーズ・ボール・残機） / fe_rogue: `WorldDump.statusLine` |
| `App.withWorldDump(f)` | `view=full` の本文（F8 注釈の world.json と共用） | fe_rogue: `WorldDump.dump` |
| 配線なし | `view=scene`（view / debugView 投影の描画物一覧）は常に使える | sokoban 等 |

statusLine は「調査に効く値だけを短く」。座標の丸めには `RemoteDebug.fmt1` が使える。
worldDump / statusLine は純粋関数で書くこと（システムの外から任意の瞬間の World で呼ばれる）。

## curl レシピ

```sh
# いま何が起きているか 1 行で
curl -s 'localhost:7777/state?view=status'

# タイトルを抜けてサーブし、最初の音まで進める
curl -s -X POST 'localhost:7777/step?until=sfx:any&max=300' -d 'press Enter
idle 5
press Space
idle 290'

# 「次にパドルに当たるかミスするまで」を 1 往復で
curl -s -X POST 'localhost:7777/step?until=sfx:paddle,miss&max=600' -d 'hold Right 45
idle 555'

# 貫通バグの類を疑ったら: 全フレームの status を吐かせて挟み撃ち
curl -s -X POST 'localhost:7777/step?view=none&trace=status:1&max=90' -d 'idle 90'

# 気になる場所の描画物一覧（worldDump 未配線でも使える）
curl -s 'localhost:7777/state?view=scene&rect=96,40,80,30'

# fe_rogue のシム状態全部入り（world.json と同じ内容）
curl -s 'localhost:7777/state?view=full'

# 実時間プレイに返す
curl -s -X POST localhost:7777/resume
```

## トークン経済の目安（AI が操作するとき）

- 1 往復 60〜300 トークン（status/イベントのみ）。`view=full` は 1〜3k なので要所だけ。
- 効く順: **/step に観測を同梱**（往復半減）＞ view の詳細度 ＞ until= の早期停止。
- 実測: breakout ステージ 1 クリア = 約 220 往復（state+step 各 110）・応答は平均 200 バイト級。
