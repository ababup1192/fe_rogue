# sprite_stress の入口。
#   make run   … ベンチを起動する（4 区間を走り切って自動終了・統計は stdout）
#   make check … 型検査だけ走らせる

.PHONY: run check bake-atlas run-px

run:
	../../bin/flix run

check:
	../../bin/flix check

# R2b: PxSprite box 列 vs 1 クアッドの A/B (BenchPx)
bake-atlas:
	../../bin/flix run --entrypoint BenchPx.bakeAtlas

run-px: bake-atlas
	../../bin/flix run --entrypoint BenchPx.bench
