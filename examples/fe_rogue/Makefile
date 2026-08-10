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
	@# 常駐 (bin/checkd) が repl を温めて持つので 2 回目からは素の CLI より数倍速い。
	@# CHECKD=0 make test で常駐を使わない素の test に戻せる。
	@if [ "$(CHECKD)" = "0" ]; then bin/flix test; else bin/checkd --test .; fi

check:
	@# 常駐 (bin/checkd) が repl を温めて持つので 2 回目からサブ秒で返る。
	@# CHECKD=0 make check で常駐を使わない素の check に戻せる。
	@if [ "$(CHECKD)" = "0" ]; then bin/flix check; else bin/checkd .; fi
