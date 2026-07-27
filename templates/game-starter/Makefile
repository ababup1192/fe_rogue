# ゲーム開発の入口。
#   make run    … ゲームを起動する（窓が開く）
#   make debug  … 保存即反映(watchFile)と F8 を有効にして起動
#   make test   … テストを実行する
#   make check  … 型検査だけ走らせる（一番速い確認）
#   make bake   … ギャラリー PNG を焼く（決定的。先に palette を作り直す）
#   make palette … Studio 用の色の写し(assets/__NAME__.palette.json)を作り直す
#   make bench  … 焼いた絵を golden とバイト比較する
#   make golden … いまの gallery を golden として祝福する
#   make atelier-preview … atelier/ の候補と assets/ の現行を debug/atelier/ に焼く
#
# Flix コンパイラはエンジンリポの bin/flix ラッパ経由で呼ぶ（devbox shell の外でも動く）。
# ラッパが nix store の flix.jar 解決と JVM フラグ（-XstartOnFirstThread、test/Bake の
# headless）を面倒みるので、ここでは素の $(FLIX) を呼ぶだけでよい。
# エンジンの場所が違うときは `make run ENGINE=/path/to/flix_game_engine` で上書きする。
ENGINE ?= __ENGINE__
FLIX   := $(ENGINE)/bin/flix

.PHONY: run debug test build check bake bench golden atelier-preview palette

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
