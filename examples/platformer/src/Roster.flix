// Roster — 15 キャラの名簿。番号（World.charIndex 1..15）から「描き方」と「個性」を引く。
// 描き方はキャラクターラボの Char01..15（Stage → Placed 列）をそのまま本編ビューへ繋ぐ。
// 個性はパラメータへの純粋な倍率 + ガード（敵に 1 回耐える）: 各キャラ 1〜2 個だけ変えて、
// 全体のバランスは公平に保つ。番号 1（HERO）は全部 1.0 の基準 — 既存の物理 pin が全て生きる。

mod Roster {

    /// 番号 → キャラの draw（Stage → 足元中心ローカルの描画パーツ列）。範囲外は基準の 01。
    pub def drawOf(index: Int32): CharStage.Stage -> List[Render.Placed] = match index {
        case 2  => stage -> Char02.draw(stage)
        case 3  => stage -> Char03.draw(stage)
        case 4  => stage -> Char04.draw(stage)
        case 5  => stage -> Char05.draw(stage)
        case 6  => stage -> Char06.draw(stage)
        case 7  => stage -> Char07.draw(stage)
        case 8  => stage -> Char08.draw(stage)
        case 9  => stage -> Char09.draw(stage)
        case 10 => stage -> Char10.draw(stage)
        case 11 => stage -> Char11.draw(stage)
        case 12 => stage -> Char12.draw(stage)
        case 13 => stage -> Char13.draw(stage)
        case 14 => stage -> Char14.draw(stage)
        case 15 => stage -> Char15.draw(stage)
        case _  => stage -> Char01.draw(stage)
    }

    /// 番号 → 名前（HUD の右上とリモートデバッグに出す）。範囲外は基準の 01。
    pub def nameOf(index: Int32): String = match index {
        case 2  => Char02.name()
        case 3  => Char03.name()
        case 4  => Char04.name()
        case 5  => Char05.name()
        case 6  => Char06.name()
        case 7  => Char07.name()
        case 8  => Char08.name()
        case 9  => Char09.name()
        case 10 => Char10.name()
        case 11 => Char11.name()
        case 12 => Char12.name()
        case 13 => Char13.name()
        case 14 => Char14.name()
        case 15 => Char15.name()
        case _  => Char01.name()
    }

    /// キャラの巡回数。左 Shift で 1 → 2 → … → 15 → 1 と回る。
    pub def count(): Int32 = 15

    /// 次のキャラ番号（15 の次は 1 へ折り返す）。
    pub def nextIndex(index: Int32): Int32 =
        if (index >= count()) 1 else index + 1

    /// キャラ個性: パラメータへの純粋な倍率 + ガード（敵の致命接触に 1 回耐える）。
    /// 既定は全部 1.0 / guard 0。jumpMult は jumpHeight に掛かるので上昇重力（2h/t²）も
    /// 一緒に強まる — 高く飛ぶが滞空は同じ、という正しい物理になる。
    pub type alias Traits = { runMult = Float64, dashTopMult = Float64, dashAccelMult = Float64,
                              jumpMult = Float64, fallMult = Float64, maxFallMult = Float64,
                              airMult = Float64, coyoteMult = Float64, guard = Int32 }

    /// 何も変えない基準（01 HERO がこれ）。
    def neutral(): Traits =
        { runMult = 1.0, dashTopMult = 1.0, dashAccelMult = 1.0,
          jumpMult = 1.0, fallMult = 1.0, maxFallMult = 1.0,
          airMult = 1.0, coyoteMult = 1.0, guard = 0 }

    /// 番号 → 個性。各キャラの持ち味（見た目のコンセプト）に寄せて 1〜2 項目だけ変える。
    pub def traitsOf(index: Int32): Traits = match index {
        case 2  => { runMult = 1.15 | neutral() }                        // STRIDER: 大股の俊足
        case 3  => { coyoteMult = 2.0 | neutral() }                      // GECKO: 崖に強い吸い付き
        case 4  => { fallMult = 0.65, maxFallMult = 0.6 | neutral() }    // FIREFLY: ふわりと落ちる
        case 5  => { guard = 1, runMult = 0.9 | neutral() }              // GOLEM: 硬いが少し遅い
        case 6  => { jumpMult = 1.1, fallMult = 0.85 | neutral() }       // LANTERN: 軽く高く浮く
        case 7  => { airMult = 1.4 | neutral() }                         // ORBITER: 空中の舵が利く
        case 8  => { airMult = 1.2, fallMult = 0.9 | neutral() }         // TORORO: とろける空中機動
        case 9  => { dashAccelMult = 2.0 | neutral() }                   // KADORIN: P 速度が早く育つ
        case 10 => { fallMult = 0.75 | neutral() }                       // MUREBOSHI: 群れごと滞空
        case 11 => { dashTopMult = 1.145 | neutral() }                   // HIKYAKU: 最高速 280 → 約 320
        case 12 => { jumpMult = 1.2 | neutral() }                        // ODORIKO: 跳躍の華
        case 13 => { airMult = 1.5, coyoteMult = 1.5 | neutral() }       // TRACEUR: 壁と崖の職人
        case 14 => { guard = 1, jumpMult = 0.9 | neutral() }             // SMITH: 重装だが硬い
        case 15 => { guard = 1, runMult = 0.85, coyoteMult = 2.0 | neutral() } // PEDDLER: 荷が重いが粘る
        case _  => neutral()                                             // HERO: 全部 1.0 の基準
    }

    /// 個性をパラメータへ適用する（純粋な乗算だけ）。番号 1 は全倍率 1.0 なので恒等 —
    /// 既定パラメータの物理 pin がそのまま成立する。
    pub def applyTraits(traits: Traits, p: GameParameters.Params): GameParameters.Params =
        { maxRunSpeed     = p#maxRunSpeed * traits#runMult,
          dashMult        = p#dashMult * traits#dashTopMult,
          dashAccel       = p#dashAccel * traits#dashAccelMult,
          jumpHeight      = p#jumpHeight * traits#jumpMult,
          fallGravityMult = p#fallGravityMult * traits#fallMult,
          maxFallSpeed    = p#maxFallSpeed * traits#maxFallMult,
          airAccel        = p#airAccel * traits#airMult,
          coyoteTime      = p#coyoteTime * traits#coyoteMult
        | p }
}
