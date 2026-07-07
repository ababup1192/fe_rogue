// Levels — 面のデザイン: 文字の盤面（1 行 = 格子の 1 行、1 文字 = 1 セル）と、その読み方。
// 新しい面を足すときはこのファイルだけ触る: rows に盤を 1 枚足し、count を 1 増やす。
//   .  空          n  通常ブロック（1発 = 耐久 {1,1}）
//   h  ハード（2発 = 耐久 {2,2}）   #  壊れないブロック（耐久 Store に載せない）
// 難度曲線: 1面=導入のピラミッド / 2面=不壊の帯に 2 本のスリット / 3面=ポケット完備。
// 3面は中央が縦にまるごと通路: 撃ち込んだボールは天井まで駆け上がり、天井と不壊の帯の
// 間のポケットで横に流れながら、上段のブロックを上から壊し続ける。
// 文字の意味づけ（耐久への写像・id の採番・セルの画面座標）は盤の組み立て側（Field）が行う。

mod Levels {

    /// 盤面の 1 セル: 何列目・何行目に、どの文字が書かれているか。
    pub type alias Cell = { col = Int32, row = Int32, glyph = Char }

    pub def count(): Int32 = 3

    def rows(n: Int32): List[String] = match n {
        case 1 =>
            "........." ::
            ".nnnnnnn." ::
            ".nnnnnnn." ::
            "..nnnnn.." ::
            "...nnn..." :: Nil
        case 2 =>
            ".nnnnnnn." ::
            ".hhhhhhh." ::
            "##.###.##" ::
            "........." ::
            ".nn.n.nn." :: Nil
        case 3 =>
            "nnnn.nnnn" ::
            "nnnn.nnnn" ::
            "####.####" ::
            "........." ::
            "hhh...hhh" ::
            ".nn...nn." :: Nil
        // count を増やしたのに盤面を足し忘れたら、静かに他の面を使い回さず大声で落ちる。
        case _ => bug!("Levels.rows: 面 ${n} の盤面が未定義（count と rows は同時に増やす）")
    }

    /// レベル n の盤面をセルの列へ開く。'.' は空なので現れない。
    pub def cells(n: Int32): List[Cell] =
        List.zipWithIndex(rows(n)) |> List.flatMap(rowPair -> {
            let (row, text) = rowPair;
            List.zipWithIndex(String.toList(text)) |> List.filterMap(colPair -> {
                let (col, ch) = colPair;
                if (ch == '.') None else Some({ col = col, row = row, glyph = ch })
            })
        })
}
