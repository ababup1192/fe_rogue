// Skeleton — 全キャラ共用の死亡表現（横たわる白骨・32×32・2 コマ）。
// キャラの Death クリップ（膝どまり）が終わった後、ゲーム側がこの絵に差し替えて
// フェードアウトさせる。誰の骨でも同じ = 「死は平等」をそのまま絵にした共通部品。
//
// 構図: 左に頭蓋（眼窩と歯が読める）、右へ背骨が伸び、肋骨のアーチ・骨盤の輪・
// 大腿骨/脛骨の長骨と続く。腕の骨は背骨の上に投げ出されている。
// 色は骨 = white・影/奥側 = paleBlue の 2 色のみ。接地は y=29。
//
//   frame 0 … 落下直後。全体が 1px 浮き、腕がまだ跳ねている
//   frame 1 … カタッと落ち着いた静止（以降この絵のまま）

mod Skeleton {
    use PixelCanvas.Canvas
    use PixelCanvas.{empty, dot, hline, vline, line, shift, overlay}

    def boneC(): Color = RoguePalette.white()
    def shadeC(): Color = RoguePalette.paleBlue()

    pub def draw(frame: Int32): Canvas =
        if (frame <= 0) floating() else settled()

    /// 落ち着いた静止形（frame 1）。
    def settled(): Canvas =
        skull()
            |> overlay(spine())
            |> overlay(ribs())
            |> overlay(armBones())
            |> overlay(pelvis())
            |> overlay(legBones())

    /// 落下直後（frame 0）: 全体 1px 浮き + 腕はさらに 1px 跳ね + 遠い脚が半歩ずれる。
    def floating(): Canvas =
        shift(0, -1, skull())
            |> overlay(shift(0, -1, spine()))
            |> overlay(shift(0, -1, ribs()))
            |> overlay(shift(0, -2, armBones()))
            |> overlay(shift(0, -1, pelvis()))
            |> overlay(shift(1, -1, legBones()))

    // ── 頭蓋（x=3..9・y=22..29）: ドーム + 眼窩の抜き + 歯列 ──

    def skull(): Canvas =
        empty()
            |> hline(5, 22, 4, boneC())                    // 頭頂のドーム
            |> hline(4, 23, 6, boneC())
            |> (cv -> dot(3, 24, boneC(), cv))             // こめかみ（眼窩 x7..8 は抜き）
            |> hline(4, 24, 3, boneC())
            |> (cv -> dot(9, 24, boneC(), cv))
            |> (cv -> dot(3, 25, boneC(), cv))
            |> hline(4, 25, 3, boneC())
            |> (cv -> dot(9, 25, boneC(), cv))
            |> (cv -> dot(3, 26, shadeC(), cv))            // 頬（下側は影色で立体に）
            |> hline(4, 26, 6, boneC())
            |> hline(4, 27, 6, boneC())
            |> (cv -> dot(5, 28, boneC(), cv))             // 歯列（白と影を交互に）
            |> (cv -> dot(6, 28, shadeC(), cv))
            |> (cv -> dot(7, 28, boneC(), cv))
            |> (cv -> dot(8, 28, shadeC(), cv))
            |> (cv -> dot(9, 28, boneC(), cv))
            |> hline(5, 29, 4, shadeC())                   // 顎の接地影

    // ── 背骨（y=27・x=10..20）+ 椎骨の影 ──

    def spine(): Canvas =
        empty()
            |> hline(10, 27, 11, boneC())
            |> (cv -> dot(11, 28, shadeC(), cv))           // 椎骨のこぶ（1 個おき）
            |> (cv -> dot(13, 28, shadeC(), cv))
            |> (cv -> dot(15, 28, shadeC(), cv))
            |> (cv -> dot(17, 28, shadeC(), cv))

    // ── 肋骨（背骨から上へ弧を描く 4 本 + 奥側のかけら）──

    def ribs(): Canvas =
        empty()
            |> vline(11, 25, 2, boneC())                   // 手前の弧: 端は低く
            |> (cv -> dot(12, 24, boneC(), cv))
            |> vline(13, 24, 3, boneC())                   // 中央 2 本は高く
            |> (cv -> dot(14, 23, boneC(), cv))
            |> vline(15, 24, 3, boneC())
            |> (cv -> dot(16, 23, boneC(), cv))
            |> vline(17, 25, 2, boneC())
            |> (cv -> dot(18, 24, boneC(), cv))
            |> (cv -> dot(12, 26, shadeC(), cv))           // 奥側の肋骨がのぞく
            |> (cv -> dot(14, 26, shadeC(), cv))
            |> (cv -> dot(16, 26, shadeC(), cv))

    // ── 腕の骨（肩から地面へ落ちた上腕 + 地面に沿う前腕 + 指のかけら）──

    def armBones(): Canvas =
        empty()
            |> line(10, 26, 13, 29, boneC())               // 上腕骨: 肩から斜めに
            |> hline(14, 29, 3, boneC())                   // 前腕骨: 地面に沿って
            |> (cv -> dot(17, 29, shadeC(), cv))           // 手のかけら
            |> (cv -> dot(18, 29, shadeC(), cv))

    // ── 骨盤（x=20..23）: 輪郭が輪に読めるよう中を抜く ──

    def pelvis(): Canvas =
        empty()
            |> hline(21, 26, 2, boneC())                   // 腸骨の上縁
            |> hline(20, 27, 4, boneC())
            |> (cv -> dot(20, 28, boneC(), cv))            // 左右の縁だけ残して輪に
            |> (cv -> dot(23, 28, boneC(), cv))
            |> (cv -> dot(21, 28, shadeC(), cv))           // 仙骨の影
            |> (cv -> dot(22, 28, shadeC(), cv))
            |> (cv -> dot(20, 29, shadeC(), cv))           // 接地影
            |> (cv -> dot(23, 29, shadeC(), cv))

    // ── 脚の骨（大腿骨 → 膝のこぶ → 脛骨。奥の脚は影色で 1 本）──

    def legBones(): Canvas =
        empty()
            |> line(24, 27, 27, 28, boneC())               // 大腿骨: 腰から膝へ斜めに
            |> (cv -> dot(28, 28, boneC(), cv))            // 膝頭のこぶ
            |> hline(28, 29, 3, boneC())                   // 脛骨: 地面に沿って
            |> (cv -> dot(30, 28, shadeC(), cv))           // 足首のこぶ
            |> line(24, 28, 26, 29, shadeC())              // 奥の脚
}
