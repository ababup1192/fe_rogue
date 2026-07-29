# ゲーム開発の入口。
#   make run    … ゲームを起動する（窓が開く）
#   make debug  … 保存即反映(watchFile)と F8 を有効にして起動
#   make test   … テストを実行する
#   make check  … 型検査だけ走らせる（一番速い確認）
#   make bake   … ギャラリー PNG を焼く（決定的。先に palette を作り直す）
#   make palette … Studio 用の色の写し(assets/rpg.palette.json)を作り直す
#   make bench  … 焼いた絵を golden とバイト比較する
#   make golden … いまの gallery を golden として祝福する
#   make atelier-preview … atelier/ の候補と assets/ の現行を debug/atelier/ に焼く
#   make cutscene … イベントシーン(assets/*.cutscene.json)を debug/cutscene/ に焼く
#                   1 本だけなら make cutscene FILE=assets/intro.cutscene.json
#   make cutscene-watch … 脚本の保存を見張って焼き直す(編集ループ用)
#   make cutscene-server … 常駐の焼き係(2 回目からは秒単位。curl で頼む)
#   make cutscene-grid … 間取りを座標定規つきで debug/cutscene/grid/ に焼く
#   make hosts  … 焼き係(cutscene 8793)を起こす(冪等・非ブロッキング)。
#                 Studio の自動起動もこれを撃つ。止めるのは make hosts-stop。
#                 放置 10 分で自分からも消える(BakeService)。
#
# Flix コンパイラはエンジンリポの bin/flix ラッパ経由で呼ぶ（devbox shell の外でも動く）。
# ラッパが nix store の flix.jar 解決と JVM フラグ（-XstartOnFirstThread、test/Bake の
# headless）を面倒みるので、ここでは素の $(FLIX) を呼ぶだけでよい。
# エンジンの場所が違うときは `make run ENGINE=/path/to/flix_game_engine` で上書きする。
ENGINE ?= /Users/abab/Desktop/flix_game_engine
FLIX   := $(ENGINE)/bin/flix

.PHONY: run debug test build check bake bench golden atelier-preview palette cutscene cutscene-watch cutscene-server cutscene-grid hosts hosts-stop

run:
	$(FLIX) run

debug:
	DEBUG=true $(FLIX) run

test:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) test

build:
	$(FLIX) build

check:
	$(FLIX) check

palette:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) run --entrypoint Palette.write

bake: palette
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) run --entrypoint Bake.all

bench: bake
	@ok=1; for f in gallery/*.png; do \
		name=$$(basename $$f); \
		if cmp -s $$f golden/$$name; then echo "bench OK: $$name"; \
		else echo "bench DIFF: $$name"; ok=0; fi; \
	done; [ $$ok -eq 1 ]

golden:
	cp gallery/*.png golden/
	@echo "blessed: golden/*.png updated from gallery/"

atelier-preview:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) run --entrypoint Bake.atelier

# イベントシーンを debug/cutscene/ に GIF＋コマ別 PNG で焼く(golden の外)
cutscene:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" CUTSCENE_FILE="$(FILE)" \
	  $(FLIX) run --entrypoint CutsceneBake.all

# 常駐のイベントシーン焼き係。立ち上げ(コンパイル + JVM + フォントの仕度)が 1 回で
# 済むので、2 回目からは演じて焼く時間だけ = 秒単位で編集ループが回る。
# 10 分放置で自分から終わる(BakeService)。
# 使い方:
#   make cutscene-server &   # 立ち上げ(初回は分の単位。listening が出たら準備完了)
#   curl -X POST 'http://127.0.0.1:8793/cutscene?file=assets/intro.cutscene.json'
#   curl -X POST 'http://127.0.0.1:8793/cutscene'   # 全シーン
#   curl -X POST 'http://127.0.0.1:8793/cutscene?file=…&draft=1'   # 下書き(等倍+粗い間引き。debug/cutscene/draft/ へ)
#   curl -X POST 'http://127.0.0.1:8793/cutscene/frame?file=…&cut=3'   # カット 3 の最初の拍を PNG 1 枚
# 応答は {"baked":[{"gif":…,"frames":…,"pngFrames":…,"stride":…,"draft":…,"notes":[…]}]}
# (notes = 飛ばしたカットの報せ)。/cutscene/frame は {"png":…,"cut":…,"notes":[…]}。
# ポートは CUTSCENE_PORT で変えられる(既定 8793)。
cutscene-server:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) run --entrypoint CutscenePreview.main

# 間取りを座標定規つき(上端に x・左端に y の数字)で debug/cutscene/grid/grid.png に焼く。
# 脚本の start / at のマスを数える下敷き(golden の外)。
cutscene-grid:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) run --entrypoint CutsceneBake.grid

# 焼き係(常駐サーバ)を起こす(冪等・非ブロッキング)。
# /health への疎通が無ければ nohup で起こし、すぐ戻る — 起動完了は待たない
# (初回はコンパイル込みで分の単位。debug/cutscene-server.log に listening が出たら準備完了)。
# Studio の bakeCmd もこれを撃つ(冪等なので毎回撃ってよい)。
# 止めるのは make hosts-stop。放置 10 分で自分からも消える(BakeService)。
CUTSCENE_PORT ?= 8793

hosts:
	@mkdir -p debug
	@if curl -s -m 1 "http://127.0.0.1:$(CUTSCENE_PORT)/health" > /dev/null 2>&1; then \
	  echo "cutscene 焼き係: 既に稼働中 (port $(CUTSCENE_PORT))"; \
	else \
	  CUTSCENE_PORT=$(CUTSCENE_PORT) nohup $(MAKE) cutscene-server > debug/cutscene-server.log 2>&1 & \
	  echo "cutscene 焼き係: 起こした (port $(CUTSCENE_PORT))。準備完了は debug/cutscene-server.log の listening を待つ"; \
	fi

# 焼き係を止める。ポートで LISTEN しているプロセスを特定して kill する。
hosts-stop:
	@pids=$$(lsof -ti:$(CUTSCENE_PORT) 2>/dev/null); \
	if [ -n "$$pids" ]; then kill $$pids && echo "port $(CUTSCENE_PORT): 止めた (pid $$pids)"; \
	else echo "port $(CUTSCENE_PORT): 稼働なし"; fi

# 脚本の保存を見張り、変わったファイルだけ焼き直す(2 秒ごとのポーリング。Ctrl-C で止める)
cutscene-watch:
	@mkdir -p debug/cutscene/.stamp; while true; do \
	  for f in assets/*.cutscene.json; do \
	    b=$$(basename $$f); st="debug/cutscene/.stamp/$$b.sum"; s=$$(cksum "$$f"); \
	    if [ "$$s" != "$$(cat $$st 2>/dev/null)" ]; then \
	      echo "$$s" > "$$st"; $(MAKE) cutscene FILE="$$f"; fi; \
	  done; sleep 2; done
