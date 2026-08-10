.PHONY: run debug bake test check

run:
	bin/flix run

debug:
	DEBUG=true bin/flix run

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
