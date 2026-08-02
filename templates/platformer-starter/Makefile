# ゲーム開発の入口。
#   make run    … ゲームを起動する（窓が開く）
#   make debug  … 保存即反映(watchFile)と F8 を有効にして起動
#   make test   … テストを実行する
#   make check  … 型検査だけ走らせる（一番速い確認）
#   make bake   … ギャラリー PNG を焼く（決定的）
#   make palette … Studio 用の色の写し(assets/px.palette.json)を作り直す
#   make shot STAGE=1 … 調整中の 1 面だけ debug/shot.png へ焼く（golden を汚さない）
#   make bench  … 焼いた絵を golden とバイト比較する
#   make golden … いまの gallery を golden として祝福する
#   make stages … 面の罠ゼロ(BFS)と流れを機械検査する
#   make checkpoints … 中間ポイント(c)を等間隔に置き直し、そのまま stages で検査する
#   make loc    … src/ + test/ の .flix 合計行数（上限 3,000 行）
#   make playtest … bot に通しで遊ばせて「走れるか・詰まらないか」を測る
#   make probe  … 面の読み込み・1 tick・タイル層の組み立てにかかる時間を測る
#
# Flix コンパイラはエンジンリポの bin/flix ラッパ経由で呼ぶ（devbox shell の外でも動く）。
# エンジンの場所が違うときは `make run ENGINE=/path/to/flix_game_engine` で上書きする。
ENGINE ?= ../..
FLIX   := $(ENGINE)/bin/flix

.PHONY: run debug test build check bake shot bench golden stages checkpoints playtest probe loc palette

run:
	"$(FLIX)" run

debug:
	DEBUG=true "$(FLIX)" run

test:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" "$(FLIX)" test

build:
	"$(FLIX)" build

check:
	"$(FLIX)" check

# Studio のドット絵エディタに legend の意味色キーの実色を教える写し（生成物）。
# 色を変えたら焼き直す — 忘れると編集画面だけ仮色になり、実機と配色が食い違う。
palette:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" "$(FLIX)" run --entrypoint Palette.write

bake: palette
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" "$(FLIX)" run --entrypoint Bake.all

shot:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" STAGE=$(STAGE) "$(FLIX)" run --entrypoint Bake.one

bench: bake
	@ok=1; for f in gallery/*.png; do \
		name=$$(basename $$f); \
		if cmp -s $$f golden/$$name; then echo "bench OK: $$name"; \
		else echo "bench DIFF: $$name"; ok=0; fi; \
	done; [ $$ok -eq 1 ]

golden:
	cp gallery/*.png golden/
	@echo "blessed: golden/*.png updated from gallery/"

stages:
	python3 tools/check_stages.py

# 中間ポイントを等間隔に置き直す（assets/stages.stage.json を書き換える）。
# 置き直したら必ず静的検査へ — 戻り先が変われば面の流れも変わるため。
checkpoints:
	python3 tools/space_checkpoints.py
	python3 tools/check_stages.py

# ロジックの大きさ。「全部読める大きさ」（上限 3,000 行）を保つための物差し。
loc:
	@find src test -name '*.flix' -print0 | xargs -0 wc -l | tail -1

playtest:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" "$(FLIX)" run --entrypoint Playtest.all

probe:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" "$(FLIX)" run --entrypoint Probe.all
