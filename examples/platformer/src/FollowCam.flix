// FollowCam — 横+縦スクロールのカメラ。不感帯 → 追従 → レベル端クランプ の 3 段の純関数。
// 状態は World の camX / camY の 2 本（カメラ左上の座標）。前進は Step が呼ぶ
// （Replay/テストが駆動できる）。レベルが 1 画面ぶんの寸法しか無い軸はクランプで 0 に
// 張り付く — classic の全シナリオはこれで従来とバイト一致のまま。
mod FollowCam {

    /// プレイヤーが画面中央からこの距離まで離れても、カメラは動かない（不感帯・px）。
    pub def deadzone(): Float64 = 40.0

    /// 縦の不感帯は横より広い（ジャンプのたびに画面が上下すると酔う）。
    /// 満タンジャンプの頂点 96px でも、地面ビューの下端クランプと合わせると帯の中に収まる。
    pub def deadzoneY(): Float64 = 60.0

    /// 追従の寄せ率（1 秒あたり）。大きいほどキビキビ寄る。
    pub def followK(): Float64 = 8.0

    /// 1 フレームぶんカメラを進める。プレイヤーが不感帯の外に出たぶんだけ、寄せ率で追う。
    /// 追従の数式は engine_world の CameraRig.followDelta（昇格済み）。画面中心の計算と
    /// レベル端クランプはゲームの座標系の知識なのでこちらが持つ。
    pub def stepCam(dt: Float64, levelW: Float64, targetX: Float64, camX: Float64): Float64 =
        let center = camX + Field.designW() / 2.0;
        clampCam(levelW, camX + CameraRig.followDelta({ deadzone = deadzone(), k = followK() }, dt, targetX, center))

    /// 即座に対象を中央へ（死亡リスポーン・開始時）。
    pub def snapCam(levelW: Float64, targetX: Float64): Float64 =
        clampCam(levelW, targetX - Field.designW() / 2.0)

    /// カメラ左端をレベルの内側に収める。レベルが 1 画面ぶんしか無ければ常に 0。
    def clampCam(levelW: Float64, x: Float64): Float64 =
        CameraRig.clampAxis(0.0, Float64.max(0.0, levelW - Field.designW()), x)

    /// 1 フレームぶんカメラを縦に進める。横と同じ 3 段（不感帯 → 寄せ率 → クランプ）で、
    /// 不感帯だけ広い（deadzoneY）。
    pub def stepCamY(dt: Float64, levelH: Float64, targetY: Float64, camY: Float64): Float64 =
        let center = camY + Field.designH() / 2.0;
        clampCamY(levelH, camY + CameraRig.followDelta({ deadzone = deadzoneY(), k = followK() }, dt, targetY, center))

    /// 縦の即スナップ（死亡リスポーン・開始時）。
    pub def snapCamY(levelH: Float64, targetY: Float64): Float64 =
        clampCamY(levelH, targetY - Field.designH() / 2.0)

    /// カメラ上端をレベルの内側に収める。レベルが 1 画面ぶんの高さなら常に 0。
    def clampCamY(levelH: Float64, y: Float64): Float64 =
        CameraRig.clampAxis(0.0, Float64.max(0.0, levelH - Field.designH()), y)
}
