# breakout の入口。
#   make run   … ゲームを起動する
#   make debug … デバッグ機能（F8 の時間停止・注釈・巻き戻し）付きで起動する
#   make bake  … ギャラリー（PNG・GIF・コマ送りサイト）と効果音 WAV を生成する
#   make test  … テストを実行する（検証のみ・生成はしない）
#   make check … 型検査だけ走らせる

.PHONY: run debug bake test check

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
