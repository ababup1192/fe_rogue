## fe_rogue モノレポの workspace コマンド
##
## 構成:
##   engine/      ─ 再利用ライブラリ。engine 自身の build / test / check は
##                   `cd engine && flix ...` で直接行う
##   examples/    ─ 各 example も同様に `cd examples/<name> && flix ...` で直接
##
## Makefile に集約するのは workspace 横断の作業だけ:
##   `make sync` … engine を build-pkg して、engine を依存している全 example の
##                  `lib/github/ababup1192/flix_game_engine/0.1.0/` に fpkg と
##                  flix.toml を配布する

FLIX_JAR    := $(CURDIR)/bin/flix.jar
FLIX        := java -XstartOnFirstThread -jar $(FLIX_JAR)

ENGINE_DIR       := engine
ENGINE_FPKG_SRC  := $(ENGINE_DIR)/artifact/engine.fpkg
ENGINE_TOML_SRC  := $(ENGINE_DIR)/flix.toml

# engine fpkg の配布先 (各 example の lib/github/ の末端)
ENGINE_LIB_SUBPATH := lib/github/ababup1192/flix_game_engine/0.1.0
ENGINE_FPKG_NAME   := flix_game_engine-0.1.0.fpkg
ENGINE_TOML_NAME   := flix_game_engine-0.1.0.toml

.PHONY: help sync

help:
	@echo "Targets:"
	@echo "  make sync   engine を build-pkg して、engine 依存を持つ全 example に配布"

sync:
	cd $(ENGINE_DIR) && $(FLIX) build-pkg
	@for dir in examples/*/; do \
		toml="$$dir/flix.toml"; \
		if [ -f "$$toml" ] && grep -q "ababup1192/flix_game_engine" "$$toml"; then \
			target="$$dir/$(ENGINE_LIB_SUBPATH)"; \
			mkdir -p "$$target"; \
			cp $(ENGINE_FPKG_SRC) "$$target/$(ENGINE_FPKG_NAME)"; \
			cp $(ENGINE_TOML_SRC) "$$target/$(ENGINE_TOML_NAME)"; \
			echo "[sync] $$target に engine を反映"; \
		fi \
	done
