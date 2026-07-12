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
         (clip, frame) -> BarbarianB.draw(clip, frame)) ::
        ({ classId = "barbarian", variant = "c", displayName = BarbarianC.name() },
         (clip, frame) -> BarbarianC.draw(clip, frame)) ::
        ({ classId = "fighter", variant = "a", displayName = FighterA.name() },
         (clip, frame) -> FighterA.draw(clip, frame)) ::
        ({ classId = "fighter", variant = "b", displayName = FighterB.name() },
         (clip, frame) -> FighterB.draw(clip, frame)) ::
        ({ classId = "fighter", variant = "c", displayName = FighterC.name() },
         (clip, frame) -> FighterC.draw(clip, frame)) ::
        ({ classId = "ranger", variant = "a", displayName = RangerA.name() },
         (clip, frame) -> RangerA.draw(clip, frame)) ::
        ({ classId = "ranger", variant = "b", displayName = RangerB.name() },
         (clip, frame) -> RangerB.draw(clip, frame)) ::
        ({ classId = "ranger", variant = "c", displayName = RangerC.name() },
         (clip, frame) -> RangerC.draw(clip, frame)) ::
        ({ classId = "rogue", variant = "a", displayName = RogueA.name() },
         (clip, frame) -> RogueA.draw(clip, frame)) ::
        ({ classId = "rogue", variant = "b", displayName = RogueB.name() },
         (clip, frame) -> RogueB.draw(clip, frame)) ::
        ({ classId = "rogue", variant = "c", displayName = RogueC.name() },
         (clip, frame) -> RogueC.draw(clip, frame)) :: Nil
}
