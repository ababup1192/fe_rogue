# platformer の入口。
#   make run   … ゲームを起動する
#   make debug … デバッグ機能（F8 の時間停止・注釈・巻き戻し）付きで起動する
#   make bake  … ギャラリー（PNG・GIF・コマ送りサイト）と効果音 WAV を生成する
#   make test  … テストを実行する（検証のみ・生成はしない）
#   make check … 型検査だけ走らせる
#   make clean … build/ の .class を一掃する（Flix は呼び出し毎に約 7MB 書き足して
#                掃除しないため、放置すると 1 日で GB 級に膨れる。フルビルドは約 7 秒）

.PHONY: run debug bake test check clean

run:
	bin/flix run

debug:
	DEBUG=true bin/flix run

bake:
	bin/flix run --entrypoint Bake.all

test:
	bin/flix test

check:
	bin/flix check

clean:
	bin/flix clean
