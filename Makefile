## fe_rogue モノレポの workspace コマンド
##
## 構成:
##   engine/      ─ 再利用ライブラリ。engine 自身の build / test / check は
##                   `cd engine && flix ...` で直接行う
##   editor/      ─ engine を依存する独立 fpkg (Godot 風エディタ)。
##                   `cd editor && flix ...` で直接
##   editor/lib/  ─ editor は engine fpkg を依存に持つので make sync で配布される
##   examples/    ─ 各 example も同様に `cd examples/<name> && flix ...` で直接
##
## Makefile に集約するのは workspace 横断の配布作業だけ:
##   `make sync` … engine と editor を build-pkg し、それぞれを依存している
##                  ディレクトリの lib/github/ababup1192/<pkg>/<version>/ に
##                  相対 symlink を張る (cp ではなく ln -sf)。
##                  symlink にすることで engine を rebuild すれば即座に反映され、
##                  例題側で stale な fpkg を持ち回らなくて済む。
##                  各ターゲットディレクトリの project root への相対パスは深さで決まる:
##                    editor/lib/github/.../0.1.0/        → 6 階層上 (../ x6)
##                    examples/<name>/lib/github/.../0.1.0/ → 7 階層上 (../ x7)
##                  ループ内で $$dir のスラッシュ数 + 5 (ENGINE_SUBPATH 階層) として計算する。

FLIX_JAR := $(CURDIR)/bin/flix.jar
FLIX     := java -XstartOnFirstThread -jar $(FLIX_JAR)

ENGINE_CORE_DIR       := engine_core
ENGINE_CORE_FPKG_SRC  := $(ENGINE_CORE_DIR)/artifact/engine_core.fpkg
ENGINE_CORE_TOML_SRC  := $(ENGINE_CORE_DIR)/flix.toml
ENGINE_CORE_SUBPATH   := lib/github/ababup1192/flix_engine_core/0.1.0
ENGINE_CORE_FPKG_NAME := flix_engine_core-0.1.0.fpkg
ENGINE_CORE_TOML_NAME := flix_engine_core-0.1.0.toml

RENDER_CORE_DIR       := render_core
RENDER_CORE_FPKG_SRC  := $(RENDER_CORE_DIR)/artifact/render_core.fpkg
RENDER_CORE_TOML_SRC  := $(RENDER_CORE_DIR)/flix.toml
RENDER_CORE_SUBPATH   := lib/github/ababup1192/flix_render_core/0.1.0
RENDER_CORE_FPKG_NAME := flix_render_core-0.1.0.fpkg
RENDER_CORE_TOML_NAME := flix_render_core-0.1.0.toml

ENGINE_DIR       := engine
ENGINE_FPKG_SRC  := $(ENGINE_DIR)/artifact/engine.fpkg
ENGINE_TOML_SRC  := $(ENGINE_DIR)/flix.toml
ENGINE_SUBPATH   := lib/github/ababup1192/flix_game_engine/0.1.0
ENGINE_FPKG_NAME := flix_game_engine-0.1.0.fpkg
ENGINE_TOML_NAME := flix_game_engine-0.1.0.toml

EDITOR_DIR       := editor
EDITOR_FPKG_SRC  := $(EDITOR_DIR)/artifact/editor.fpkg
EDITOR_TOML_SRC  := $(EDITOR_DIR)/flix.toml
EDITOR_SUBPATH   := lib/github/ababup1192/flix_engine_editor/0.1.0
EDITOR_FPKG_NAME := flix_engine_editor-0.1.0.fpkg
EDITOR_TOML_NAME := flix_engine_editor-0.1.0.toml

# lib/github/ababup1192/<pkg>/0.1.0 サブパスの階層数 (= 5)。
# `$$dir` のスラッシュ数 (editor/ なら 1、examples/<name>/ なら 2) と足して
# 全体の up 階層数を求め、symlink の相対パスを動的に組み立てる。
SUBPATH_DEPTH := 5

.PHONY: help sync sync-engine-core sync-render-core sync-engine sync-editor clean-locks

help:
	@echo "Targets:"
	@echo "  make sync             engine_core / render_core / engine / editor を build-pkg し、各依存先に配布"
	@echo "  make sync-engine-core engine_core だけ build-pkg & 配布 (render_core / engine / editor / ide / examples へ)"
	@echo "  make sync-render-core render_core だけ build-pkg & 配布 (engine / editor / ide / examples へ)"
	@echo "  make sync-engine      engine だけ build-pkg & 配布 (editor と examples の両方へ)"
	@echo "  make sync-editor      editor だけ build-pkg & 配布 (examples へ)"
	@echo "  make clean-locks      flix check 中断で残った Maven cache の *.lock を削除"

# flix check を Ctrl-C で中断すると lib/cache/.../*.lock が残り、
# 次回 Maven リゾルバが「他プロセスが取得中」と誤認して無限待ちになる。
# 各ワークスペース配下のロックをまとめて削除する。
clean-locks:
	@find . -path "*/lib/cache/*" -name "*.lock" -print -delete | awk 'END { print NR " lock(s) removed" }'

sync: clean-locks sync-engine-core sync-render-core sync-engine sync-editor

# engine_core は engine / render_core / editor / ide / examples すべてが（直接または推移的に）依存する。
# 最も土台のパッケージなので sync チェーンの先頭に置く。
sync-engine-core:
	cd $(ENGINE_CORE_DIR) && $(FLIX) build-pkg
	@for dir in $(RENDER_CORE_DIR)/ $(ENGINE_DIR)/ $(EDITOR_DIR)/ ide/ examples/*/; do \
		toml="$$dir/flix.toml"; \
		if [ -f "$$toml" ] && grep -qE "ababup1192/(flix_engine_core|flix_game_engine|flix_render_core)" "$$toml"; then \
			target="$${dir}$(ENGINE_CORE_SUBPATH)"; \
			mkdir -p "$$target"; \
			depth=$$(printf '%s' "$$dir" | tr -cd '/' | wc -c | tr -d ' '); \
			upcnt=$$((depth + $(SUBPATH_DEPTH))); \
			rel=$$(printf '../%.0s' $$(seq 1 $$upcnt)); \
			ln -sfn "$${rel}$(ENGINE_CORE_FPKG_SRC)" "$$target/$(ENGINE_CORE_FPKG_NAME)"; \
			ln -sfn "$${rel}$(ENGINE_CORE_TOML_SRC)" "$$target/$(ENGINE_CORE_TOML_NAME)"; \
			echo "[sync-engine-core] $$target"; \
		fi \
	done

# render_core は engine_core に依存。engine / editor / ide / examples (engine 経由) が利用する。
# editor は engine.fpkg を経由して render_core を transitive に必要とするため、配布対象に含める。
sync-render-core:
	cd $(RENDER_CORE_DIR) && $(FLIX) build-pkg
	@for dir in $(ENGINE_DIR)/ $(EDITOR_DIR)/ ide/ examples/*/; do \
		toml="$$dir/flix.toml"; \
		if [ -f "$$toml" ] && grep -qE "ababup1192/(flix_render_core|flix_game_engine)" "$$toml"; then \
			target="$${dir}$(RENDER_CORE_SUBPATH)"; \
			mkdir -p "$$target"; \
			depth=$$(printf '%s' "$$dir" | tr -cd '/' | wc -c | tr -d ' '); \
			upcnt=$$((depth + $(SUBPATH_DEPTH))); \
			rel=$$(printf '../%.0s' $$(seq 1 $$upcnt)); \
			ln -sfn "$${rel}$(RENDER_CORE_FPKG_SRC)" "$$target/$(RENDER_CORE_FPKG_NAME)"; \
			ln -sfn "$${rel}$(RENDER_CORE_TOML_SRC)" "$$target/$(RENDER_CORE_TOML_NAME)"; \
			echo "[sync-render-core] $$target"; \
		fi \
	done

# engine は editor と examples の両方が依存している
# fpkg / toml は cp ではなく相対 symlink で配布する (engine 再ビルドが即反映される)
sync-engine:
	cd $(ENGINE_DIR) && $(FLIX) build-pkg
	@for dir in $(EDITOR_DIR)/ ide/ examples/*/; do \
		toml="$$dir/flix.toml"; \
		if [ -f "$$toml" ] && grep -q "ababup1192/flix_game_engine" "$$toml"; then \
			target="$${dir}$(ENGINE_SUBPATH)"; \
			mkdir -p "$$target"; \
			depth=$$(printf '%s' "$$dir" | tr -cd '/' | wc -c | tr -d ' '); \
			upcnt=$$((depth + $(SUBPATH_DEPTH))); \
			rel=$$(printf '../%.0s' $$(seq 1 $$upcnt)); \
			ln -sfn "$${rel}$(ENGINE_FPKG_SRC)" "$$target/$(ENGINE_FPKG_NAME)"; \
			ln -sfn "$${rel}$(ENGINE_TOML_SRC)" "$$target/$(ENGINE_TOML_NAME)"; \
			echo "[sync-engine] $$target"; \
		fi \
	done

# editor は examples のみが依存しうる (engine は editor に依存しない)
sync-editor:
	cd $(EDITOR_DIR) && $(FLIX) build-pkg
	@for dir in examples/*/; do \
		toml="$$dir/flix.toml"; \
		if [ -f "$$toml" ] && grep -q "ababup1192/flix_engine_editor" "$$toml"; then \
			target="$${dir}$(EDITOR_SUBPATH)"; \
			mkdir -p "$$target"; \
			depth=$$(printf '%s' "$$dir" | tr -cd '/' | wc -c | tr -d ' '); \
			upcnt=$$((depth + $(SUBPATH_DEPTH))); \
			rel=$$(printf '../%.0s' $$(seq 1 $$upcnt)); \
			ln -sfn "$${rel}$(EDITOR_FPKG_SRC)" "$$target/$(EDITOR_FPKG_NAME)"; \
			ln -sfn "$${rel}$(EDITOR_TOML_SRC)" "$$target/$(EDITOR_TOML_NAME)"; \
			echo "[sync-editor] $$target"; \
		fi \
	done
