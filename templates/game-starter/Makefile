# ゲーム開発の入口。
#   make run   … ゲームを起動する（窓が開く）
#   make test  … テストを実行する
#   make build … 実行できる形にビルドする
#   make check … 型検査だけ走らせる（一番速い確認）
#
# macOS の GLFW はメインスレッド起動を要求するが、それは GameEngine.ensureMainThread() が
# -XstartOnFirstThread 付きで自分を再起動して満たす。だから run に特別なフラグは要らない。
# （-XstartOnFirstThread は java の起動引数専用で、JAVA_TOOL_OPTIONS 経由では
#  「Unrecognized option」で落ちる。だからここでは環境変数に入れず、素の flix を呼ぶ）

.PHONY: run test build check

run:
	flix run

test:
	JAVA_TOOL_OPTIONS="-Djava.awt.headless=true" flix test

build:
	flix build

check:
	flix check
