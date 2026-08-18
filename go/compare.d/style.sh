# lint-style の突き合わせ。go/compare.sh から読まれる (単体では走らない)。
# 絵は git に入っている物だけを使う (生成物は機械によって在る無いが変わる)。
STYLE_PNG=templates/rpg-starter/reference/title.png
STYLE_PNG2=templates/tetris-starter/reference/title.png

run_gate style bin/lint-style.py -- style
run_gate style-strict bin/lint-style.py --strict -- style --strict
run_gate style-badopt bin/lint-style.py --nope -- style --nope
run_gate style-badhand bin/lint-style.py --hand pixel $STYLE_PNG -- style --hand pixel $STYLE_PNG
run_gate style-badunit bin/lint-style.py --unit two $STYLE_PNG -- style --unit two $STYLE_PNG
run_gate style-missing bin/lint-style.py debug/no-such-file.png -- style debug/no-such-file.png
run_gate style-notpng bin/lint-style.py bin/lint-style.py -- style bin/lint-style.py
run_gate style-guess bin/lint-style.py $STYLE_PNG -- style $STYLE_PNG
run_gate style-guess-strict bin/lint-style.py --strict $STYLE_PNG -- style --strict $STYLE_PNG
run_gate style-coarse bin/lint-style.py --hand coarse $STYLE_PNG -- style --hand coarse $STYLE_PNG
run_gate style-fine bin/lint-style.py --hand fine $STYLE_PNG -- style --hand fine $STYLE_PNG
run_gate style-smooth bin/lint-style.py --hand smooth $STYLE_PNG -- style --hand smooth $STYLE_PNG
run_gate style-unit2 bin/lint-style.py --hand fine --unit 2 $STYLE_PNG -- style --hand fine --unit 2 $STYLE_PNG
run_gate style-unit1 bin/lint-style.py --hand coarse --unit 1 $STYLE_PNG -- style --hand coarse --unit 1 $STYLE_PNG
run_gate style-regions bin/lint-style.py --regions --hand coarse $STYLE_PNG -- style --regions --hand coarse $STYLE_PNG
run_gate style-many bin/lint-style.py --hand fine $STYLE_PNG $STYLE_PNG2 -- style --hand fine $STYLE_PNG $STYLE_PNG2
run_gate style-compare bin/lint-style.py --compare $STYLE_PNG $STYLE_PNG2 -- style --compare $STYLE_PNG $STYLE_PNG2
run_gate style-compare-one bin/lint-style.py --compare $STYLE_PNG -- style --compare $STYLE_PNG

run_gate_split style bin/lint-style.py -- style
run_gate_split style-coarse bin/lint-style.py --hand coarse $STYLE_PNG -- style --hand coarse $STYLE_PNG
run_gate_split style-smooth bin/lint-style.py --hand smooth $STYLE_PNG -- style --hand smooth $STYLE_PNG
run_gate_split style-compare bin/lint-style.py --compare $STYLE_PNG $STYLE_PNG2 -- style --compare $STYLE_PNG $STYLE_PNG2

run_fixtures_go style lint-style.py
