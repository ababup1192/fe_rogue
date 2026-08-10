# rogue_chars の入口。
#   make bake  … スプライトシート PNG・JSON マニフェスト・ギャラリー（GIF/PNG/index.html）を生成する
#   make test  … テストを実行する（検証のみ・生成はしない）
#   make check … 型検査だけ走らせる
#   make clean … build/ の .class を一掃する（Flix は呼び出し毎に約 7MB 書き足して
#                掃除しないため、放置すると GB 級に膨れる。フルビルドは数秒）

.PHONY: bake test check clean

bake:
	bin/flix run --entrypoint Bake.all

test:
	@# 常駐 (bin/checkd) が repl を温めて持つので 2 回目からは素の CLI より数倍速い。
	@# CHECKD=0 make test で常駐を使わない素の test に戻せる。
	@if [ "$(CHECKD)" = "0" ]; then bin/flix test; else bin/checkd --test .; fi

check:
	@# 常駐 (bin/checkd) が repl を温めて持つので 2 回目からサブ秒で返る。
	@# CHECKD=0 make check で常駐を使わない素の check に戻せる。
	@if [ "$(CHECKD)" = "0" ]; then bin/flix check; else bin/checkd .; fi

clean:
	bin/flix clean
