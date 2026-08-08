# ゲーム開発の入口。
#   make run    … ゲームを起動する（窓が開く）
#   make debug  … 保存即反映(watchFile)と F8 を有効にして起動
#   make test   … テストを実行する
#   make check  … 型検査だけ走らせる（一番速い確認）
#   make bake   … ギャラリー PNG を焼く（決定的）
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
# -Xss64m: View の式が深く入れ子になると、既定のスタックでは型検査が StackOverflow で落ちる。
FLIX   := "$(JAVA)" -Xss64m -jar "$(ENGINE)/bin/flix.jar"
else
PYTHON ?= python3
FLIX   := "$(ENGINE)/bin/flix"
endif

.PHONY: run debug test build check bake bench golden atelier-preview

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

bake:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) run --entrypoint Bake.all

bench: bake
	"$(ENGINE)/bin/golden-check.sh"

golden:
	"$(ENGINE)/bin/golden-bless.sh"

atelier-preview:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) run --entrypoint Bake.atelier
