# ゲーム開発の入口。
#   make run    … ゲームを起動する（窓が開く）
#   make debug  … 保存即反映(watchFile)と F8 を有効にして起動
#   make test   … テストを実行する（記録は .test-logs/）
#   make status … 現状 1 画面（テスト記録・golden・チケット・git）
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
# Flix コンパイラの呼び方は OS で変える:
#   - macOS/Linux … エンジンリポの bin/flix ラッパ（nix store の flix.jar 解決と JVM フラグ
#     （-XstartOnFirstThread、test/Bake の headless）を面倒みる）
#   - Windows … ラッパ（bash）が無いので、JRE の java で bin/flix.jar を直接叩く
# エンジンや java の場所はマシンごとに違うので、git に入れない local.mk に書く
# （make new-game / Studio が生成する。別のマシンで clone したら 1 度だけ書き直す）:
#   ENGINE := /abs/path/to/flix_game_engine   （Studio 同梱なら …/resources/engine）
#   JAVA   := /abs/path/to/java.exe           （Windows のみ。Studio 同梱 JRE の java.exe）
# 既定の ../.. は「テンプレを engine リポの中でそのまま動かす」ための値。
-include local.mk
ENGINE ?= ../..
ifeq ($(wildcard $(ENGINE)/bin/flix*),)
$(warning ENGINE が見当たりません ($(ENGINE)) — local.mk に「ENGINE := /path/to/flix_game_engine」を書くか、make <対象> ENGINE=... で指定してください)
endif
ifeq ($(OS),Windows_NT)
JAVA   ?= java
PYTHON ?= python
# -Xss64m: View の式が深く入れ子になると、既定のスタックでは型検査が StackOverflow で落ちる。
FLIX   := "$(JAVA)" -Xss64m -jar "$(ENGINE)/bin/flix.jar"
else
PYTHON ?= python3
FLIX   := "$(ENGINE)/bin/flix"
endif

.PHONY: status run debug test build check bake shot bench golden stages checkpoints playtest probe loc palette

run:
	$(FLIX) run

debug:
	DEBUG=true $(FLIX) run

# 出力は .test-logs/test.log に落とし、緑なら末尾 5 行だけ見せる。
# make status が「最後にいつ・緑か赤か」をこの記録から読む。
test:
	@mkdir -p .test-logs; rm -f .test-logs/test.fail
	@if JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) test > .test-logs/test.log 2>&1; then \
		tail -5 .test-logs/test.log; \
	else \
		touch .test-logs/test.fail; tail -40 .test-logs/test.log; exit 1; \
	fi

build:
	$(FLIX) build

check:
	$(FLIX) check

# Studio のドット絵エディタに legend の意味色キーの実色を教える写し（生成物）。
# 色を変えたら焼き直す — 忘れると編集画面だけ仮色になり、実機と配色が食い違う。
palette:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) run --entrypoint Palette.write

bake: palette
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) run --entrypoint Bake.all

shot:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" STAGE=$(STAGE) $(FLIX) run --entrypoint Bake.one

bench: bake
	"$(ENGINE)/bin/golden-check.sh"

golden:
	"$(ENGINE)/bin/golden-bless.sh"

stages:
	$(PYTHON) tools/check_stages.py

# 中間ポイントを等間隔に置き直す（assets/stages.stage.json を書き換える）。
# 置き直したら必ず静的検査へ — 戻り先が変われば面の流れも変わるため。
checkpoints:
	$(PYTHON) tools/space_checkpoints.py
	$(PYTHON) tools/check_stages.py

# ロジックの大きさ。「全部読める大きさ」（上限 3,000 行）を保つための物差し。
loc:
	@find src test -name '*.flix' -print0 | xargs -0 wc -l | tail -1

playtest:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) run --entrypoint Playtest.all

probe:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) run --entrypoint Probe.all

# 現状 1 画面 (テスト記録・golden・チケット・git)。何も実行しない。
# .claude/settings.json の SessionStart フックがセッション開始時に毎回呼ぶ。
status:
	@$(PYTHON) bin/status.py
