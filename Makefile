## fe_rogue モノレポの workspace コマンド
##
## 構成:
##   engine_core/ ─ engine の中で純粋な計算寄りを切り出した土台パッケージ
##   render_core/ ─ engine_core を依存にする描画レイヤパッケージ
##   engine/      ─ 再利用ライブラリ。engine 自身の build / test / check は
##                   `cd engine && flix ...` で直接行う
##   ide/         ─ Swing + AWTGLCanvas ベースのシーンエディタ (engine を依存)
##   examples/    ─ 各 example も `cd examples/<name> && flix ...` で直接
##
## Makefile に集約するのは workspace 横断の配布作業だけ:
##   `make sync` … engine_core / render_core / engine / engine_world / engine_tools を build-pkg し、それぞれを
##                  依存しているディレクトリの lib/github/ababup1192/<pkg>/<version>/ に
##                  相対 symlink を張る (cp ではなく ln -sf)。
##                  symlink にすることで engine を rebuild すれば即座に反映され、
##                  例題側で stale な fpkg を持ち回らなくて済む。
##                  各ターゲットディレクトリの project root への相対パスは深さで決まる:
##                    engine_world/lib/github/.../0.1.0/      → 6 階層上 (../ x6)  (ide と同じ深さ)
##                    ide/lib/github/.../0.1.0/             → 6 階層上 (../ x6)
##                    examples/<name>/lib/github/.../0.1.0/ → 7 階層上 (../ x7)
##                  ループ内で $$dir のスラッシュ数 + 5 (ENGINE_SUBPATH 階層) として計算する。

FLIX_JAR := $(CURDIR)/bin/flix.jar
FLIX     := java -XstartOnFirstThread -jar $(FLIX_JAR)

# テスト専用の起動形。macOS では -XstartOnFirstThread (LWJGL 必須) と AWT の
# 初期化が競合し、フォントアトラス焼き (HeadlessFont → BufferedImage) が
# ネイティブ内で永久ハングすることがある。テストは全てヘッドレス設計
# (実ウィンドウを開かない) なので headless を明示して AWT を安全な初期化に固定する。
# 実機起動 (flix run) や IDE には付けないこと (IDE は JavaFX なので起動不能になる)。
FLIX_TEST := java -XstartOnFirstThread -Djava.awt.headless=true -jar $(FLIX_JAR)

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

# engine_world は engine に依存する再利用 ECS lib。examples が利用する。
ENGINE_WORLD_DIR       := engine_world
ENGINE_WORLD_FPKG_SRC  := $(ENGINE_WORLD_DIR)/artifact/engine_world.fpkg
ENGINE_WORLD_TOML_SRC  := $(ENGINE_WORLD_DIR)/flix.toml
ENGINE_WORLD_SUBPATH   := lib/github/ababup1192/flix_engine_world/0.1.0
ENGINE_WORLD_FPKG_NAME := flix_engine_world-0.1.0.fpkg
ENGINE_WORLD_TOML_NAME := flix_engine_world-0.1.0.toml

# engine_tools は engine (+ engine_core) に依存するヘッドレス描画/スナップショット工具箱 lib。examples が利用する。
ENGINE_TOOLS_DIR       := engine_tools
ENGINE_TOOLS_FPKG_SRC  := $(ENGINE_TOOLS_DIR)/artifact/engine_tools.fpkg
ENGINE_TOOLS_TOML_SRC  := $(ENGINE_TOOLS_DIR)/flix.toml
ENGINE_TOOLS_SUBPATH   := lib/github/ababup1192/flix_engine_tools/0.1.0
ENGINE_TOOLS_FPKG_NAME := flix_engine_tools-0.1.0.fpkg
ENGINE_TOOLS_TOML_NAME := flix_engine_tools-0.1.0.toml

# lib/github/ababup1192/<pkg>/0.1.0 サブパスの階層数 (= 5)。
# `$$dir` のスラッシュ数 (ide/ なら 1、examples/<name>/ なら 2) と足して
# 全体の up 階層数を求め、symlink の相対パスを動的に組み立てる。
SUBPATH_DEPTH := 5

.PHONY: help sync sync-engine-core sync-render-core sync-engine sync-engine-world sync-engine-tools clean-locks clean-example-builds test bake

help:
	@echo "Targets:"
	@echo "  make test                 全パッケージ (engine系 + examples) のテストを headless で実行"
	@echo "  make test-<name>          1 つだけテスト (例: make test-fe_rogue / make test-engine)"
	@echo "  make bake                 bake ターゲットを持つ全 example の生成物を焼き直す"
	@echo "  make sync                 engine_core / render_core / engine / engine_world / engine_tools を build-pkg し、各依存先に配布"
	@echo "  make sync-engine-core     engine_core だけ build-pkg & 配布 (render_core / engine / engine_world / ide / examples へ)"
	@echo "  make sync-render-core     render_core だけ build-pkg & 配布 (engine / engine_world / ide / examples へ)"
	@echo "  make sync-engine          engine だけ build-pkg & 配布 (engine_world / ide / examples へ)"
	@echo "  make sync-engine-world      engine_world だけ build-pkg & 配布 (examples へ)"
	@echo "  make sync-engine-tools    engine_tools だけ build-pkg & 配布 (examples へ)"
	@echo "  make clean-locks          flix check 中断で残った Maven cache の *.lock を削除"
	@echo "  make clean-example-builds examples/*/build/ を全削除 (IDE の scene.json glob 高速化用)"

# flix check を Ctrl-C で中断すると lib/cache/.../*.lock が残り、
# 次回 Maven リゾルバが「他プロセスが取得中」と誤認して無限待ちになる。
# 各ワークスペース配下のロックをまとめて削除する。
clean-locks:
	@find . -path "*/lib/cache/*" -name "*.lock" -print -delete | awk 'END { print NR " lock(s) removed" }'

# IDE で examples 配下のプロジェクトを開くと ProjectLoader.findSceneFiles の Fs.Glob が
# build/class 配下の数十万コンパイル成果物を stat してしまい、プロジェクト読み込みに
# 数十秒〜数分かかる。IDE 起動前に各 example の build/ を消して回避する。
# 個別の example を flix run すれば build/ は再生成される (incremental compile は失われる)。
clean-example-builds:
	@removed=0; \
	for d in examples/*/build; do \
		if [ -d "$$d" ]; then \
			rm -rf "$$d"; \
			echo "[clean-example-builds] removed $$d"; \
			removed=$$((removed + 1)); \
		fi \
	done; \
	echo "[clean-example-builds] $$removed build dir(s) removed"

# ── テスト ────────────────────────────────────────────────
# 全パッケージのテストを順に回す。1 つでも赤ならそこで止まり exit 1。
TEST_DIRS := $(ENGINE_CORE_DIR) $(RENDER_CORE_DIR) $(ENGINE_DIR) $(ENGINE_WORLD_DIR) $(ENGINE_TOOLS_DIR) $(wildcard examples/*)

test:
	@for dir in $(TEST_DIRS); do \
		echo "===== $$dir ====="; \
		(cd "$$dir" && $(FLIX_TEST) test) || exit 1; \
	done

# ── bake ──────────────────────────────────────────────────
# 各 example のギャラリー・効果音などの生成物を一括で焼き直す。
# 対象は「Makefile に bake ターゲットを持つ example」だけ
# (fe_rogue は生成系を作り替え中のため、整備後にここへ合流する)。
bake:
	@for dir in examples/*/; do \
		if [ -f "$$dir/Makefile" ] && grep -q "^bake:" "$$dir/Makefile"; then \
			echo "===== $$dir ====="; \
			(cd "$$dir" && make bake) || exit 1; \
		fi \
	done

# 個別テスト: make test-fe_rogue (examples/ を先に探し、無ければルート直下のパッケージ名)
test-%:
	@if [ -d "examples/$*" ]; then \
		cd "examples/$*" && $(FLIX_TEST) test; \
	else \
		cd "$*" && $(FLIX_TEST) test; \
	fi

sync: clean-locks sync-engine-core sync-render-core sync-engine sync-engine-world sync-engine-tools

# engine_core は engine / render_core / ide / examples すべてが（直接または推移的に）依存する。
# 最も土台のパッケージなので sync チェーンの先頭に置く。
sync-engine-core:
	cd $(ENGINE_CORE_DIR) && $(FLIX) build-pkg
	@for dir in $(RENDER_CORE_DIR)/ $(ENGINE_DIR)/ $(ENGINE_WORLD_DIR)/ $(ENGINE_TOOLS_DIR)/ ide/ examples/*/; do \
		toml="$$dir/flix.toml"; \
		if [ -f "$$toml" ] && grep -qE "ababup1192/(flix_engine_core|flix_game_engine|flix_render_core|flix_engine_world|flix_engine_tools)" "$$toml"; then \
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

# render_core は engine_core に依存。engine / ide / examples (engine 経由) が利用する。
sync-render-core:
	cd $(RENDER_CORE_DIR) && $(FLIX) build-pkg
	@for dir in $(ENGINE_DIR)/ $(ENGINE_WORLD_DIR)/ $(ENGINE_TOOLS_DIR)/ ide/ examples/*/; do \
		toml="$$dir/flix.toml"; \
		if [ -f "$$toml" ] && grep -qE "ababup1192/(flix_render_core|flix_game_engine|flix_engine_world|flix_engine_tools)" "$$toml"; then \
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

# engine は ide / examples / engine_world が依存している
# fpkg / toml は cp ではなく相対 symlink で配布する (engine 再ビルドが即反映される)
sync-engine:
	cd $(ENGINE_DIR) && $(FLIX) build-pkg
	@for dir in $(ENGINE_WORLD_DIR)/ $(ENGINE_TOOLS_DIR)/ ide/ examples/*/; do \
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

# engine_world は engine を依存にする再利用 ECS lib。examples に配布する。
# engine に依存するので sync チェーンでは sync-engine の後に置く（lib に engine fpkg が要る）。
sync-engine-world:
	cd $(ENGINE_WORLD_DIR) && $(FLIX) build-pkg
	@for dir in examples/*/; do \
		toml="$$dir/flix.toml"; \
		if [ -f "$$toml" ] && grep -q "ababup1192/flix_engine_world" "$$toml"; then \
			target="$${dir}$(ENGINE_WORLD_SUBPATH)"; \
			mkdir -p "$$target"; \
			depth=$$(printf '%s' "$$dir" | tr -cd '/' | wc -c | tr -d ' '); \
			upcnt=$$((depth + $(SUBPATH_DEPTH))); \
			rel=$$(printf '../%.0s' $$(seq 1 $$upcnt)); \
			ln -sfn "$${rel}$(ENGINE_WORLD_FPKG_SRC)" "$$target/$(ENGINE_WORLD_FPKG_NAME)"; \
			ln -sfn "$${rel}$(ENGINE_WORLD_TOML_SRC)" "$$target/$(ENGINE_WORLD_TOML_NAME)"; \
			echo "[sync-engine-world] $$target"; \
		fi \
	done

# engine_tools は engine を依存にするヘッドレス描画/スナップショット工具箱 lib。examples に配布する。
# engine に依存するので sync チェーンでは sync-engine の後に置く（lib に engine fpkg が要る）。
sync-engine-tools:
	cd $(ENGINE_TOOLS_DIR) && $(FLIX) build-pkg
	@for dir in examples/*/; do \
		toml="$$dir/flix.toml"; \
		if [ -f "$$toml" ] && grep -q "ababup1192/flix_engine_tools" "$$toml"; then \
			target="$${dir}$(ENGINE_TOOLS_SUBPATH)"; \
			mkdir -p "$$target"; \
			depth=$$(printf '%s' "$$dir" | tr -cd '/' | wc -c | tr -d ' '); \
			upcnt=$$((depth + $(SUBPATH_DEPTH))); \
			rel=$$(printf '../%.0s' $$(seq 1 $$upcnt)); \
			ln -sfn "$${rel}$(ENGINE_TOOLS_FPKG_SRC)" "$$target/$(ENGINE_TOOLS_FPKG_NAME)"; \
			ln -sfn "$${rel}$(ENGINE_TOOLS_TOML_SRC)" "$$target/$(ENGINE_TOOLS_TOML_NAME)"; \
			echo "[sync-engine-tools] $$target"; \
		fi \
	done
