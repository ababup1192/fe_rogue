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
	bin/flix test

check:
	bin/flix check

clean:
	bin/flix clean
