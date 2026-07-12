// トロロ — 全身が液体のアメーバ生命体。決まった骨格を持たず、7 枚の水平スライスの
// 山が波打ちながら「体らしき形」を保つ。跳べば雫に伸び、落ちれば傘に開き、
// 急停止では飛沫を撒いて潰れ、着地でべしゃりと広がってから盛り上がって戻る。
// ダッシュの合図は体色でなく、路面に残る「濡れた轍」で示す。

mod Char08 {

    // ── 色（DB32・体色は全モードで不変）──

    def bodyGel(): Color = {r = 0.600000f32, g = 0.898039f32, b = 0.313725f32}   // #99e550
    def wetBase(): Color = {r = 0.415686f32, g = 0.745098f32, b = 0.188235f32}   // #6abe30
    def eyeInk(): Color  = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32}   // #222034
    def gelGlint(): Color = {r = 1.000000f32, g = 1.000000f32, b = 1.000000f32}  // #ffffff

    /// キャラ選択ギャラリーに出す ASCII ラベル。
    pub def name(): String = "08 TORORO"

    /// 体のシルエットをひとまとめにした変形パラメータ。スライス積層はこれだけで形が決まる。
    /// wFac/hFac = 横縦の伸縮 / taper = 上すぼまりの強さ（大=雫・小=傘）/
    /// lean = 上ほど大きく前へ流れるずれ / wobAmp = 表面のうねり振幅 / wavePhase = うねりの位相。
    type alias Pose = {
        wFac = Float64,
        hFac = Float64,
        taper = Float64,
        lean = Float64,
        wobAmp = Float64,
        wavePhase = Float64
    }

    /// 舞台状態から 1 コマ分の描画リストを組む（モードごとに変形と付随エフェクトを選ぶ）。
    pub def draw(stage: CharStage.Stage): List[Render.Placed] =
        match stage#mode {
            case CharStage.Mode.IdleMode => body(stage, idlePose(stage))
            case CharStage.Mode.RunMode  => body(stage, runPose(stage))
            case CharStage.Mode.DashMode => List.append(dashWake(stage), body(stage, dashPose(stage)))
            case CharStage.Mode.SkidMode => List.append(body(stage, skidPose(stage)), skidSplash(stage))
            case CharStage.Mode.JumpMode => List.append(body(stage, jumpPose(stage)), riseBeads(stage))
            case CharStage.Mode.FallMode => List.append(body(stage, fallPose(stage)), fallBeads(stage))
            case CharStage.Mode.LandMode => List.append(body(stage, landPose(stage)), landSplash(stage))
        }

    // ── モードごとの変形 ──

    /// 待機: ゆっくり呼吸するゼリー。縦に膨らむとき横は締まる（体積が保たれて見える）。
    def idlePose(stage: CharStage.Stage): Pose =
        let breathe = Curve.triWave(stage#modeT * 0.77);
        { wFac = 1.0 - 0.05 * breathe, hFac = 1.0 + 0.06 * breathe, taper = 1.0,
          lean = 0.0, wobAmp = 0.7, wavePhase = stage#t * 0.6 }

    /// 走り: 進んだ距離で表面波が体を伝い、上半身が進行方向へ流れる（足のない「這い」）。
    def runPose(stage: CharStage.Stage): Pose =
        let speed = Float64.min(1.0, Float64.abs(stage#vx) / 160.0);
        { wFac = 1.0, hFac = 1.0 + 0.05 * Curve.triWave(stage#pos#x * 0.1), taper = 1.0,
          lean = stage#facing * 5.0 * speed, wobAmp = 1.3, wavePhase = stage#pos#x * 0.05 }

    /// ダッシュ: 走りと同じ論理のまま、うねりと前傾だけを深くする（色は変えない）。
    def dashPose(stage: CharStage.Stage): Pose =
        let band = dashBand(stage);
        { wFac = 1.0, hFac = 1.0 + 0.06 * Curve.triWave(stage#pos#x * 0.14), taper = 1.0,
          lean = stage#facing * (5.0 + 4.0 * band), wobAmp = 1.3 + 0.9 * band,
          wavePhase = stage#pos#x * 0.08 }

    /// スキッド: 進行方向へ大きく潰れて横滑りする「にゅるり」。強さは残速度で決まる。
    def skidPose(stage: CharStage.Stage): Pose =
        let grip = Float64.min(1.0, Float64.abs(stage#vx) / 280.0);
        { wFac = 1.0 + 0.75 * grip, hFac = 1.0 - 0.4 * grip, taper = 1.0,
          lean = stage#facing * 11.0 * grip, wobAmp = 1.5, wavePhase = stage#t * 2.0 }

    /// 上昇: 上すぼまりの雫へ絞られる（taper を上げて先端を尖らせる）。
    def jumpPose(stage: CharStage.Stage): Pose =
        let e = Float64.min(1.0, stage#modeT * 4.0);
        { wFac = 1.0 - 0.22 * e, hFac = 1.0 + 0.4 * e, taper = 1.0 + 0.6 * e,
          lean = 0.0, wobAmp = 0.5, wavePhase = stage#t * 1.5 }

    /// 落下: 上が開いた傘形に広がって空気を受ける（taper を下げると天面が太る）。
    def fallPose(stage: CharStage.Stage): Pose =
        let e = Float64.min(1.0, stage#modeT * 4.0);
        { wFac = 1.0 + 0.25 * e, hFac = 1.0 - 0.2 * e, taper = 1.0 - 0.45 * e,
          lean = 0.0, wobAmp = 0.8, wavePhase = stage#t * 1.5 }

    /// 着地: べしゃりと水たまりに広がり、窓の終わりへ向けて盛り上がって元の山へ戻る。
    def landPose(stage: CharStage.Stage): Pose =
        let recover = stage#modeT / 0.2;
        let squash = 1.0 - recover;
        { wFac = 1.0 + 0.8 * squash, hFac = 1.0 - 0.55 * squash, taper = 1.0,
          lean = 0.0, wobAmp = 2.5 * squash, wavePhase = stage#t * 3.0 }

    // ── 体の描画（スライス積層 + 目 + 照り）──

    /// 変形パラメータから体一式（スライス 7 枚・照り・目）を組む。
    def body(stage: CharStage.Stage, pose: Pose): List[Render.Placed] =
        List.flatten(List#{
            List.range(0, 7) |> List.map(i -> slice(stage, pose, i)),
            shine(stage, pose),
            eyes(stage, pose)
        })

    /// i 枚目（0=底）の水平スライス。円弧のプロフィールで山なりの幅にし、
    /// 表面波と前傾ずれを足すと「輪郭が流れる液体」に見える。
    def slice(stage: CharStage.Stage, pose: Pose, i: Int32): Render.Placed =
        let fi = Int32.toFloat64(i);
        let u = (fi + 0.5) / 7.0;
        let halfW = 11.0 * Vec2.sqrt(Float64.max(0.03, 1.0 - u * u * pose#taper)) * pose#wFac;
        let cx = stage#pos#x
               + pose#lean * u * u
               + pose#wobAmp * Curve.triWave(pose#wavePhase + u * 0.9);
        let h = 3.0 * pose#hFac + 0.8;
        let topY = stage#pos#y - (fi + 1.0) * 3.0 * pose#hFac - 0.4;
        let tone = if (i == 0) wetBase() else bodyGel();
        ({x = cx - halfW, y = topY},
         Render.box({x = halfW * 2.0, y = h}, tone, 10) |> Render.rounded(Float64.min(h * 0.5, halfW)))

    /// ゲル表面の照り（後頭部側の白い点）。変形に追従して上下する。
    def shine(stage: CharStage.Stage, pose: Pose): List[Render.Placed] =
        let gx = stage#pos#x - stage#facing * 4.0 + pose#lean * 0.3;
        let gy = stage#pos#y - 16.0 * pose#hFac;
        List#{({x = gx - 1.7, y = gy - 1.7}, Render.circle(1.7, gelGlint(), 11) |> Render.fade(0.5f32))}

    /// ゲルに浮かぶ 2 つの目。体の変形（hFac・lean・うねり）にわずかに遅れて漂う。
    def eyes(stage: CharStage.Stage, pose: Pose): List[Render.Placed] =
        let ey = stage#pos#y - 13.0 * pose#hFac + 0.4 * Curve.triWave(pose#wavePhase);
        let frontX = stage#pos#x + stage#facing * 5.2 + pose#lean * 0.6;
        let backX = stage#pos#x + stage#facing * 1.4 + pose#lean * 0.6;
        List#{
            ({x = backX - 1.3, y = ey - 1.3}, Render.circle(1.3, eyeInk(), 12)),
            ({x = frontX - 1.3, y = ey - 1.3}, Render.circle(1.3, eyeInk(), 12))
        }

    // ── モード付随のエフェクト ──

    /// ダッシュ強度 0..1（見かけ速度 160→280 を正規化）。
    def dashBand(stage: CharStage.Stage): Float64 =
        Float64.min(1.0, Float64.max(0.0, (Float64.abs(stage#vx) - 160.0) / 120.0))

    /// ダッシュの「濡れた轍」: 通った路面に残る、後ろほど細い水たまり 3 枚。
    def dashWake(stage: CharStage.Stage): List[Render.Placed] =
        let band = dashBand(stage);
        if (band < 0.05) Nil
        else
            List.range(0, 3) |> List.map(j ->
                let fj = Int32.toFloat64(j);
                let w = (11.0 - fj * 3.0) * band;
                let px = stage#pos#x - stage#facing * (13.0 + fj * 10.0);
                ({x = px - w * 0.5, y = -2.2},
                 Render.box({x = w, y = 2.2}, wetBase(), 8)
                     |> Render.rounded(1.1)
                     |> Render.fade(RenderUtil.f32((0.55 - fj * 0.15) * band))))

    /// スキッドの飛沫: 前方へ弧を描いて飛ぶしずく 4 粒。残速度が強いほど濃い。
    def skidSplash(stage: CharStage.Stage): List[Render.Placed] =
        let grip = Float64.min(1.0, Float64.abs(stage#vx) / 280.0);
        let tt = stage#modeT;
        List.range(0, 4) |> List.map(d ->
            let fd = Int32.toFloat64(d);
            let dx = stage#facing * (16.0 + 6.0 * fd) * tt;
            let dy = -8.0 - (30.0 + 8.0 * fd) * tt + 160.0 * tt * tt;
            let r = 1.7 - 0.25 * fd;
            ({x = stage#pos#x + dx - r, y = stage#pos#y + dy - r},
             Render.circle(r, bodyGel(), 12)
                 |> Render.fade(RenderUtil.f32(Float64.max(0.0, (0.9 - tt * 2.2) * (0.4 + 0.6 * grip))))))

    /// 上昇中に足元へ残す雫の尾（高度が出てから現れる）。
    def riseBeads(stage: CharStage.Stage): List[Render.Placed] =
        let e = Float64.min(1.0, stage#modeT * 4.0);
        let high = Float64.min(1.0, Float64.max(0.0, (0.0 - stage#pos#y - 8.0) / 12.0));
        List#{
            ({x = stage#pos#x - 1.4, y = stage#pos#y + 7.0 - 1.4},
             Render.circle(1.4, bodyGel(), 9) |> Render.fade(RenderUtil.f32(0.6 * e * high))),
            ({x = stage#pos#x - 0.9, y = stage#pos#y + 13.0 - 0.9},
             Render.circle(0.9, bodyGel(), 9) |> Render.fade(RenderUtil.f32(0.3 * e * high)))
        }

    /// 落下中に頭上へ置いていく雫（相対的に上へ「こぼれる」）。着地前に消える。
    def fallBeads(stage: CharStage.Stage): List[Render.Placed] =
        let high = Float64.min(1.0, Float64.max(0.0, (0.0 - stage#pos#y - 6.0) / 10.0));
        List#{
            ({x = stage#pos#x - stage#facing * 2.0 - 1.2, y = stage#pos#y - 23.0 - 1.2},
             Render.circle(1.2, bodyGel(), 9) |> Render.fade(RenderUtil.f32(0.45 * high))),
            ({x = stage#pos#x - stage#facing * 3.5 - 0.8, y = stage#pos#y - 28.0 - 0.8},
             Render.circle(0.8, bodyGel(), 9) |> Render.fade(RenderUtil.f32(0.25 * high)))
        }

    /// 着地の飛沫: 左右へ低く跳ねるしずく。窓の後半で薄れて消える。
    def landSplash(stage: CharStage.Stage): List[Render.Placed] =
        let recover = stage#modeT / 0.2;
        List#{-1.0, 1.0} |> List.map(side ->
            let dx = side * (7.0 + 16.0 * stage#modeT);
            let dy = -3.5 - 9.0 * Vec2.sin(recover * 3.14159265);
            ({x = stage#pos#x + dx - 1.6, y = dy - 1.6},
             Render.circle(1.6, bodyGel(), 12)
                 |> Render.fade(RenderUtil.f32(Float64.max(0.0, 0.8 * (1.0 - recover))))))
}
