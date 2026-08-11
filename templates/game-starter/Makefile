# ゲーム開発の入口。
#   make run    … ゲームを起動する（窓が開く）
#   make debug  … 保存即反映(watchFile)と F8 を有効にして起動
#   make test   … テストを実行する（記録は .test-logs/）
#   make status … 現状 1 画面（テスト記録・golden・チケット・git）
#   make check  … 型検査だけ走らせる（一番速い確認）
#   make bake   … ギャラリー PNG を焼く（決定的。先に palette を作り直す）
#   make palette … Studio 用の色の写し(assets/__NAME__.palette.json)を作り直す
#   make bench  … 焼いた絵を golden とバイト比較する
#   make golden … いまの gallery を golden として祝福する
#   make atelier-preview … atelier/ の候補と assets/ の現行を debug/atelier/ に焼く
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
# 常駐 checkd は bash ラッパー (bin/flix) しか起動を知らず、Windows の
# JAVA+flix.jar 経路では落ちる。checkd が教わるまで Windows では素の check を使う。
CHECKD := 0
# -Xss64m: View の式が深く入れ子になると、既定のスタックでは型検査が StackOverflow で落ちる。
FLIX   := "$(JAVA)" -Xss64m -jar "$(ENGINE)/bin/flix.jar"
else
PYTHON ?= python3
FLIX   := "$(ENGINE)/bin/flix"
endif

.PHONY: status run debug test build check bake bench golden atelier-preview palette api

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

# check の全文は .test-logs/check.log に落とし、画面には要約だけ出す:
# 成功 = 1 行、失敗 = 最初のエラー全文 + 残りの file:line 一覧 + 処方箋 1 行
# (bin/explain-error が整形。全文が欲しいときは QUIET=0 make check かログを開く)。
# 常駐 (bin/checkd) が居れば 2 回目からサブ秒。CHECKD=0 make check で素の check。
check:
	@mkdir -p .test-logs
	@if [ "$(CHECKD)" != "0" ] && [ -f bin/checkd ]; then \
		"$(PYTHON)" bin/checkd . > .test-logs/check.log 2>&1; code=$$?; \
	else \
		$(FLIX) check > .test-logs/check.log 2>&1; code=$$?; \
	fi; \
	ee=bin/explain-error; [ -f "$$ee" ] || ee="$(ENGINE)/bin/explain-error"; \
	if [ "$(QUIET)" = "0" ] || [ ! -f "$$ee" ]; then \
		cat .test-logs/check.log; \
	else \
		"$(PYTHON)" "$$ee" --status $$code --log .test-logs/check.log < .test-logs/check.log; \
	fi; \
	exit $$code

# エンジン API の型・引数を 1 行で引く ($(ENGINE)/docs/api-digest の grep)。
# 例: make api Q=gradPolygon 。ソースの unzip や丸読みの前にまずこれ。
api:
	@test -n "$(Q)" || { echo "usage: make api Q=<関数名やモジュール名>"; exit 1; }
	@out=$$(grep -h -i -- "$(Q)" "$(ENGINE)/docs/api-digest/"*.md 2>/dev/null | head -40); \
	if [ -n "$$out" ]; then printf '%s\n' "$$out"; \
	else echo "[api] '$(Q)' に当たりなし。$(ENGINE)/docs/module-index.md で別名を探す"; fi

palette:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) run --entrypoint Palette.write

bake: palette
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) run --entrypoint Bake.all

bench: bake
	"$(ENGINE)/bin/golden-check.sh"

golden:
	"$(ENGINE)/bin/golden-bless.sh"

atelier-preview:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) run --entrypoint Bake.atelier

# 現状 1 画面 (テスト記録・golden・チケット・git)。何も実行しない。
# .claude/settings.json の SessionStart フックがセッション開始時に毎回呼ぶ。
status:
	@$(PYTHON) bin/status.py
