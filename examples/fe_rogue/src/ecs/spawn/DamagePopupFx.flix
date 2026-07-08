/// DamagePopupFx — 攻撃ヒット時にユニット頭上で数字を浮かす HUD
///
/// 攻撃 / 反撃が当たった瞬間に被弾側のグリッド位置から `5` のようなダメージ量を
/// Text で出し、上方向に少し移動しながら寿命満了で消える。LogScene の文字列
/// 「P1 → 敵2 に 5ダメージ」と冗長になるが、戦場上で直感的にダメージ量を見せる
/// のが目的。
///
/// scene ノードは持たない。寿命・テキスト・色・位置すべて World の `popupFx` store が持ち
/// （`Cmd.SpawnPopupFx` で spawn・`stepWorld` が tick して期限切れ drop）、描画は
/// `RenderWorld.renderPopups` が Text **値**を組んで直描きする（tree に積まない）。
///
/// engine の Tween.tickAll に乗せない理由:
///   - Tween.tweenAlpha は Sprite 専用（engine/src/scene/Tween.flix）
///   - Text の modulate は {r,g,b} のみで alpha 成分を持たない（Color は engine_core）
///   フェード表現は省き、上方向に float させてから瞬時に消すスタイルにする。
///   寿命を 700ms 程度にすれば違和感は最小。
mod DamagePopupFx {

    /// fontManifest で登録した name。フォントアトラスはゲーム全体で共有されるため、
    /// LogUi / BattlePanelUi など他の UIと同じ "ui" を指定しないと
    /// 実行時に別アトラスを要求してクラッシュする。renderPopups が使うため pub。
    pub def fontName(): String = "ui"

    /// 1 つのポップアップの寿命（出現 → 消滅まで）
    def lifetime(): Duration.Duration = Duration.millis(700)

    /// ポップアップが寿命中に上方向へ移動する総ピクセル数（論理 px）
    pub def floatDistancePx(): Float64 = 12.0

    /// Text の表示フォントサイズ。LDTK タイル 16px に対して読める粒度。
    pub def fontSize(): Float64 = 8.0

    /// 描画 zIndex。ゲームオブジェクト（スプライト・マップ）よりも前面に重ね、
    /// ダメージ数字がユニットや地形に埋もれないようにする。
    pub def popupZIndex(): Int32 = 100

    /// プレイヤー攻撃 → 敵（被弾は敵）に使う色: 白
    pub def damageToEnemyColor(): Color = UITheme.white()

    /// 敵攻撃 → プレイヤー（被弾は味方）に使う色: 赤寄り
    pub def damageToPlayerColor(): Color = {r = 1.0f32, g = 0.4f32, b = 0.4f32}

    /// 指定ワールド座標にダメージ数字をスポーンする。色は呼び出し側で
    /// `damageToEnemyColor()` / `damageToPlayerColor()` を選ぶ。
    pub def emit(worldPos: Vec2.Vec2, damage: Int32, color: Color): Unit \ World.Command =
        emitText(worldPos, "${damage}", color)

    /// `emit` の文字列版。ダメージ数値の代わりに任意のテキスト（例: "miss"）を
    /// 同じ float-up 演出で浮かす。命中失敗時に呼び出し側が "miss" を出すのに使う。
    /// `Cmd.SpawnPopupFx` の emit のみ（ノード無し）。
    pub def emitText(worldPos: Vec2.Vec2, text: String, color: Color): Unit \ World.Command =
        World.Command.emit(World.Cmd.SpawnPopupFx(
            {total = Duration.toSeconds(lifetime()), pos = worldPos, text = text, color = color}))
}
