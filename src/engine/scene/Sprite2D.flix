/// 2D スプライトノード（Godot Sprite2D 準拠）
/// see: https://docs.godotengine.org/ja/4.x/classes/class_sprite2d.html
///
/// テクスチャを持つ最小の描画可能ノード。
/// CanvasItem（可視性・描画順）と Node2D（座標変換）を実装する。
///
///   Sprite2D
///     ├─ CanvasItem: visible, zIndex, modulate
///     └─ Node2D: position, rotation, scale, skew
///
/// テクスチャの切り出しは Godot 同様の 2 機構で表現する:
///   - region: テクスチャ内のサブ矩形（ピクセル単位）。None ならテクスチャ全体を使う。
///   - hframes / vframes / frame: region をさらに格子分割し、表示するセル index を指定。
///
/// region のみ指定すれば region_rect 切り出し、hframes/vframes/frame のみ指定すれば
/// スプライトシート分割、両方指定すれば region 内をさらに格子分割となる。
pub enum Sprite2D {
    case Sprite2D({
        position = Vec2.Vec2,           // 位置
        rotation = Float64,              // 回転（ラジアン）
        scale = Vec2.Vec2,              // スケール
        skew = Float64,                  // スキュー（ラジアン）
        visible = Bool,                  // 表示フラグ
        zIndex = Int32,                  // 描画順
        modulate = Color,                // 色変調（{r, g, b}、不透明度は alpha フィールドで指定）
        alpha = Float32,                 // 不透明度 0.0–1.0。Color にアルファが無いため別フィールド
        texture = String,                // テクスチャパス
        centered = Bool,                 // 中心を原点にするか
        offset = Vec2.Vec2,             // 描画オフセット
        flipH = Bool,                    // 水平反転
        flipV = Bool,                    // 垂直反転
        regionRect = Option[Rect2.Rect2], // テクスチャ内の切り出し矩形（ピクセル単位）。None ならテクスチャ全体
        hframes = Int32,                 // 格子分割の列数（デフォルト 1）
        vframes = Int32,                 // 格子分割の行数（デフォルト 1）
        frame = Int32                    // 表示セル index = row * hframes + col（デフォルト 0）
    })
}

mod Sprite2D {
    /// デフォルト値で Sprite2D を生成する（テクスチャ全体を表示）
    pub def make(texture: String, position: Vec2.Vec2, scale: Vec2.Vec2): Sprite2D =
        Sprite2D.Sprite2D({
            position = position,
            rotation = 0.0,
            scale = scale,
            skew = 0.0,
            visible = true,
            zIndex = 0,
            modulate = {r = 1.0f32, g = 1.0f32, b = 1.0f32},
            alpha = 1.0f32,
            texture = texture,
            centered = true,
            offset = {x = 0.0, y = 0.0},
            flipH = false,
            flipV = false,
            regionRect = None,
            hframes = 1,
            vframes = 1,
            frame = 0
        })

    /// 不透明度を設定する（0.0 = 完全透明、1.0 = 不透明）
    pub def setAlpha(alpha: Float32, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({alpha = alpha | r})

    /// テクスチャ名を変更する
    pub def setTexture(texture: String, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({texture = texture | r})

    /// 水平反転を設定する
    pub def setFlipH(h: Bool, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({flipH = h | r})

    /// 垂直反転を設定する
    pub def setFlipV(v: Bool, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({flipV = v | r})

    /// テクスチャ内の切り出し矩形を設定する。None ならテクスチャ全体を使う
    pub def setRegionRect(rect: Option[Rect2.Rect2], sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({regionRect = rect | r})

    /// 格子分割の列数を設定する（スプライトシート用）
    pub def setHframes(hframes: Int32, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({hframes = hframes | r})

    /// 格子分割の行数を設定する（スプライトシート用）
    pub def setVframes(vframes: Int32, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({vframes = vframes | r})

    /// 表示セル index を設定する。frame = row * hframes + col
    pub def setFrame(frame: Int32, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({frame = frame | r})

    /// 表示セルを (col, row) 座標で設定する。内部で frame = row * hframes + col に変換される
    pub def setFrameCoords(col: Int32, row: Int32, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({frame = row * r#hframes + col | r})

    /// regionRect / hframes / vframes / frame と元テクスチャサイズから
    /// GPU シェーダ用の uvOffset / uvScale を計算する。
    /// regionRect = None なら textureSize を atlas として使い、hframes×vframes でセル分割する。
    pub def computeUv(sprite: Sprite2D, textureSize: Vec2.Vec2):
                      {uvOffset = Vec2.Vec2, uvScale = Vec2.Vec2} =
        let Sprite2D.Sprite2D(r) = sprite;
        let atlasPx = match r#regionRect {
            case Some(rect) => rect
            case None       => Rect2.fromSize(textureSize)
        };
        let cellW = atlasPx#size#x / Int32.toFloat64(r#hframes);
        let cellH = atlasPx#size#y / Int32.toFloat64(r#vframes);
        let col = Int32.modulo(r#frame, r#hframes);
        let row = r#frame / r#hframes;
        let cellX = atlasPx#position#x + Int32.toFloat64(col) * cellW;
        let cellY = atlasPx#position#y + Int32.toFloat64(row) * cellH;
        {
            uvOffset = {x = cellX / textureSize#x, y = cellY / textureSize#y},
            uvScale  = {x = cellW / textureSize#x, y = cellH / textureSize#y}
        }
}

// ── CanvasItem 実装 ──

instance CanvasItem[Sprite2D] {
    pub def isVisible(sprite: Sprite2D): Bool =
        let Sprite2D.Sprite2D(r) = sprite;
        r#visible
    pub def setVisible(visible: Bool, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({ visible = visible | r })
    pub def getModulate(sprite: Sprite2D): Color =
        let Sprite2D.Sprite2D(r) = sprite;
        r#modulate
    pub def setModulate(color: Color, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({ modulate = color | r })
    pub def getZIndex(sprite: Sprite2D): Int32 =
        let Sprite2D.Sprite2D(r) = sprite;
        r#zIndex
    pub def setZIndex(zIndex: Int32, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({ zIndex = zIndex | r })
}

// ── Node2D 実装 ──

instance Node2D[Sprite2D] {
    pub def getPosition(sprite: Sprite2D): Vec2.Vec2 =
        let Sprite2D.Sprite2D(r) = sprite;
        r#position
    pub def setPosition(position: Vec2.Vec2, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({ position = position | r })
    pub def getRotation(sprite: Sprite2D): Float64 =
        let Sprite2D.Sprite2D(r) = sprite;
        r#rotation
    pub def setRotation(rotation: Float64, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({ rotation = rotation | r })
    pub def getScale(sprite: Sprite2D): Vec2.Vec2 =
        let Sprite2D.Sprite2D(r) = sprite;
        r#scale
    pub def setScale(scale: Vec2.Vec2, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({ scale = scale | r })
    pub def getSkew(sprite: Sprite2D): Float64 =
        let Sprite2D.Sprite2D(r) = sprite;
        r#skew
    pub def setSkew(skew: Float64, sprite: Sprite2D): Sprite2D =
        let Sprite2D.Sprite2D(r) = sprite;
        Sprite2D.Sprite2D({ skew = skew | r })
}
