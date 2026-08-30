# checkd: REPL 起動 1 回目が 0% CPU でハングする問題 — スパイク計画

2026-08-30、internet_dungeon_new での実測から。checkd-runaway-guard.md の姉妹編で、
あちらに無い新発見(A〜C)が中心。**進め方はスパイク: 観測を直す → 本命を当てる →
ゲームへ差し替えて実測 → 外れたら次の候補**。

## 実測した症状(internet_dungeon_new)

- まっさら(java 全滅・~/.cache/flix-checkd 削除)から `make check` = 17 分 01 秒で成功。CPU 使用は 106 秒だけ。
- daemon.log: 06:09:01「repl が居ないので起動」→ 06:22:49「check 失敗: repl の起動がタイムアウト」= **828 秒 < workTimeoutSec 900 = タイムアウトではない**。
  waitFor の EOF 経路(daemon.go:380-383)= **repl が 13 分 48 秒 0% CPU の末に自分で死んだ**。
- その後クライアントは runFallback(素の flix check)で 1〜2 分で成功(check.log に Maven 依存解決のログ)。
- 過去ログに 15 分待ち 8 連続(2.5 時間)の記録。クライアントは全期間無言。
- 別の残骸: 生きているデーモン(pid あり)なのに port ファイルだけ消えている個体を確認
  (client.go:103 の DropPort が生死を見ずに消した結果。以後そのパッケージは永久に素の CLI 行き)。

## 結論(2026-08-30 スパイク完了。根本原因は -Xmx の上限)

段 1 の原因ログが決め手。**-Xmx の上限(このマシンで 1302MB)が repl の初回フルコンパイル
(Monomorpher の作業セット 3〜4.5GB)に全く足りない**のが本体だった。実測:

| ヒープ | 結果 |
|---|---|
| 1302MB(旧既定) | Monomorpher で GC スラッシング。900 秒のタイムアウトでも終わらない(3 回再現。ディスクキャッシュの温冷は無関係) |
| 2572MB | 約 80 秒で repl が自滅(Type.typeVars の深い再帰でメモリ系エラー、exit 1) |
| 3084MB | **28 秒でウォームアップ完了**。RSS 3463MB で常駐維持 |
| 4108MB | 25 秒でウォームアップ完了。RSS 4445MB |

入れた修正(全て検証済み):

1. **hooks.json: heapMinMB 768 → 3072 / rssLimit.minMB 1024 → 3584**(ソース・Studio 写し両方)。
   16GB 機で heapCap = 3584-500 = 3084MB になり、上の実測で 28 秒。
2. **ウォームアップ失敗の原因ログ**(EOF かタイムアウトか / wait の結果 / 出力の末尾 20 行)— これが無いと何も分からない。
3. **上限なしリトライ**: ウォームアップが「上限つきで生きたままタイムアウト」か「OutOfMemory / StackOverflowError で死亡」
   なら、-Xmx なしで 1 回だけやり直す(将来プロジェクトが太って 3084MB を超えた日の保険)。
4. **repl.pid + killStaleRepl**: デーモンが killRepl を通らず死ぬと、コンパイル中で stdin の EOF に
   気づかない repl プロセスが残る(ウォームアップ中のデーモン SIGKILL で再現)。起動前に pid ファイルを見て kill
   (ログ「stale な repl プロセス (pid N) を kill した」を実機確認)。
5. gh auth token に 3 秒のタイムアウト / 古い Maven lock の掃除(sweepStaleLocks)。

追補(同日): さらに 2 件対応済み。

6. **warmTimeoutSec 240 を新設**(hooks.json 3 写し + rules.go + daemon.go)。ウォームアップのタイムアウトを
   check 用の 900 から分離 — 上限不足のスラッシングを 4 分で打ち切って上限なしリトライへ渡す。
   実地確認: 上限 1300MB を強制 → 240 秒で打ち切り → リトライ 26 秒 → 合計 4 分 46 秒で check OK
   (旧 15 分半)。正常構成の初回は 27 秒のまま。
7. **gbPerDaemon 5 → 8**: 16GB 機でデーモン最大 2 本。rssLimit 3.6GB × 2 = 約 7GB で、
   複数プロジェクト同居時の膨張を抑える。あわせて rssLimitMB に「rssLimit は heapMin + headroom を
   下回らない」clamp を追加(環境変数で成立しない構成を作れないように)。テスト 2 本更新。

なお「828 秒 EOF 死」の正体も 2 の後の実測でほぼ確定: 上限の下の GC スラッシング中に
メモリ系エラーで自滅する個体と、タイムアウトまで生きる個体の 2 通りがある。lock 待ち(段 2 仮説)は
主犯ではなかった(掃除は保険として残す)。

## スパイク手順

### 段 1: エラーの内訳を見えるようにする(必ず最初。これ無しで当てても検証できない)

- daemon.go:190 `if ok, _ := d.waitFor("zzz-warm", work); !ok {` — **出力を捨てない**。
  waitFor を `(ok bool, out []byte, reason string)`(reason = "eof" | "deadline")にし、
  daemon.log に「EOF か締切か / exit code(cmd.Wait のエラー) / 出力の末尾 20 行(scrub 済み)」を必ず書く。
- daemon.go:177-180 `_ = cmd.Wait()` — exit code を保持してログへ。
- daemon.go:127-133 `gh auth token` — exec.CommandContext + 3 秒。失敗は無言で token 無し続行。
  (keychain 待ちで cmd.Start() 前に無限ハングする独立経路の封鎖)

### 段 2: 本命(Maven lock の自己増殖)を当てる

仮説: REPL 起動は毎回 Flix/Maven 依存解決(ネットワーク待ち = 0% CPU)を通る。
起動失敗のたび killRepl が SIGKILL(daemon.go:237,242)→ `<pkg>/lib/cache/**/*.lock` が残る →
次の起動が「他プロセスが取得中」と誤認して 0% CPU で待つ → また SIGKILL、の自己増殖。
Makefile:136-141 の clean-locks が既にこの罠を文書化済み(だが game.mk に配られていない)。

- killRepl で SIGKILL に至ったら stateDir に印 → 次の startRepl 前に `<pkg>/lib/cache` の *.lock を掃く。
- SIGTERM の猶予 5 秒(daemon.go:241)は依存解決中の JVM に短すぎる → 15〜30 秒へ。
- mk/game.mk に clean-locks ターゲットを追加(ゲーム側に掃除の口が無い)。

### 段 3: 差し替えと検証(ゲーム側)

```
cd ~/Desktop/flix_game_engine && make go-build
make sync-agents GAME=/Users/abab/Desktop/internet_dungeon_new   # bin/fge-go を運ぶ
# 検証(ゲーム側):
pkill -f java; rm -rf ~/.cache/flix-checkd/8fef2a5be9abe6d8
cd ~/Desktop/internet_dungeon_new && time make check   # 1 回目
tail ~/.cache/flix-checkd/*/daemon.log                  # 原因ログが出ているか
time make check                                         # 2 回目(温まって数秒か)
```

判定: 段 1 のログでエラーの内訳が「lock 待ち」なら段 2 が的中。別のエラーの内訳(例: -Xmx の上限でウォームアップ中 OOM、
-XstartOnFirstThread、gh)が出たらそれを直す。**17 分 → 2〜3 分(素の check 相当)以下**になれば成功。

### 段 4(スパイクの後で。checkd-runaway-guard.md と統合)

- client.go:103 DropPort は DaemonAlive を見てから(生きている常駐の port を消さない)。
- daemon.go:580-609 loop がシングルスレッド → PING だけは check 中も即答(後続クライアントが最大 900 秒無音で並ぶ)。
- クライアントとデーモンが同じ workTimeoutSec 900 を共有 → ウォームアップ用 warmTimeoutSec(180〜300)を新設、クライアント > デーモンに。
- CHECKD_DEBUG が main.go:231-236 のバッファリングでプロセス終了まで出ない → checkd だけ即時 stderr。
- serve が pid 取得に負けたとき無言 return(daemon.go:59-61)→ 1 行ログ + クライアントは即先客へ。
- runFallback に上限(fallbackTimeoutSec 300)と重複起動ガード。
- hooks/checkd.go:260 ReserveDaemon が素の CLI に落ちる(docs/checkd.md:70 と矛盾)→ ウォームアップするだけの verb へ。

### 注意

- bin/lint-rules/hooks.json に鍵を足すときは LoadRules(go/internal/hooks/rules.go:104-200)が
  欠けキーで止まるため、**Studio 同梱の写し(~/.flix_ge_studio/engines/0.33.2/bin/lint-rules/hooks.json)も同時更新**。
- 配布ランタイム(~/.flix_ge_studio/engines/0.33.2)には go/ が無く、そこからの sync-agents は動かない。
  sync-agents は必ずこのソースリポから。

## 関連(ゲーム側 internet_dungeon_new の緩和・別セッションで)

- local.mk に `CHECKD := 0`(engine 修正が入ったら消す)
- ゲーム Makefile に checkd-stop / clean-locks の口
- .codex/hooks.json が腐っている(存在しない .claude/hooks/*.py)→ sync-agents で正規化
- make test 遅い件は別問題: 素の Flix 全体コンパイル 6.5 分 + テスト 6 秒(ハングではない)。
  checkd --test(常駐でのテスト)を test の既定にする改善はここの段 4 の後で検討。
