// Roster — キャラの登録簿。24 枠（8 職 × 3 案）の正典で、SheetBake・Gallery・TestLint は
// 全部ここを総当たりする。キャラを 1 体足す = chars/ にモジュールを書いて、ここに 1 行足す。
//
// Phase 0 はパイロットの KnightA 1 件のみ。

mod Roster {

    /// 登録情報（描き手の関数値はタプルの相方に持つ）。
    pub type alias Entry = { classId = String, variant = String, displayName = String }

    /// 全登録: (書誌情報, 描き手)。描き手は (クリップ, コマ番号) → 32×32 Canvas の純関数。
    pub def entries(): List[(Entry, (RogueStage.Clip, Int32) -> PixelCanvas.Canvas)] =
        ({ classId = "knight", variant = "a", displayName = KnightA.name() },
         (clip, frame) -> KnightA.draw(clip, frame)) ::
        ({ classId = "knight", variant = "b", displayName = KnightB.name() },
         (clip, frame) -> KnightB.draw(clip, frame)) ::
        ({ classId = "knight", variant = "c", displayName = KnightC.name() },
         (clip, frame) -> KnightC.draw(clip, frame)) ::
        ({ classId = "barbarian", variant = "a", displayName = BarbarianA.name() },
         (clip, frame) -> BarbarianA.draw(clip, frame)) ::
        ({ classId = "barbarian", variant = "b", displayName = BarbarianB.name() },
         (clip, frame) -> BarbarianB.draw(clip, frame)) :: Nil
}
