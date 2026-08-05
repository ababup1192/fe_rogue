## Flix ゲームエンジン モノレポの workspace コマンド
##
## 構成:
##   engine/       ─ 契約層 flix_engine_core（Game/Audio effect・共有描画型・土台型・描画語彙）
##   render_gl/    ─ engine（契約層）を実装する GL バックエンド
##   engine_world/ ─ App/World/UI ランタイム。examples が利用する
##   engine_tools/ ─ ヘッドレス bake/snapshot 工具箱。examples が利用する
##   engine_full/  ─ 上4つのソースを1つに集めた自己完結の全部入り flix_game_engine（配布物）
##   editor_server/─ ui.json/hitbox.json エディタの常駐 HTTP バックエンド（make editor で起動）
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
VERSION := 0.18.0

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

# editor_server は engine / engine_world / engine_tools に依存する常駐 HTTP サーバ。
# 配布はしない (fpkg を作らない) が、sync の配布ループの受け手として lib/ を張ってもらう。
EDITOR_SERVER_DIR := editor_server

# lib/github/ababup1192/<pkg>/<version> サブパスの階層数 (= 5)。
# `$$dir` のスラッシュ数 (render_gl/ や engine_full/ なら 1、examples/<name>/ なら 2) と足して
# 全体の up 階層数を求め、symlink の相対パスを動的に組み立てる。
SUBPATH_DEPTH := 5

.PHONY: help sync sync-engine sync-render-gl sync-engine-world sync-engine-tools sync-engine-full sync-root-src clean-locks clean-example-builds test test-par bake bake-par diff release release-guard bump editor lint-palette lint-view rules check-docs-sync

help:
	@echo "Targets:"
	@echo "  make test                 全パッケージ (engine系 + examples) のテストを headless で実行"
	@echo "  make test-par             同上を並列実行 (壁時計 ≈ fe_rogue 1本分。ログは .test-logs/)"
	@echo "  make test-<name>          1 つだけテスト (例: make test-fe_rogue / make test-engine)"
	@echo "  make lint-palette         ドット絵 legend の意味色キーが Studio から解けるか検査"
	@echo "  make lint-view            View が矩形と円だけになっていないか検査"
	@echo "  make lint-images          git に入れる絵が増えすぎていないか検査"
	@echo "  make lint-sprite          ドット絵の画素の並び (浮き・階段・帯・色数) を検査"
	@echo "  make lint-anim            コマ間の飛び・体積・接地と 4 方向のそろいを検査"
	@echo "  make rules                docs/ の規約から .claude/rules/ を作り直す"
	@echo "  make bake                 bake ターゲットを持つ全 example の生成物を焼き直す"
	@echo "  make bake-par             同上を並列実行"
	@echo "  make diff DIR=<dir>       直す前(golden)と後(gallery)を左右に並べて <dir>/debug/diff/ に焼く"
	@echo "  make sync                 engine / render_gl / engine_world / engine_tools を build-pkg し、各依存先に配布"
	@echo "  make sync-render-gl       render_gl だけ build-pkg & 配布 (examples へ)"
	@echo "  make sync-engine          engine だけ build-pkg & 配布 (render_gl / engine_world / engine_tools / examples へ)"
	@echo "  make sync-engine-world      engine_world だけ build-pkg & 配布 (examples へ)"
	@echo "  make sync-engine-tools    engine_tools だけ build-pkg & 配布 (examples へ)"
	@echo "  make sync-root-src        コミュニティビルド用にルート src/ の symlink 集を再生成"
	@echo "  make clean-locks          flix check 中断で残った Maven cache の *.lock を削除"
	@echo "  make clean-example-builds examples/*/build/ を全削除 (IDE の scene.json glob 高速化用)"
	@echo "  make sync-engine-full     engine_full だけ src 集約 & build-pkg & 配布 (examples へ)"
	@echo "  make editor [DIR=<dir>]   ui.json/hitbox.json エディタのバックエンドを起動 (PORT=8787。DIR 省略時は未選択で起動)"
	@echo "  make release              sync→test-par→build-pkg→gh release を一括実行 (未コミットなら中断・tagはHEAD固定)"
	@echo "  make bump FROM=x TO=y     全 flix.toml の version を一括更新 (lockstep)。release の前に実行する"

# flix check を Ctrl-C で中断すると lib/cache/.../*.lock が残り、
# 次回 Maven リゾルバが「他プロセスが取得中」と誤認して無限待ちになる。
# ルートから `find .` すると worktree や巨大な build/ まで stat して数分固まるので、
# 走査先はパッケージ配下だけに絞り、build/ は枝ごと prune する (lock は lib/cache だけにある)。
# 消すのは -delete でなく -exec rm にする: BSD find の -delete は暗黙に -depth を立て、
# すると -prune が無効化されて GB 級の build/ を全部歩き数分固まる (元の 7 分ハングの正体)。
LOCK_DIRS := $(ENGINE_DIR) $(RENDER_GL_DIR) $(ENGINE_WORLD_DIR) $(ENGINE_TOOLS_DIR) $(ENGINE_FULL_DIR) $(EDITOR_SERVER_DIR) $(wildcard examples/*) $(wildcard templates/*) $(wildcard bench/*)
clean-locks:
	@find $(LOCK_DIRS) -type d -name build -prune -o \( -path "*/lib/cache/*" -name "*.lock" -print -exec rm -f {} + \) 2>/dev/null | awk 'END { print NR " lock(s) removed" }'

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
TEST_DIRS := $(ENGINE_DIR) $(RENDER_GL_DIR) $(ENGINE_WORLD_DIR) $(ENGINE_TOOLS_DIR) $(EDITOR_SERVER_DIR) $(wildcard examples/*)

test:
	@for dir in $(TEST_DIRS); do \
		if [ -f "$$dir/flix.toml" ]; then \
			echo "===== $$dir ====="; \
			(cd "$$dir" && "$(FLIX_TEST)" test) || exit 1; \
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
		if (cd "$$dir" && "$(FLIX_TEST)" test) > ".test-logs/$$name.log" 2>&1; then \
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

# 直した絵の「前 (golden)」と「後 (gallery)」を左右に並べて <dir>/debug/diff/ に焼く。
# bench はバイトが違うことしか言わないので、どこがどう変わったかを目で追えるようにする物。
# 焼くのは変わった絵だけ — どれが変わったかは cmp が決め、名前だけ工具へ渡す。
#
# golden の PNG は git 管理外（追跡するのは SHA256SUMS.txt だけ）なので、clone 直後は
# 「前」が手元に無い。その時は一度 make bake && make golden で今の絵を基準に置く。
diff:
	@test -n "$(DIR)" || { echo "使い方: make diff DIR=templates/rpg-starter"; exit 1; }
	@ls "$(DIR)"/golden/*.png > /dev/null 2>&1 || { \
		echo "[diff] $(DIR)/golden に比べる前の絵がありません。"; \
		echo "       golden の PNG は git 管理外です。まず make -C $(DIR) bake && make -C $(DIR) golden で基準を置いてください。"; \
		exit 1; }
	@names=$$(cd "$(DIR)" && for f in gallery/*.png; do \
		n=$$(basename "$$f"); \
		if [ ! -f "golden/$$n" ]; then echo "[diff] 比べる前がありません (新しい場面): $$n" >&2; \
		elif ! cmp -s "$$f" "golden/$$n"; then printf '%s,' "$$n"; fi; \
	done); \
	if [ -z "$$names" ]; then echo "[diff] 変わった絵はありません"; else \
		cd $(ENGINE_TOOLS_DIR) && DIFF_DIR="$(abspath $(DIR))" DIFF_NAMES="$$names" \
			JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" "$(FLIX)" run --entrypoint GoldenDiff.pairs; \
	fi

# 個別テスト: make test-fe_rogue (examples/ を先に探し、無ければルート直下のパッケージ名)
test-%:
	@if [ -d "examples/$*" ]; then \
		cd "examples/$*" && "$(FLIX_TEST)" test; \
	else \
		cd "$*" && "$(FLIX_TEST)" test; \
	fi

# ── 関所: ドット絵の意味色キー ────────────────────────────
# legend の名前が Studio から実色に解けるかを検査する (解けないと編集画面が仮色で塗り、
# 実機と配色が食い違う)。テンプレを足す・sprite Doc を触ったら通す。
lint-palette:
	@python3 bin/lint-palette.py

# ── 起動画面の素材 ────────────────────────────────────────
# 組み込みフォント (ASCII の 1bit ビットマップ) とロゴを engine/src/render/BootFontData.flix へ
# 焼き直す。fpkg は .flix しか運べないので、生成物はコミットする。
# 起動画面の文言に新しい字を足したとき・ロゴを差し替えたときだけ回す。
# PREVIEW=<dir> を付けると、焼いた結果を目視用の PNG でも書き出す。
boot-font:
	@java bin/BootFontGen.java $(if $(PREVIEW),--preview $(PREVIEW))

# フォントの焼き上がりの取り置きを捨てる (次の起動は焼き直しになる)。
# 焼き方を変えた・容量が気になる・焼き直しを確かめたいときに。
clean-font-cache:
	@rm -rf "$${FLIX_GE_CACHE_DIR:-$$HOME/.cache/flix_game_engine/font}"
	@echo "[clean-font-cache] 取り置きを捨てました"

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
	cd $(ENGINE_FULL_DIR) && "$(FLIX)" build-pkg
	@for dir in examples/*/ templates/*/ bench/*/; do \
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

# ── エディタバックエンド ──────────────────────────────────
# ui.json/hitbox.json エディタの常駐 HTTP サーバを起動する。DIR は省略可 —
# 未指定ならプロジェクト未選択で立ち上がり、エディタ画面 (POST /project) から選ぶ。
# EDITOR_WEB はビルド済みエディタ画面 (dist) の置き場所 (env で上書き可・無ければ配信無効の API 専用)。
# 例: make editor DIR=../flix_ge_shapes PORT=8787
# DIR の先頭 ~ はシェルによって展開されずに届く (make editor DIR=~/foo) ため、ここで HOME に読み替える。
# EDITOR_WEB も同様に ~ と相対パスをここで絶対化する — editor_server は editor_server/ で走るため、
# 呼び出し側基準の相対パスは黙って「dist 無し」に化ける。
EDITOR_DIR_EXPANDED = $(if $(DIR),$(abspath $(patsubst ~/%,$(HOME)/%,$(patsubst ~,$(HOME),$(DIR)))),)
EDITOR_WEB_EXPANDED = $(if $(EDITOR_WEB),$(abspath $(patsubst ~/%,$(HOME)/%,$(patsubst ~,$(HOME),$(EDITOR_WEB)))),$(abspath ../flix_ge_resource_editor/dist))

editor:
	@test -n "$(DIR)" || echo "[editor] DIR 未指定 — プロジェクト未選択で起動します (usage: make editor DIR=<game project dir> [PORT=8787])"
	@test -f "$(EDITOR_WEB_EXPANDED)/index.html" || echo "[editor] 注意: $(EDITOR_WEB_EXPANDED) に dist が無い — 画面配信なしの API 専用で起動します"
	cd $(EDITOR_SERVER_DIR) && EDITOR_DIR="$(EDITOR_DIR_EXPANDED)" EDITOR_PORT="$(if $(PORT),$(PORT),8787)" EDITOR_WEB="$(EDITOR_WEB_EXPANDED)" "$(FLIX)" run

# ── リリース ──────────────────────────────────────────────
# 自己完結の全部入り engine_full を build-pkg し、既存リポ flix_game_engine の GitHub Release に
# fpkg と flix.toml を添付する。利用側は github:ababup1192/flix_game_engine の1行でこの版を引く。
# 依存ゼロなので公開はこの1リポで完結する (推移先の別リポは不要)。
#
# 推奨フロー (この3手だけ):
#   1) make bump FROM=<旧> TO=<新>   … 全 flix.toml と VERSION を一括更新
#   2) git で変更を commit → main へ push  … リリースする版を GitHub に載せる
#   3) make release                        … sync → test-par(全量ゲート) → build-pkg → gh release
#   終了後の案内どおり、lib/ を消したコピーで外部 fetch を検証する。
#
# release は sync (clean-locks はパッケージ配下だけ walk するのでもう固まらない) と
# test-par (並列全量ゲート) を前提に組み、以下の安全策を持つ:
#   - engine ソースが未コミットだと配布 fpkg がどのコミットにも対応しなくなるため中断する。
#   - tag は現在の HEAD に固定する。push し忘れていれば gh が「commit が無い」と明示エラーにする。
# test-par に不審な挙動があれば TEST := test で逐次にフォールバックする (make release TEST=test)。
RELEASE_SHA := $(shell git rev-parse HEAD)
TEST := test-par
release-guard:
	@dirty=$$(git status --porcelain -- $(ROOT_SRC_PKGS)); \
	 if [ -n "$$dirty" ]; then \
	   echo "[release] engine ソースが未コミットです。commit してから実行してください:"; echo "$$dirty"; exit 1; \
	 fi
	@# ゲーム側 lib の flix.toml はここへの symlink なので、別プロセスの依存解決が
	@# symlink 越しに中身を空にしてしまうことがある。壊れたまま build-pkg へ進まない。
	@for f in $(ROOT_SRC_PKGS:%=%/flix.toml) $(ENGINE_FULL_DIR)/flix.toml; do \
	   grep -q '^name' "$$f" || { echo "[release] $$f が壊れています (package.name が無い)。git checkout -- $$f で復元してください"; exit 1; }; \
	 done
	@echo "[release] v$(VERSION) を $(RELEASE_SHA) で公開します"
release: release-guard sync $(TEST)
	cd $(ENGINE_FULL_DIR) && "$(FLIX)" build-pkg
	gh release create v$(VERSION) --repo ababup1192/flix_game_engine --target $(RELEASE_SHA) \
	  --title "v$(VERSION)" --generate-notes \
	  "$(ENGINE_FULL_FPKG_SRC)#$(ENGINE_FULL_FPKG_NAME)" \
	  "$(ENGINE_FULL_TOML_SRC)#$(ENGINE_FULL_TOML_NAME)"
	@echo "[release] 完了。外部 fetch 検証: lib/ を消したサンプルで github:ababup1192/flix_game_engine v$(VERSION) を引けるか確認してください"

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
	@for f in $(ENGINE_DIR)/flix.toml $(RENDER_GL_DIR)/flix.toml $(ENGINE_WORLD_DIR)/flix.toml $(ENGINE_TOOLS_DIR)/flix.toml $(ENGINE_FULL_DIR)/flix.toml $(EDITOR_SERVER_DIR)/flix.toml examples/*/flix.toml templates/*/flix.toml bench/*/flix.toml flix_ge_shapes/flix.toml; do \
		[ -f "$$f" ] && perl -pi -e 's|(ababup1192/flix_[a-z_]*"[^"]*version = )"[0-9]+\.[0-9]+\.[0-9]+"|$${1}"$(TO)"|g' "$$f" || true; \
	done
	@perl -pi -e 's/^(VERSION := ).*/$${1}$(TO)/' Makefile
	@echo "[bump] $(FROM) -> $(TO) 完了 (依存行は旧版どれでも TO へ・flix-random と flix コンパイラ版は据え置き)。"

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
	cd $(RENDER_GL_DIR) && "$(FLIX)" build-pkg
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
	cd $(ENGINE_DIR) && "$(FLIX)" build-pkg
	@for dir in $(RENDER_GL_DIR)/ $(ENGINE_WORLD_DIR)/ $(ENGINE_TOOLS_DIR)/ $(EDITOR_SERVER_DIR)/ examples/*/; do \
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
	cd $(ENGINE_WORLD_DIR) && "$(FLIX)" build-pkg
	@for dir in $(EDITOR_SERVER_DIR)/ examples/*/; do \
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
	cd $(ENGINE_TOOLS_DIR) && "$(FLIX)" build-pkg
	@for dir in $(EDITOR_SERVER_DIR)/ examples/*/; do \
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

# agents-pack をゲームに配る。共通指針 AGENTS.core.md + スキル一覧（frontmatter から
# 自動生成。Claude 以外のエージェントも AGENTS.md だけで skills に気づけるように）+
# ゲームの AGENTS.local.md を連結して game/AGENTS.md を生成し、skills を
# game/.claude/skills/ にコピーする。冪等。
.PHONY: sync-agents
sync-agents:
	@if [ -z "$(GAME)" ]; then echo "error: GAME を指定してください (make sync-agents GAME=/path/to/game)"; exit 1; fi
	@if [ ! -d "$(GAME)" ]; then echo "error: ゲームのフォルダが見つかりません: $(GAME)"; exit 1; fi
	@ver=$$(sed -n 's/^version *= *"\(.*\)"/\1/p' flix.toml | head -1); \
	{ \
	  echo "<!-- generated by flix_game_engine agents-pack (engine v$$ver). 編集しないで。共通部は engine の agents-pack/AGENTS.core.md、ゲーム固有部は AGENTS.local.md を編集して再 sync -->"; \
	  echo ""; \
	  cat agents-pack/AGENTS.core.md; \
	  echo ""; \
	  echo "## 配られているスキル一覧（sync-agents が自動生成。手で編集しない）"; \
	  echo ""; \
	  for d in agents-pack/skills/*/; do \
	    name=$$(basename $$d); \
	    desc=$$(sed -n 's/^description: *//p' "$${d}SKILL.md" | head -1 | sed 's/^"//; s/"$$//'); \
	    echo "- \`.claude/skills/$$name/SKILL.md\` — $$desc"; \
	  done; \
	  if [ -f "$(GAME)/AGENTS.local.md" ]; then echo ""; cat "$(GAME)/AGENTS.local.md"; fi; \
	} > "$(GAME)/AGENTS.md"
	@printf '@AGENTS.md\n' > "$(GAME)/CLAUDE.md"
	@mkdir -p "$(GAME)/.claude/skills"
	@for d in agents-pack/skills/*/; do \
	  name=$$(basename $$d); \
	  mkdir -p "$(GAME)/.claude/skills/$$name"; \
	  cp -f $$d* "$(GAME)/.claude/skills/$$name/"; \
	  echo "[sync-agents] skill: $$name"; \
	done
	@mkdir -p "$(GAME)/.claude/rules" "$(GAME)/bin"
	@cp -f agents-pack/rules/*.md "$(GAME)/.claude/rules/"
	@cp -f bin/lint-view.py bin/lint-palette.py bin/lint-sprite.py bin/lint-anim.py "$(GAME)/bin/"
	@echo "[sync-agents] rules: $$(ls agents-pack/rules | tr '\n' ' ')"
	@echo "[sync-agents] lint: bin/lint-view.py bin/lint-palette.py bin/lint-sprite.py bin/lint-anim.py"
	@echo "[sync-agents] wrote $(GAME)/AGENTS.md + CLAUDE.md"

# 規約の本文は docs/ に 1 つだけ置く。CLAUDE.md は AGENTS.md を import するだけ、
# .claude/rules/ は bin/gen-rules.py の生成物。手で 2 か所に書かないので、ずれない。
.PHONY: rules
rules:
	@python3 bin/gen-rules.py

# 絵の下限（矩形と円だけになっていないか）。どの OS・どのエージェントからも同じ検査。
.PHONY: lint-view
lint-view:
	@python3 bin/lint-view.py

# git に入れる絵が増えすぎていないか（焼いた絵が紛れ込んでいないか）の検査。
.PHONY: lint-images
lint-images:
	@python3 bin/lint-images.py

# ドット絵の画素の並びの検査。自己テストが壊れた lint には門番をさせない。
.PHONY: lint-sprite
lint-sprite:
	@python3 bin/lint-sprite.py --self-test >/dev/null
	@python3 bin/lint-sprite.py

.PHONY: lint-anim
lint-anim:
	@python3 bin/lint-anim.py --self-test >/dev/null
	@python3 bin/lint-anim.py

# 規約まわりの配線が崩れていないかの検査（生成はしない）。
.PHONY: check-docs-sync
check-docs-sync:
	@ok=1; \
	if [ ! -f CLAUDE.md ] || [ ! -f AGENTS.md ]; then \
	  echo "[check-docs-sync] CLAUDE.md か AGENTS.md が見つかりません"; exit 1; \
	fi; \
	echo "[check-docs-sync] CLAUDE.md が AGENTS.md を import しているか"; \
	if ! grep -q '^@AGENTS.md' CLAUDE.md; then \
	  echo "[check-docs-sync] NG: CLAUDE.md は @AGENTS.md の 1 行にしてください（本文の二重管理を避ける）"; ok=0; \
	fi; \
	echo "[check-docs-sync] .claude/rules が docs/ と一致しているか"; \
	python3 bin/gen-rules.py --check || ok=0; \
	echo "[check-docs-sync] AGENTS.md のスキル表が実在する skill を指しているか"; \
	for s in $$(grep -o '`/[a-z][a-z-]*`' AGENTS.md | tr -d '`/' | sort -u); do \
	  if [ ! -f ".claude/skills/$$s/SKILL.md" ]; then \
	    echo "[check-docs-sync] NG: AGENTS.md が /$$s を指していますが .claude/skills/$$s/SKILL.md がありません"; ok=0; \
	  fi; \
	done; \
	echo "[check-docs-sync] AGENTS.core.md のスキル参照が agents-pack/skills に実在するか"; \
	for s in $$(grep -o '`/[a-z][a-z-]*`' agents-pack/AGENTS.core.md | tr -d '`/' | sort -u) \
	         $$(grep -o '\.claude/skills/[a-z][a-z-]*' agents-pack/AGENTS.core.md | sed 's|.*/||' | sort -u); do \
	  if [ ! -f "agents-pack/skills/$$s/SKILL.md" ]; then \
	    echo "[check-docs-sync] NG: AGENTS.core.md が $$s を指していますが agents-pack/skills/$$s/SKILL.md がありません（ゲームに配られるのは agents-pack/skills だけ）"; ok=0; \
	  fi; \
	done; \
	echo "[check-docs-sync] AGENTS.core.md に skills への橋渡しがあるか"; \
	if ! grep -q 'SKILL.md' agents-pack/AGENTS.core.md; then \
	  echo "[check-docs-sync] NG: AGENTS.core.md に「.claude/skills/<名前>/SKILL.md を直接読む」案内がありません（スキル機構を持たないエージェントが skills に気づけなくなります）"; ok=0; \
	fi; \
	echo "[check-docs-sync] agents-pack/skills にコピー先のゲームで切れる相対リンクが無いか"; \
	if grep -rn '](\.\./' agents-pack/skills/; then \
	  echo "[check-docs-sync] NG: 上の相対リンクは skills フォルダの外を指していて、コピー先のゲームで切れます。「engine リポの docs/...」の文言参照にしてください"; ok=0; \
	fi; \
	echo "[check-docs-sync] skill の frontmatter に name と description があるか"; \
	for f in .claude/skills/*/SKILL.md agents-pack/skills/*/SKILL.md; do \
	  if ! grep -q '^name:' $$f; then echo "[check-docs-sync] NG: $$f に name がありません"; ok=0; fi; \
	  if ! grep -q '^description:' $$f; then echo "[check-docs-sync] NG: $$f に description がありません"; ok=0; fi; \
	done; \
	echo "[check-docs-sync] AGENTS.md から docs/ への導線があるか"; \
	for kw in \
	  "docs/audio.md" \
	  "docs/engine-module-index.md" \
	  "docs/module-index.md" \
	  "docs/drawing-floor.md" \
	  "docs/flix-conventions.md" \
	; do \
	  if ! grep -q "$$kw" AGENTS.md; then \
	    echo "[check-docs-sync] NG: AGENTS.md に $$kw への導線がありません"; ok=0; \
	  fi; \
	done; \
	echo "[check-docs-sync] templates/ に CLAUDE.md を置いていないか"; \
	for f in templates/*/CLAUDE.md; do \
	  if [ -f "$$f" ]; then \
	    echo "[check-docs-sync] NG: $$f は make new-game の sync-agents が @AGENTS.md で上書きするので、書いても捨てられます。ゲーム固有の事は AGENTS.local.md に、共通の方針は agents-pack/AGENTS.core.md に書いてください"; ok=0; \
	  fi; \
	done; \
	if [ -d .agents/skills ]; then \
	  for d in .agents/skills/*/; do \
	    n=$$(basename $$d); \
	    if [ ! -f ".claude/skills/$$n/SKILL.md" ] || ! diff -q "$$d/SKILL.md" ".claude/skills/$$n/SKILL.md" >/dev/null 2>&1; then \
	      echo "[check-docs-sync] WARN: .agents/skills/$$n が .claude/skills/ と違います（どこからも参照されていない古い写しです。消すか揃えるか決めてください）"; \
	    fi; \
	  done; \
	fi; \
	if [ "$$ok" = "1" ]; then \
	  echo "[check-docs-sync] OK"; \
	else \
	  exit 1; \
	fi

# ── 新しいゲームを 1 コマンドで産む ──────────────────────
# 使い方: make new-game GAME=/abs/path/to/dir NAME=<パッケージ名> TITLE=<題名> W=240 H=320 TEMPLATE=novel-starter
#   - GAME  … 生成先（存在しない絶対パス）。
#   - TEMPLATE … 複製元（templates/ 直下の名前。省略時は game-starter）。
#   - NAME  … Flix パッケージ名（小文字英字はじまり・[a-z0-9_]）。sprite の entityId にも使う。
#   - TITLE … 窓の題名（省略時は NAME）。
#   - W/H   … design 解像度（省略時は 480×300。窓はその 2 倍）。
# templates/game-starter を写して __NAME__/__TITLE__/__W__/__H__/__WW__/__WH__/__ENGINE__ を
# 置換し、Makefile の `ENGINE ?=` 行はエンジンの現在地で上書きする（具体値式テンプレは in-repo で
# ビルドするため実パスを持っていて、トークンにはできない）。lib/ をエンジン手元の成果物から
# 種付け（初回ダウンロード不要）、git init（commit はしない）、
# sync-agents を配ってから check → test → bake を通して「生きて産まれた」ことを証明する。
NG_TEMPLATE := $(if $(TEMPLATE),$(TEMPLATE),game-starter)
NG_W := $(if $(W),$(W),480)
NG_H := $(if $(H),$(H),300)
NG_TITLE = $(if $(TITLE),$(TITLE),$(NAME))
# 題名は自由文（アポストロフィ・空白・記号を含みうる）。シェルの '...' 囲みだと
# "Tetris's" のような ' で構文が壊れる。make の export で環境変数として直接渡し
# （execve が値をそのまま載せる・シェル再クォート無し）、recipe 側の perl は
# $ENV{NG_TITLE} で安全に読む。
export NG_TITLE
.PHONY: new-game
new-game:
	@if [ -z "$(GAME)" ]; then echo "error: GAME を指定してください (make new-game GAME=/abs/path NAME=mygame TITLE=題名 W=240 H=320)"; exit 1; fi
	@case "$(GAME)" in /*) : ;; *) echo "error: GAME は絶対パスで指定してください: $(GAME)"; exit 1;; esac
	@if [ -e "$(GAME)" ]; then echo "error: 生成先が既に存在します: $(GAME)"; exit 1; fi
	@if [ -z "$(NAME)" ]; then echo "error: NAME を指定してください（Flix パッケージ名）"; exit 1; fi
	@echo "$(NAME)" | grep -Eq '^[a-z][a-z0-9_]*$$' || { echo "error: NAME が不正です: $(NAME)（小文字英字はじまり・英小文字/数字/_ のみ）"; exit 1; }
	@echo "$(NG_W)" | grep -Eq '^[0-9]+$$' || { echo "error: W が数値ではありません: $(NG_W)"; exit 1; }
	@echo "$(NG_H)" | grep -Eq '^[0-9]+$$' || { echo "error: H が数値ではありません: $(NG_H)"; exit 1; }
	@echo "$(NG_TEMPLATE)" | grep -Eq '^[a-z][a-z0-9-]*$$' || { echo "error: TEMPLATE が不正です: $(NG_TEMPLATE)"; exit 1; }
	@if [ ! -d "templates/$(NG_TEMPLATE)" ]; then echo "error: templates/$(NG_TEMPLATE) がありません"; exit 1; fi
	@if [ -z "$(W)$(H)" ] && grep -q "__W__" "templates/$(NG_TEMPLATE)/project.json" 2>/dev/null; then echo "[new-game] W/H 未指定 — トークン式テンプレの既定 480×300 で作ります"; fi
	@if [ ! -f "$(ENGINE_FULL_FPKG_SRC)" ]; then echo "error: $(ENGINE_FULL_FPKG_SRC) がありません。先に make sync-engine-full を実行してください"; exit 1; fi
	@set -e; \
	echo "[new-game] $(GAME) を作成します (NAME=$(NAME) TITLE=$(NG_TITLE) design=$(NG_W)x$(NG_H) TEMPLATE=$(NG_TEMPLATE))"; \
	mkdir -p "$(GAME)"; \
	cp -R "templates/$(NG_TEMPLATE)/." "$(GAME)/"; \
	rm -rf "$(GAME)/lib"; \
	mkdir -p "$(GAME)/gallery" "$(GAME)/golden" "$(GAME)/debug" "$(GAME)/atelier"; \
	for f in "$(GAME)"/assets/__NAME__.*; do \
	  [ -e "$$f" ] || continue; \
	  mv "$$f" "$(GAME)/assets/$(NAME).$${f##*/__NAME__.}"; \
	done; \
	NG_NAME='$(NAME)' NG_W='$(NG_W)' NG_H='$(NG_H)' \
	NG_WW=$$(( $(NG_W) * 2 )) NG_WH=$$(( $(NG_H) * 2 )) NG_ENGINE='$(CURDIR)' \
	find "$(GAME)" -type f \( -name '*.flix' -o -name '*.json' -o -name '*.toml' -o -name '*.md' -o -name 'Makefile' \) \
	  -exec perl -pi -e 's/__NAME__/$$ENV{NG_NAME}/g; s/__TITLE__/$$ENV{NG_TITLE}/g; s/__WW__/$$ENV{NG_WW}/g; s/__WH__/$$ENV{NG_WH}/g; s/__W__/$$ENV{NG_W}/g; s/__H__/$$ENV{NG_H}/g; s/__ENGINE__/$$ENV{NG_ENGINE}/g; s/^ENGINE \?= .*$$/ENGINE ?= $$ENV{NG_ENGINE}/;' {} +; \
	mkdir -p "$(GAME)/$(ENGINE_FULL_SUBPATH)"; \
	cp "$(ENGINE_FULL_FPKG_SRC)" "$(GAME)/$(ENGINE_FULL_SUBPATH)/$(ENGINE_FULL_FPKG_NAME)"; \
	cp "$(ENGINE_FULL_TOML_SRC)" "$(GAME)/$(ENGINE_FULL_SUBPATH)/$(ENGINE_FULL_TOML_NAME)"; \
	for d in cache external; do \
	  if [ -d "lib/$$d" ]; then mkdir -p "$(GAME)/lib"; cp -R "lib/$$d" "$(GAME)/lib/$$d"; fi; \
	done; \
	echo "[new-game] lib/ を種付けしました（engine 手元に無い Maven 依存 (LWJGL natives 等) は初回ビルドで自動ダウンロードされます）"; \
	git -C "$(GAME)" init -q; \
	$(MAKE) --no-print-directory sync-agents GAME="$(GAME)"; \
	echo "[new-game] 産声の確認: check → test → bake"; \
	$(MAKE) --no-print-directory -C "$(GAME)" check ENGINE="$(CURDIR)"; \
	$(MAKE) --no-print-directory -C "$(GAME)" test ENGINE="$(CURDIR)"; \
	$(MAKE) --no-print-directory -C "$(GAME)" bake ENGINE="$(CURDIR)"; \
	echo ""; \
	echo "🎉 新しいゲームが産まれました: $(GAME)"; \
	echo "  次にやること:"; \
	echo "    cd $(GAME) && make run              … 窓を開いて遊ぶ（矢印キーで移動）"; \
	echo "    make golden                          … いまの絵を golden(基準)にする"; \
	echo "    make editor DIR=$(GAME)              … (engine 側で) Studio で開いて色や数値を調整する"; \
	echo "  git init 済み・未コミットです。最初のコミットは自分の手で。"
