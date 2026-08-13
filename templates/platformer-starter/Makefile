# ゲーム開発の入口。
#   make run    … ゲームを起動する（ウィンドウが開く）
#   make debug  … 保存即反映(watchFile)と F8 を有効にして起動
#   make test   … テストを実行する（記録は .test-logs/）
#   make status … 現状 1 画面（テスト記録・スナップショット・チケット・git）
#   make check  … 型検査だけ走らせる（一番速い確認）
#   make render   … ギャラリー PNG を描き出す（決定的）
#   make palette … Studio 用の色の写し(assets/px.palette.json)を作り直す
#   make shot STAGE=1 … 調整中の 1 面だけ debug/shot.png へ描き出す（スナップショットを汚さない）
#   make reference-check  … 生成した絵をリファレンス画像とバイト比較する
#   make reference-update … いまの gallery をリファレンス画像として更新する
#   make stages … 面の罠ゼロ(BFS)と流れを機械検査する
#   make checkpoints … 中間ポイント(c)を等間隔に置き直し、そのまま stages で検査する
#   make loc    … src/ + test/ の .flix 合計行数（上限 3,000 行）
#   make playtest … bot に通しで遊ばせて「走れるか・詰まらないか」を測る
#   make probe  … 面の読み込み・1 tick・タイル層の組み立てにかかる時間を測る
#
# Flix コンパイラの呼び方は OS で変える:
#   - macOS/Linux … エンジンリポの bin/flix ラッパ（nix store の flix.jar 解決と JVM フラグ
#     （-XstartOnFirstThread、test/render の headless）を面倒みる）
#   - Windows … ラッパ（bash）が無いので、JRE の java で bin/flix.jar を直接叩く
# エンジンや java の場所はマシンごとに違うので、git に入れない local.mk に書く
# （make new-game / Studio が生成する。別のマシンで clone したら 1 度だけ書き直す）:
#   ENGINE := /abs/path/to/flix_game_engine   （Studio 同梱なら …/resources/engine）
#   JAVA   := /abs/path/to/java.exe           （Windows のみ。Studio 同梱 JRE の java.exe）
# 既定の ../.. は「テンプレを engine リポの中でそのまま動かす」ための値。
-include local.mk
ENGINE ?= ../..
# $(wildcard) は空白入りパス (Studio.app 同梱の engine) を扱えないので shell の test で見る
ifeq ($(shell test -e "$(ENGINE)/bin/flix" -o -e "$(ENGINE)/bin/flix.jar" && echo ok),)
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

.PHONY: status run debug test build check render shot reference-check reference-update stages checkpoints playtest probe loc palette api hooks check-docs-sync

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

# Studio のドット絵エディタに legend の意味色キーの実色を教える写し（生成物）。
# 色を変えたら焼き直す — 忘れると編集画面だけ仮色になり、実機と配色が食い違う。
palette:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) run --entrypoint Palette.write

render: palette
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" $(FLIX) run --entrypoint SceneRender.all

shot:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" STAGE=$(STAGE) $(FLIX) run --entrypoint SceneRender.one

reference-check: render
	"$(ENGINE)/bin/reference-check.sh"

reference-update:
	"$(ENGINE)/bin/reference-update.sh"

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

# 現状 1 画面 (テスト記録・スナップショット・チケット・git)。何も実行しない。
# .claude/settings.json の SessionStart フックがセッション開始時に毎回呼ぶ。
# pack が欠けたゲーム (sync-agents を配りきらない産み方をされた物) はここで配り直す —
# AGENTS.md がセッションの入口を必ずこの target にしているため、最初の 1 回で自己修復できる。
status:
	@if [ ! -f bin/status.py ]; then \
		echo "[status] agents-pack が未配布です (bin/status.py が無い) — $(ENGINE) から配り直します"; \
		$(MAKE) -C "$(ENGINE)" sync-agents GAME="$(CURDIR)" || { echo "[status] 配布に失敗 — engine リポで make sync-agents GAME=$(CURDIR) を実行してください"; exit 1; }; \
	fi
	@$(PYTHON) bin/status.py

# engine の版に追随する (flix.toml と lib/ の fpkg 差し替え + pack 配り直し + check)。
# status の「engine 版ズレ」を見たらこれ。実体は engine 側の upgrade-game。
engine-upgrade:
	@$(MAKE) -C "$(ENGINE)" upgrade-game GAME="$(CURDIR)"

# コミット時のゲート (描き出した絵の混入・矩形だけの View・規約の配線ずれを止める)。
# .git/hooks は git 管理外なので clone ごとに 1 回この配線が要る (status が未配線を知らせる)。
hooks:
	@git config core.hooksPath bin/githooks
	@echo "[hooks] 配線しました: pre-commit = bin/githooks/pre-commit (中身は bin/precommit.py)"

# 規約の配線ずれの軽い検査 (engine 版のうちゲームで見るべき 3 点だけ)。
# pre-commit (bin/precommit.py) が .md / .flix を触ったコミットで呼ぶ。生成はしない。
check-docs-sync:
	@ok=1; \
	if ! grep -q '^@AGENTS.md' CLAUDE.md 2>/dev/null; then \
	  echo "[check-docs-sync] NG: CLAUDE.md は @AGENTS.md の 1 行にする (作り直しは engine 側の make sync-agents GAME=$(CURDIR))"; ok=0; \
	fi; \
	if ! head -n 1 AGENTS.md 2>/dev/null | grep -q 'generated by flix_game_engine agents-pack'; then \
	  echo "[check-docs-sync] NG: AGENTS.md に agents-pack の刻印がありません (手書きせず engine 側の sync-agents で作り直す)"; ok=0; \
	fi; \
	for s in $$(grep -o '\.claude/skills/[a-z][a-z0-9-]*' AGENTS.md 2>/dev/null | sed 's|.*/||' | sort -u); do \
	  if [ ! -f ".claude/skills/$$s/SKILL.md" ]; then \
	    echo "[check-docs-sync] NG: AGENTS.md が挙げるスキル $$s が .claude/skills にありません"; ok=0; \
	  fi; \
	done; \
	if [ "$$ok" = "1" ]; then echo "[check-docs-sync] OK"; else exit 1; fi
