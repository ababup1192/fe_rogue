# fe_rogue の入口。
#   make run   … ゲームを起動する
#   make debug … デバッグ機能付きで起動する（fe_rogue は自前描画のため F8 注釈は今は効かない・将来用）
#   make test  … テストを実行する（bin/flix が headless フラグを自動で付ける）
#   make check … 型検査だけ走らせる

.PHONY: run debug test check

run:
	bin/flix run

debug:
	DEBUG=true bin/flix run

test:
	bin/flix test

check:
	bin/flix check
