/// Godot SpriteFrames リソース準拠
/// see: https://docs.godotengine.org/ja/4.x/classes/class_spriteframes.html
///
/// アニメーション集合を保持するリソース。AnimatedSprite2D が `spriteFrames`
/// フィールドで参照する。各アニメーションは独自の loop / speed (FPS) と
/// 個別フレーム（テクスチャ + 表示時間倍率）を持つ。
pub enum SpriteFrames {
    case SpriteFrames(Map[String, SpriteFrames.Animation])
}

mod SpriteFrames {

    /// 1 フレームの定義
    /// duration はそのアニメーションの基本フレーム時間 (1/speed) に対する倍率。
    /// 1.0 = 通常、2.0 = 2 倍長く表示。Godot の Frame Duration と同じ意味。
    pub type alias Frame = {
        texture = String,    // 表示するテクスチャ名
        duration = Float64   // フレーム時間倍率（デフォルト 1.0）
    }

    /// 1 アニメーションの定義
    pub type alias Animation = {
        loop = Bool,           // 終端でループするか（false なら最終フレームで停止）
        speed = Float64,       // このアニメーションの基本 FPS
        frames = List[Frame]   // 表示順のフレーム列
    }

    /// 空の SpriteFrames を生成する
    pub def empty(): SpriteFrames =
        SpriteFrames.SpriteFrames(Map.empty())

    /// アニメーションを追加する（同名なら上書き）
    pub def addAnimation(name: String, animation: Animation,
                          spriteFrames: SpriteFrames): SpriteFrames =
        let SpriteFrames.SpriteFrames(map) = spriteFrames;
        SpriteFrames.SpriteFrames(Map.insert(name, animation, map))

    /// 指定したアニメーションを取得する
    pub def getAnimation(name: String, spriteFrames: SpriteFrames): Option[Animation] =
        let SpriteFrames.SpriteFrames(map) = spriteFrames;
        Map.get(name, map)

    /// アニメーションが存在するか
    pub def hasAnimation(name: String, spriteFrames: SpriteFrames): Bool =
        let SpriteFrames.SpriteFrames(map) = spriteFrames;
        Map.memberOf(name, map)

    /// アニメーション名の一覧を返す
    pub def animationNames(spriteFrames: SpriteFrames): List[String] =
        let SpriteFrames.SpriteFrames(map) = spriteFrames;
        Map.keysOf(map) |> Set.toList

    /// 指定アニメ・フレーム index のテクスチャ名を返す（範囲外なら None）
    pub def frameTexture(name: String, frame: Int32,
                         spriteFrames: SpriteFrames): Option[String] =
        forM (
            anim <- getAnimation(name, spriteFrames);
            f    <- List.nth(frame, anim#frames)
        ) yield f#texture
}
