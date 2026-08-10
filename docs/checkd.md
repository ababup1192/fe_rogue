# checkd — flix check / flix test の常駐高速化

## 何が嬉しいか

`flix check` は毎回 JVM とコンパイラをゼロから立ち上げるので、小さなパッケージでも
5〜10 秒かかる。`bin/checkd` はパッケージごとに flix repl を裏で 1 つだけ温めて持ち、
2 回目からの check を **0.3〜0.5 秒**で返す。

```
bin/checkd [パッケージdir]     # check する (省略時はカレント)。見た目と exit code は素の check と同じ
bin/checkd --test [dir]        # test する (check と同じ常駐 repl を使う)
bin/checkd --stop [dir]        # そのパッケージの常駐を止める
bin/checkd --stop-all          # 常駐を全部止める (make checkd-stop と同じ)
```

examples の `make check` / `make test` は自動でこれを通る。**素の経路に戻したい時は
`CHECKD=0 make check` / `CHECKD=0 make test`**。

## どう動くか

```
make check ──> bin/checkd (クライアント)
                  │ TCP 127.0.0.1    常駐が無ければ自動で立てる。実ポートは
                  ▼                  ~/.cache/flix-checkd/<ハッシュ>/port に書いてある。
                  │                  会話に失敗したら素の bin/flix check に落ちる
               checkd 常駐 (パッケージごとに 1 つ)
                  │ パイプで :check を送り、結果を CLI と同じ見た目に整える
                  ▼
               flix repl (温まった JVM)
```

- ソースは repl が毎回ディスクから読み直すので、保存 → check だけでよい
- 結果の正しさが常に最優先。少しでも怪しければ黙って素の check に落ちる

## test も同じ常駐で速くなる

check と test は 1 本の repl が両方受ける。温まった repl の `:test` は、素の
`flix test` (sokoban で 9〜12 秒) が **3〜4 秒**になる (約 3 倍)。exit code は
出力のまとめ行 (`Passed: N, Failed: M.`) から復元し、行が読み取れない出力なら
推測せず素の CLI に投げ直す。テスト本数・失敗本文は CLI と同じに出る。

注意が 2 つ:

- `:test` は 1 回ごとにメモリが数百 MB 増える (check より漏れが速い)。4GB の
  上限に当たったら repl をその場で使い捨てるので、直後の 1 回だけ遅くなるのは仕様
- repl には常に `-Djava.awt.headless=true` を付けて起動する。GLFW と AWT の初期化が
  ぶつかるとテストが固まるパッケージがあるため (fe_rogue 等)。checkd は run を
  扱わないので、常時付けて害はない

結果が疑わしい時の逃げ道は check と同じ: `CHECKD=0 make test` で素の経路に戻る。

## 常駐は勝手に片づく

デーモンが溜まって Mac を重くしないよう、自分で消える:

- 30 分誰も check / test しなければ自殺する
- `flix.toml` や `lib/` の依存の実体 (symlink の先も見る) が変わったら、古い依存を
  握り続けないよう repl を作り直す (`make sync-engine` 後の check も安全)
- メモリが 4GB を超えるか check / test 合計 200 回で repl を使い捨てて立て直す

## 困ったら

```
make checkd-stop        # 全部止める。次の check が立て直すので、いつ打っても壊れない
```

check の結果がどうしても疑わしい時は `CHECKD=0 make check`(または `bin/flix check`)で
素の経路と比べる。常駐の記録は `~/.cache/flix-checkd/<ハッシュ>/daemon.log` にある。
`CHECKD_DEBUG=1` を付けると、クライアントがなぜ素の check に落ちたかを表示する。

## 対象外 (今はやらない)

- `make run` の常駐化 (repl は絵の窓を出せないし、常時 headless とも相性が悪い)
- engine / engine_world 等パッケージ本体の test (まず examples で様子を見る)
- LSP (`flix lsp`) 経由の診断: 0.75.1 では CLI check と結果が食い違う偽エラーを
  出すことがあり不採用
