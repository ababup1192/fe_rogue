## Flix ゲームエンジン モノレポの workspace コマンド
##
## 構成:
##   engine/       ─ 契約層 flix_engine_core（Game/Audio effect・共有描画型・土台型・描画語彙）
##   render_gl/    ─ engine（契約層）を実装する GL バックエンド
##   engine_world/ ─ App/World/UI ランタイム。examples が利用する
##   engine_tools/ ─ ヘッドレス bake/snapshot 工具箱。examples が利用する
##   engine_full/  ─ 上4つのソースを1つに集めた自己完結の全部入り flix_game_engine（配布物）
##   examples/     ─ 各 example は `cd examples/<name> && flix ...` で直接
##
## Makefile に集約するのは workspace 横断の配布作業だけ:
##   `make sync` … engine / render_gl / engine_world / engine_tools を build-pkg し、それぞれを
##                  依存しているディレクトリの lib/github/ababup1192/<pkg>/<version>/ に
##                  相対 symlink を張る (cp ではなく ln -sf)。
##                  symlink にすることで engine を rebuild すれば即座に反映され、
##                  例題側で stale な fpkg を持ち回らなくて済む。
##                  各ターゲットディレクトリの project root への相対パスは深さで決まる:
##                    render_gl/lib/github/.../0.1.0/         → 6 階層上 (../ x6)
##                    engine_world/lib/github/.../0.1.0/      → 6 階層上 (../ x6)
##                    examples/<name>/lib/github/.../0.1.0/ → 7 階層上 (../ x7)
##                  ループ内で $$dir のスラッシュ数 + 5 (ENGINE_SUBPATH 階層) として計算する。

# Flix コンパイラは bin/flix ラッパー経由で呼ぶ。ラッパーが devbox (flix.nix) の
# flix コマンドと手動配置 bin/flix.jar のどちらを使うかを解決し、JVM フラグ
# (-XstartOnFirstThread、`test` サブコマンド時の -Djava.awt.headless=true) も
# サブコマンドに応じて自動で付ける。フラグの理由は bin/flix 内のコメント参照。
FLIX      := $(CURDIR)/bin/flix
FLIX_TEST := $(CURDIR)/bin/flix

# 全パッケージ共通のバージョン (lockstep)。sync 先ディレクトリ名や release の
# asset 名に使う。make bump FROM=x TO=y で各 flix.toml と一緒に上げる。
VERSION := 0.1.4

RENDER_GL_DIR       := render_gl
RENDER_GL_FPKG_SRC  := $(RENDER_GL_DIR)/artifact/render_gl.fpkg
RENDER_GL_TOML_SRC  := $(RENDER_GL_DIR)/flix.toml
RENDER_GL_SUBPATH   := lib/github/ababup1192/flix_render_gl/$(VERSION)
RENDER_GL_FPKG_NAME := flix_render_gl-$(VERSION).fpkg
RENDER_GL_TOML_NAME := flix_render_gl-$(VERSION).toml

ENGINE_DIR       := engine
ENGINE_FPKG_SRC  := $(ENGINE_DIR)/artifact/engine.fpkg
ENGINE_TOML_SRC  := $(ENGINE_DIR)/flix.toml
ENGINE_SUBPATH   := lib/github/ababup1192/flix_engine_core/$(VERSION)
ENGINE_FPKG_NAME := flix_engine_core-$(VERSION).fpkg
ENGINE_TOML_NAME := flix_engine_core-$(VERSION).toml

# engine_world は engine に依存する再利用 ECS lib。examples が利用する。
ENGINE_WORLD_DIR       := engine_world
ENGINE_WORLD_FPKG_SRC  := $(ENGINE_WORLD_DIR)/artifact/engine_world.fpkg
ENGINE_WORLD_TOML_SRC  := $(ENGINE_WORLD_DIR)/flix.toml
ENGINE_WORLD_SUBPATH   := lib/github/ababup1192/flix_engine_world/$(VERSION)
ENGINE_WORLD_FPKG_NAME := flix_engine_world-$(VERSION).fpkg
ENGINE_WORLD_TOML_NAME := flix_engine_world-$(VERSION).toml

# engine_tools は engine に依存するヘッドレス描画/スナップショット工具箱 lib。examples が利用する。
ENGINE_TOOLS_DIR       := engine_tools
ENGINE_TOOLS_FPKG_SRC  := $(ENGINE_TOOLS_DIR)/artifact/engine_tools.fpkg
ENGINE_TOOLS_TOML_SRC  := $(ENGINE_TOOLS_DIR)/flix.toml
ENGINE_TOOLS_SUBPATH   := lib/github/ababup1192/flix_engine_tools/$(VERSION)
ENGINE_TOOLS_FPKG_NAME := flix_engine_tools-$(VERSION).fpkg
ENGINE_TOOLS_TOML_NAME := flix_engine_tools-$(VERSION).toml

# engine_full は engine / render_gl / engine_world / engine_tools のソースを1つに集めた
# 自己完結の全部入りパッケージ (依存ゼロ・LWJGL ネイティブ自前)。examples はこれ1つだけを
# 依存にでき、公開も既存リポ flix_game_engine の Release 1つで完結する
# (推移先の別リポを見に行かない)。配布名は flix_game_engine でリポ名と一致させる。
ENGINE_FULL_DIR       := engine_full
ENGINE_FULL_FPKG_SRC  := $(ENGINE_FULL_DIR)/artifact/engine_full.fpkg
ENGINE_FULL_TOML_SRC  := $(ENGINE_FULL_DIR)/flix.toml
ENGINE_FULL_SUBPATH   := lib/github/ababup1192/flix_game_engine/$(VERSION)
ENGINE_FULL_FPKG_NAME := flix_game_engine-$(VERSION).fpkg
ENGINE_FULL_TOML_NAME := flix_game_engine-$(VERSION).toml

# lib/github/ababup1192/<pkg>/<version> サブパスの階層数 (= 5)。
# `$$dir` のスラッシュ数 (render_gl/ や engine_full/ なら 1、examples/<name>/ なら 2) と足して
# 全体の up 階層数を求め、symlink の相対パスを動的に組み立てる。
SUBPATH_DEPTH := 5

.PHONY: help sync sync-engine sync-render-gl sync-engine-world sync-engine-tools sync-engine-full sync-root-src clean-locks clean-example-builds test test-par bake bake-par release bump

help:
	@echo "Targets:"
	@echo "  make test                 全パッケージ (engine系 + examples) のテストを headless で実行"
	@echo "  make test-par             同上を並列実行 (壁時計 ≈ fe_rogue 1本分。ログは .test-logs/)"
	@echo "  make test-<name>          1 つだけテスト (例: make test-fe_rogue / make test-engine)"
	@echo "  make bake                 bake ターゲットを持つ全 example の生成物を焼き直す"
	@echo "  make bake-par             同上を並列実行"
	@echo "  make sync                 engine / render_gl / engine_world / engine_tools を build-pkg し、各依存先に配布"
	@echo "  make sync-render-gl       render_gl だけ build-pkg & 配布 (examples へ)"
	@echo "  make sync-engine          engine だけ build-pkg & 配布 (render_gl / engine_world / engine_tools / examples へ)"
	@echo "  make sync-engine-world      engine_world だけ build-pkg & 配布 (examples へ)"
	@echo "  make sync-engine-tools    engine_tools だけ build-pkg & 配布 (examples へ)"
	@echo "  make sync-root-src        コミュニティビルド用にルート src/ の symlink 集を再生成"
	@echo "  make clean-locks          flix check 中断で残った Maven cache の *.lock を削除"
	@echo "  make clean-example-builds examples/*/build/ を全削除 (IDE の scene.json glob 高速化用)"
	@echo "  make sync-engine-full     engine_full だけ src 集約 & build-pkg & 配布 (examples へ)"
	@echo "  make release              全部入りを build-pkg し flix_game_engine の Release に公開"
	@echo "  make bump FROM=x TO=y     全 flix.toml の version を一括更新 (lockstep)"

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
TEST_DIRS := $(ENGINE_DIR) $(RENDER_GL_DIR) $(ENGINE_WORLD_DIR) $(ENGINE_TOOLS_DIR) $(wildcard examples/*)

test:
	@for dir in $(TEST_DIRS); do \
		if [ -f "$$dir/flix.toml" ]; then \
			echo "===== $$dir ====="; \
			(cd "$$dir" && $(FLIX_TEST) test) || exit 1; \
		fi \
	done

# 並列テスト。各パッケージは独立 (別ディレクトリ・別 JVM) なので同時に回せて、
# 壁時計は最遅パッケージ (fe_rogue) 1本分まで縮む。ログは .test-logs/ にパッケージ別で残し、
# 赤があれば最後にそのログ末尾を表示して exit 1。並列数は TEST_PAR_JOBS で変えられる。
# xargs は -I でなく -n1 + $$0 渡し (BSD xargs の -I は置換後の引数が 255 バイト制限で、
# スクリプトに埋めると「command line cannot be assembled」で 1 本も走らない)。
# 「1 本も走っていないのに green」の偽陽性は実行数ガードで落とす。
TEST_PAR_JOBS ?= 6
test-par:
	@mkdir -p .test-logs; rm -f .test-logs/*.log .test-logs/*.fail; \
	printf '%s\n' $(TEST_DIRS) | xargs -P $(TEST_PAR_JOBS) -n 1 sh -c ' \
		dir="$$0"; [ -f "$$dir/flix.toml" ] || exit 0; \
		name=$$(printf "%s" "$$dir" | tr / _); \
		if (cd "$$dir" && $(FLIX_TEST) test) > ".test-logs/$$name.log" 2>&1; then \
			echo "[test-par] PASS $$dir"; \
		else \
			echo "[test-par] FAIL $$dir"; touch ".test-logs/$$name.fail"; \
		fi'; \
	ran=$$(ls .test-logs/*.log 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$ran" -eq 0 ]; then echo "[test-par] 1 本も実行されていない (xargs 失敗の疑い)"; exit 1; fi; \
	if ls .test-logs/*.fail > /dev/null 2>&1; then \
		echo "===== 失敗したパッケージのログ末尾 ====="; \
		for f in .test-logs/*.fail; do base=$${f%.fail}; echo "--- $$base"; tail -40 "$$base.log"; done; \
		exit 1; \
	fi; \
	echo "[test-par] all green ($$ran packages)"

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

# 並列 bake。example 同士は生成物が交わらないので同時に焼ける。ログ・失敗の扱いは test-par と同じ。
BAKE_PAR_JOBS ?= 4
bake-par:
	@mkdir -p .test-logs; rm -f .test-logs/bake-*.log .test-logs/bake-*.fail; \
	for dir in examples/*/; do \
		if [ -f "$$dir/Makefile" ] && grep -q "^bake:" "$$dir/Makefile"; then echo "$$dir"; fi; \
	done | xargs -P $(BAKE_PAR_JOBS) -n 1 sh -c ' \
		dir="$$0"; name=$$(basename "$$dir"); \
		if (cd "$$dir" && make bake) > ".test-logs/bake-$$name.log" 2>&1; then \
			echo "[bake-par] DONE $$dir"; \
		else \
			echo "[bake-par] FAIL $$dir"; touch ".test-logs/bake-$$name.fail"; \
		fi'; \
	ran=$$(ls .test-logs/bake-*.log 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$ran" -eq 0 ]; then echo "[bake-par] 1 本も実行されていない (xargs 失敗の疑い)"; exit 1; fi; \
	if ls .test-logs/bake-*.fail > /dev/null 2>&1; then \
		echo "===== 失敗した bake のログ末尾 ====="; \
		for f in .test-logs/bake-*.fail; do base=$${f%.fail}; echo "--- $$base"; tail -40 "$$base.log"; done; \
		exit 1; \
	fi; \
	echo "[bake-par] all done ($$ran examples)"

# 個別テスト: make test-fe_rogue (examples/ を先に探し、無ければルート直下のパッケージ名)
test-%:
	@if [ -d "examples/$*" ]; then \
		cd "examples/$*" && $(FLIX_TEST) test; \
	else \
		cd "$*" && $(FLIX_TEST) test; \
	fi

sync: clean-locks sync-engine sync-render-gl sync-engine-world sync-engine-tools sync-engine-full sync-root-src

# engine_full は engine / render_gl / engine_world / engine_tools のソースを1つに集めた
# 自己完結パッケージ (依存ゼロ)。ルート src/ と同じくファイル単位の symlink で4パッケージの
# .flix を engine_full/src/ に集約してから build-pkg し、最後に full を使う examples へ配る。
# ディレクトリ symlink は Flix のソース走査に追従されないため、必ずファイル単位で張る。
# エンジンに .flix を追加/削除/改名したら再実行して集約を更新する (sync-root-src と同じ運用)。
sync-engine-full:
	@for pkg in $(ROOT_SRC_PKGS); do rm -rf "$(ENGINE_FULL_DIR)/src/$$pkg"; done; \
	for pkg in $(ROOT_SRC_PKGS); do \
		(cd "$$pkg/src" && find . -name '*.flix') | sed 's|^\./||' | while read -r f; do \
			d=$$(dirname "$$f"); \
			if [ "$$d" = "." ]; then dir="$(ENGINE_FULL_DIR)/src/$$pkg"; else dir="$(ENGINE_FULL_DIR)/src/$$pkg/$$d"; fi; \
			mkdir -p "$$dir"; \
			depth=$$(printf '%s' "$$dir" | tr -cd '/' | wc -c | tr -d ' '); \
			up=$$(printf '../%.0s' $$(seq 0 "$$depth")); \
			ln -sfn "$$up$$pkg/src/$$f" "$$dir/$$(basename "$$f")"; \
		done; \
	done; \
	find $(ENGINE_FULL_DIR)/src -type l | awk 'END { print "[sync-engine-full] " NR " source symlink(s)" }'
	cd $(ENGINE_FULL_DIR) && $(FLIX) build-pkg
	@for dir in examples/*/ templates/*/; do \
		toml="$$dir/flix.toml"; \
		if [ -f "$$toml" ] && grep -q 'ababup1192/flix_game_engine"' "$$toml"; then \
			target="$${dir}$(ENGINE_FULL_SUBPATH)"; \
			mkdir -p "$$target"; \
			depth=$$(printf '%s' "$$dir" | tr -cd '/' | wc -c | tr -d ' '); \
			upcnt=$$((depth + $(SUBPATH_DEPTH))); \
			rel=$$(printf '../%.0s' $$(seq 1 $$upcnt)); \
			ln -sfn "$${rel}$(ENGINE_FULL_FPKG_SRC)" "$$target/$(ENGINE_FULL_FPKG_NAME)"; \
			ln -sfn "$${rel}$(ENGINE_FULL_TOML_SRC)" "$$target/$(ENGINE_FULL_TOML_NAME)"; \
			echo "[sync-engine-full] $$target"; \
		fi \
	done

# ── リリース ──────────────────────────────────────────────
# 自己完結の全部入り engine_full を build-pkg し、既存リポ flix_game_engine の GitHub Release に
# fpkg と flix.toml を添付する。利用側は github:ababup1192/flix_game_engine の1行でこの版を引く。
# 依存ゼロなので公開はこの1リポで完結する (推移先の別リポは不要)。
# 事前に make bump で version を上げ、sync + test 緑を確認してから実行する。
release: sync test
	cd $(ENGINE_FULL_DIR) && $(FLIX) build-pkg
	gh release create v$(VERSION) --repo ababup1192/flix_game_engine --title "v$(VERSION)" --generate-notes \
	  "$(ENGINE_FULL_FPKG_SRC)#$(ENGINE_FULL_FPKG_NAME)" \
	  "$(ENGINE_FULL_TOML_SRC)#$(ENGINE_FULL_TOML_NAME)"

# ── バージョン更新 (lockstep) ─────────────────────────────
# 5パッケージの flix.toml の [package] version と、パッケージ間・examples/templates の
# 自パッケージ依存参照の version を一括で上げる。flix コンパイラ版 (flix = "...") と
# flix-random など他リポ依存は触らない。使い方: make bump FROM=0.1.0 TO=0.1.1
# sed でなく perl なのは BSD/GNU の -i の非互換を踏まないため (toml は ASCII なので byte 処理で安全)。
bump:
	@test -n "$(FROM)" && test -n "$(TO)" || { echo "usage: make bump FROM=0.1.0 TO=0.1.1"; exit 1; }
	@for f in $(ENGINE_DIR) $(RENDER_GL_DIR) $(ENGINE_WORLD_DIR) $(ENGINE_TOOLS_DIR) $(ENGINE_FULL_DIR); do \
		perl -pi -e 's/^(version\s*=\s*)"\Q$(FROM)\E"/$${1}"$(TO)"/' "$$f/flix.toml"; \
	done
	@for f in $(ENGINE_DIR)/flix.toml $(RENDER_GL_DIR)/flix.toml $(ENGINE_WORLD_DIR)/flix.toml $(ENGINE_TOOLS_DIR)/flix.toml $(ENGINE_FULL_DIR)/flix.toml examples/*/flix.toml templates/*/flix.toml; do \
		[ -f "$$f" ] && perl -pi -e 's|(ababup1192/flix_[a-z_]*"[^"]*version = )"\Q$(FROM)\E"|$${1}"$(TO)"|g' "$$f" || true; \
	done
	@perl -pi -e 's/^(VERSION := ).*/$${1}$(TO)/' Makefile
	@echo "[bump] $(FROM) -> $(TO) 完了 (flix-random と flix コンパイラ版は据え置き)。"

# ── コミュニティビルド用ルート src/ ──────────────────────
# Flix 公式の community build (flix/flix の community-build.yaml) は、このリポジトリを
# checkout してルートで `flix build` を実行するだけで、make sync の fpkg 配布は走らない。
# そこでルート src/ に全エンジンパッケージの .flix をファイル単位の symlink で並べ、
# 5 パッケージを 1 ソースツリーとしてビルドできるようにする (ルートの flix.toml が対応)。
# ディレクトリ symlink は Flix のソース走査に追従されないため、必ずファイル単位で張る。
# エンジンに .flix を追加/削除/改名したら再実行して symlink 集を更新し、コミットする。
ROOT_SRC_PKGS := $(ENGINE_DIR) $(RENDER_GL_DIR) $(ENGINE_WORLD_DIR) $(ENGINE_TOOLS_DIR)

sync-root-src:
	@for pkg in $(ROOT_SRC_PKGS); do rm -rf "src/$$pkg"; done; \
	for pkg in $(ROOT_SRC_PKGS); do \
		(cd "$$pkg/src" && find . -name '*.flix') | sed 's|^\./||' | while read -r f; do \
			d=$$(dirname "$$f"); \
			if [ "$$d" = "." ]; then dir="src/$$pkg"; else dir="src/$$pkg/$$d"; fi; \
			mkdir -p "$$dir"; \
			depth=$$(printf '%s' "$$dir" | tr -cd '/' | wc -c | tr -d ' '); \
			up=$$(printf '../%.0s' $$(seq 0 "$$depth")); \
			ln -sfn "$$up$$pkg/src/$$f" "$$dir/$$(basename "$$f")"; \
		done; \
	done; \
	find src -type l | awk 'END { print "[sync-root-src] " NR " symlink(s)" }'

# render_gl は engine（フロント契約）を実装する GL バックエンド。examples が直接依存にする。
# engine に依存するので sync チェーンでは sync-engine の後に置く（lib に engine fpkg が要る）。
sync-render-gl:
	cd $(RENDER_GL_DIR) && $(FLIX) build-pkg
	@for dir in examples/*/; do \
		toml="$$dir/flix.toml"; \
		if [ -f "$$toml" ] && grep -q 'ababup1192/flix_render_gl"' "$$toml"; then \
			target="$${dir}$(RENDER_GL_SUBPATH)"; \
			mkdir -p "$$target"; \
			depth=$$(printf '%s' "$$dir" | tr -cd '/' | wc -c | tr -d ' '); \
			upcnt=$$((depth + $(SUBPATH_DEPTH))); \
			rel=$$(printf '../%.0s' $$(seq 1 $$upcnt)); \
			ln -sfn "$${rel}$(RENDER_GL_FPKG_SRC)" "$$target/$(RENDER_GL_FPKG_NAME)"; \
			ln -sfn "$${rel}$(RENDER_GL_TOML_SRC)" "$$target/$(RENDER_GL_TOML_NAME)"; \
			echo "[sync-render-gl] $$target"; \
		fi \
	done

# engine は render_gl / engine_world / engine_tools / examples が依存している。
# 特に render_gl は engine を実装するバックエンドなので、engine fpkg を render_gl にも配る。
# fpkg / toml は cp ではなく相対 symlink で配布する (engine 再ビルドが即反映される)
sync-engine:
	cd $(ENGINE_DIR) && $(FLIX) build-pkg
	@for dir in $(RENDER_GL_DIR)/ $(ENGINE_WORLD_DIR)/ $(ENGINE_TOOLS_DIR)/ examples/*/; do \
		toml="$$dir/flix.toml"; \
		if [ -f "$$toml" ] && grep -q 'ababup1192/flix_engine_core"' "$$toml"; then \
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
		if [ -f "$$toml" ] && grep -q 'ababup1192/flix_engine_world"' "$$toml"; then \
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
		if [ -f "$$toml" ] && grep -q 'ababup1192/flix_engine_tools"' "$$toml"; then \
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
