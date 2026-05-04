/// エンジンノード — 全ビルトインノード型を統一的に扱うための sum type
///
/// Scene[s] の各 SceneEntry は EngineNode[s]（描画・物理・衝突 + ゲーム状態）を保持する。
/// CanvasItem / Node2D / CollisionObject2D / Renderable は
/// EngineNode[s] に対して一度だけ実装され、ゲーム側のボイラープレートを排除する。
pub enum EngineNode[state] {
    /// 静的スプライト（背景・車両スプライト・丸太スプライト用）
    case Sprite2DWithState(Sprite2D, state)
    /// 衝突エリア（Area2D ベースの当たり判定）
    case Area2DWithState(Area2D, state)
    /// キャラクターボディ（プレイヤー等の物理ボディ）
    case Body2DWithState(CharacterBody2D, state)
    /// 剛体ボディ（物理エンジン駆動のボディ）
    case RigidBody2DWithState(RigidBody2D, state)
    /// アニメーション付きスプライト
    case AnimSprite2DWithState(AnimatedSprite2D, state)
    /// テキストラベル（HUD 表示）
    case Label2DWithState(Label2D, state)
    /// 位置マーカー（スポーン地点・参照点）
    case Marker2DWithState(Marker2D, state)
    /// 2D パスノード（スポーンパス等）
    case Path2DWithState(Path2D, state)
    /// 画面外通知ノード（VisibleOnScreenNotifier2D ベースの画面外検出）
    case ScreenNotifier2DWithState(VisibleOnScreenNotifier2D, state)
    /// タイマーノード（不可視・非衝突の時間カウントダウン）
    case TimerWithState(Timer, state)
    /// 色付き矩形ノード（テクスチャなしの単色矩形）
    case ColorRectWithState(ColorRect, state)
    /// GPU パーティクルエミッター（残像エフェクト）
    case GPUParticles2DWithState(GPUParticles2D, state)
    /// キャンバスレイヤー（独立した描画レイヤー）
    case CanvasLayerWithState(CanvasLayer, state)
    /// 不可視UIコンテナ
    case ControlWithState(Control, state)
    /// ボタンノード（背景矩形 + テキスト + マウス操作）
    case ButtonWithState(Button, state)
    /// テクスチャボタンノード（Godot TextureButton 準拠：state 切替で複数テクスチャ）
    case TextureButtonWithState(TextureButton, state)
    /// 2D カメラノード（ビューポート追従）
    case Camera2DWithState(Camera2D, state)
    /// 静的物理ボディ（壁・床・パイプ等の固定障害物）
    case StaticBody2DWithState(StaticBody2D, state)
}

mod EngineNode {

    /// EngineNode から state を取得する
    pub def getState(node: EngineNode[s]): s = match node {
        case EngineNode.Sprite2DWithState(_, state) => state
        case EngineNode.Area2DWithState(_, state) => state
        case EngineNode.Body2DWithState(_, state) => state
        case EngineNode.RigidBody2DWithState(_, state) => state
        case EngineNode.AnimSprite2DWithState(_, state) => state
        case EngineNode.Label2DWithState(_, state) => state
        case EngineNode.Marker2DWithState(_, state) => state
        case EngineNode.Path2DWithState(_, state) => state
        case EngineNode.ScreenNotifier2DWithState(_, state) => state
        case EngineNode.TimerWithState(_, state) => state
        case EngineNode.ColorRectWithState(_, state) => state
        case EngineNode.GPUParticles2DWithState(_, state) => state
        case EngineNode.CanvasLayerWithState(_, state) => state
        case EngineNode.ControlWithState(_, state) => state
        case EngineNode.ButtonWithState(_, state) => state
        case EngineNode.TextureButtonWithState(_, state) => state
        case EngineNode.Camera2DWithState(_, state) => state
        case EngineNode.StaticBody2DWithState(_, state) => state
    }

    /// EngineNode の state を置き換える
    pub def setState(newState: s, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.Sprite2DWithState(inner, _) => EngineNode.Sprite2DWithState(inner, newState)
        case EngineNode.Area2DWithState(inner, _) => EngineNode.Area2DWithState(inner, newState)
        case EngineNode.Body2DWithState(inner, _) => EngineNode.Body2DWithState(inner, newState)
        case EngineNode.RigidBody2DWithState(inner, _) => EngineNode.RigidBody2DWithState(inner, newState)
        case EngineNode.AnimSprite2DWithState(inner, _) => EngineNode.AnimSprite2DWithState(inner, newState)
        case EngineNode.Label2DWithState(inner, _) => EngineNode.Label2DWithState(inner, newState)
        case EngineNode.Marker2DWithState(inner, _) => EngineNode.Marker2DWithState(inner, newState)
        case EngineNode.Path2DWithState(inner, _) => EngineNode.Path2DWithState(inner, newState)
        case EngineNode.ScreenNotifier2DWithState(inner, _) => EngineNode.ScreenNotifier2DWithState(inner, newState)
        case EngineNode.TimerWithState(inner, _) => EngineNode.TimerWithState(inner, newState)
        case EngineNode.ColorRectWithState(inner, _) => EngineNode.ColorRectWithState(inner, newState)
        case EngineNode.GPUParticles2DWithState(inner, _) => EngineNode.GPUParticles2DWithState(inner, newState)
        case EngineNode.CanvasLayerWithState(inner, _) => EngineNode.CanvasLayerWithState(inner, newState)
        case EngineNode.ControlWithState(inner, _) => EngineNode.ControlWithState(inner, newState)
        case EngineNode.ButtonWithState(inner, _) => EngineNode.ButtonWithState(inner, newState)
        case EngineNode.TextureButtonWithState(inner, _) => EngineNode.TextureButtonWithState(inner, newState)
        case EngineNode.Camera2DWithState(inner, _) => EngineNode.Camera2DWithState(inner, newState)
        case EngineNode.StaticBody2DWithState(inner, _) => EngineNode.StaticBody2DWithState(inner, newState)
    }

    /// EngineNode の state に関数を適用する
    pub def mapState(f: s -> s, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.Sprite2DWithState(inner, state) => EngineNode.Sprite2DWithState(inner, f(state))
        case EngineNode.Area2DWithState(inner, state) => EngineNode.Area2DWithState(inner, f(state))
        case EngineNode.Body2DWithState(inner, state) => EngineNode.Body2DWithState(inner, f(state))
        case EngineNode.RigidBody2DWithState(inner, state) => EngineNode.RigidBody2DWithState(inner, f(state))
        case EngineNode.AnimSprite2DWithState(inner, state) => EngineNode.AnimSprite2DWithState(inner, f(state))
        case EngineNode.Label2DWithState(inner, state) => EngineNode.Label2DWithState(inner, f(state))
        case EngineNode.Marker2DWithState(inner, state) => EngineNode.Marker2DWithState(inner, f(state))
        case EngineNode.Path2DWithState(inner, state) => EngineNode.Path2DWithState(inner, f(state))
        case EngineNode.ScreenNotifier2DWithState(inner, state) => EngineNode.ScreenNotifier2DWithState(inner, f(state))
        case EngineNode.TimerWithState(inner, state) => EngineNode.TimerWithState(inner, f(state))
        case EngineNode.ColorRectWithState(inner, state) => EngineNode.ColorRectWithState(inner, f(state))
        case EngineNode.GPUParticles2DWithState(inner, state) => EngineNode.GPUParticles2DWithState(inner, f(state))
        case EngineNode.CanvasLayerWithState(inner, state) => EngineNode.CanvasLayerWithState(inner, f(state))
        case EngineNode.ControlWithState(inner, state) => EngineNode.ControlWithState(inner, f(state))
        case EngineNode.ButtonWithState(inner, state) => EngineNode.ButtonWithState(inner, f(state))
        case EngineNode.TextureButtonWithState(inner, state) => EngineNode.TextureButtonWithState(inner, f(state))
        case EngineNode.Camera2DWithState(inner, state) => EngineNode.Camera2DWithState(inner, f(state))
        case EngineNode.StaticBody2DWithState(inner, state) => EngineNode.StaticBody2DWithState(inner, f(state))
    }

    /// Timer の inner node に関数を適用する
    pub def mapTimer(f: Timer -> Timer, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.TimerWithState(inner, st) => EngineNode.TimerWithState(f(inner), st)
        case _ => node
    }

    /// Sprite2D の inner node に関数を適用する（他バリアントは変更なし）
    pub def mapSprite2D(f: Sprite2D -> Sprite2D, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.Sprite2DWithState(inner, st) => EngineNode.Sprite2DWithState(f(inner), st)
        case _ => node
    }

    /// AnimatedSprite2D の inner node に関数を適用する
    pub def mapAnimSprite2D(f: AnimatedSprite2D -> AnimatedSprite2D, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.AnimSprite2DWithState(inner, st) => EngineNode.AnimSprite2DWithState(f(inner), st)
        case _ => node
    }

    /// CharacterBody2D の inner node に関数を適用する
    pub def mapBody2D(f: CharacterBody2D -> CharacterBody2D, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.Body2DWithState(inner, st) => EngineNode.Body2DWithState(f(inner), st)
        case _ => node
    }

    /// RigidBody2D の inner node に関数を適用する
    pub def mapRigidBody2D(f: RigidBody2D -> RigidBody2D, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.RigidBody2DWithState(inner, st) => EngineNode.RigidBody2DWithState(f(inner), st)
        case _ => node
    }

    /// Area2D の inner node に関数を適用する
    pub def mapArea2D(f: Area2D -> Area2D, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.Area2DWithState(inner, st) => EngineNode.Area2DWithState(f(inner), st)
        case _ => node
    }

    /// Label2D の inner node に関数を適用する
    pub def mapLabel2D(f: Label2D -> Label2D, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.Label2DWithState(inner, st) => EngineNode.Label2DWithState(f(inner), st)
        case _ => node
    }

    /// Path2D の inner node に関数を適用する
    pub def mapPath2D(f: Path2D -> Path2D, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.Path2DWithState(inner, st) => EngineNode.Path2DWithState(f(inner), st)
        case _ => node
    }

    /// CanvasLayer の inner node に関数を適用する
    pub def mapCanvasLayer(f: CanvasLayer -> CanvasLayer, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.CanvasLayerWithState(inner, st) => EngineNode.CanvasLayerWithState(f(inner), st)
        case _ => node
    }

    /// Control の inner node に関数を適用する
    pub def mapControl(f: Control -> Control, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.ControlWithState(inner, st) => EngineNode.ControlWithState(f(inner), st)
        case _ => node
    }

    /// Button の inner node に関数を適用する
    pub def mapButton(f: Button -> Button, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.ButtonWithState(inner, st) => EngineNode.ButtonWithState(f(inner), st)
        case _ => node
    }

    /// TextureButton の inner node に関数を適用する
    pub def mapTextureButton(f: TextureButton -> TextureButton, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.TextureButtonWithState(inner, st) => EngineNode.TextureButtonWithState(f(inner), st)
        case _ => node
    }

    /// Camera2D の inner node に関数を適用する
    pub def mapCamera2D(f: Camera2D -> Camera2D, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.Camera2DWithState(inner, st) => EngineNode.Camera2DWithState(f(inner), st)
        case _ => node
    }

    /// StaticBody2D の inner node に関数を適用する
    pub def mapStaticBody2D(f: StaticBody2D -> StaticBody2D, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.StaticBody2DWithState(inner, st) => EngineNode.StaticBody2DWithState(f(inner), st)
        case _ => node
    }

    /// エンジンレベルの毎フレーム処理
    /// AnimatedSprite2D のフレーム送りを自動で行う。
    /// GPUParticles2D のパーティクル放出・加齢・除去を自動で行う。
    /// RigidBody2D は PhysicsStep が担当するため no-op。
    pub def engineProcess(delta: Float64, path: NodePath, scene: Scene[s],
                          node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.AnimSprite2DWithState(sprite, state) =>
            EngineNode.AnimSprite2DWithState(AnimatedSprite2D.advanceFrame(delta, sprite), state)
        case EngineNode.TimerWithState(timer, state) =>
            EngineNode.TimerWithState(Timer.process(delta, timer), state)
        case EngineNode.GPUParticles2DWithState(emitter, state) =>
            let globalPos = Scene.globalPositionAt(path, scene);
            EngineNode.GPUParticles2DWithState(GPUParticles2D.process(delta, globalPos, emitter), state)
        case _ => node
    }

    /// Sprite2D を Drawable に変換する
    /// centered=false（背景）の場合は scale を uvScale にしてタイリングする
    pub def spriteToDrawable(sprite: Sprite2D, globalPos: Vec2.Vec2): GameEngine.Drawable =
        let Sprite2D.Sprite2D(r) = sprite;
        let uvSc: Vec2.Vec2 = if (r#centered) {x = 1.0, y = 1.0}
                               else r#scale;
        {
            texture = r#texture,
            position = globalPos,
            scale = r#scale,
            rotation = r#rotation,
            color = r#modulate,
            alpha = 1.0f32,
            centered = r#centered,
            uvOffset = {x = 0.0, y = 0.0},
            uvScale = uvSc,
            zIndex = r#zIndex
        }

    /// AnimatedSprite2D を Drawable に変換する
    pub def animSpriteToDrawable(sprite: AnimatedSprite2D, globalPos: Vec2.Vec2): GameEngine.Drawable =
        let AnimatedSprite2D.AnimatedSprite2D(r) = sprite;
        {
            texture = AnimatedSprite2D.currentTexture(sprite),
            position = globalPos,
            scale = r#scale,
            rotation = r#rotation,
            color = r#modulate,
            alpha = 1.0f32,
            centered = r#centered,
            uvOffset = {x = 0.0, y = 0.0},
            uvScale = {x = 1.0, y = 1.0},
            zIndex = r#zIndex
        }

    /// EngineNode からフォールバック用 Drawable を組み立てる（デバッグ表示用）
    pub def fallbackDrawable(node: EngineNode[s], globalPos: Vec2.Vec2): GameEngine.Drawable =
        {
            texture = "white",
            position = globalPos,
            scale = Node2D.getScale(node),
            rotation = Node2D.getRotation(node),
            color = CanvasItem.getModulate(node),
            alpha = 1.0f32,
            centered = true,
            uvOffset = {x = 0.0, y = 0.0},
            uvScale = {x = 1.0, y = 1.0},
            zIndex = CanvasItem.getZIndex(node)
        }
}

// ── CanvasItem 実装 ──

instance CanvasItem[EngineNode[s]] {
    pub def isVisible(node: EngineNode[s]): Bool = match node {
        case EngineNode.Sprite2DWithState(sprite, _) => CanvasItem.isVisible(sprite)
        case EngineNode.Area2DWithState(area, _) => CanvasItem.isVisible(area)
        case EngineNode.Body2DWithState(body, _) => CanvasItem.isVisible(body)
        case EngineNode.RigidBody2DWithState(body, _) => CanvasItem.isVisible(body)
        case EngineNode.AnimSprite2DWithState(sprite, _) => CanvasItem.isVisible(sprite)
        case EngineNode.Label2DWithState(label, _) => CanvasItem.isVisible(label)
        case EngineNode.Marker2DWithState(marker, _) => CanvasItem.isVisible(marker)
        case EngineNode.Path2DWithState(path, _) => CanvasItem.isVisible(path)
        case EngineNode.ScreenNotifier2DWithState(_, _) => true
        case EngineNode.TimerWithState(timer, _) => CanvasItem.isVisible(timer)
        case EngineNode.ColorRectWithState(rect, _) => CanvasItem.isVisible(rect)
        case EngineNode.GPUParticles2DWithState(emitter, _) => CanvasItem.isVisible(emitter)
        case EngineNode.CanvasLayerWithState(cl, _) => CanvasItem.isVisible(cl)
        case EngineNode.ControlWithState(ctrl, _) => CanvasItem.isVisible(ctrl)
        case EngineNode.ButtonWithState(btn, _) => CanvasItem.isVisible(btn)
        case EngineNode.TextureButtonWithState(btn, _) => CanvasItem.isVisible(btn)
        case EngineNode.Camera2DWithState(cam, _) => CanvasItem.isVisible(cam)
        case EngineNode.StaticBody2DWithState(body, _) => CanvasItem.isVisible(body)
    }
    pub def setVisible(visible: Bool, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.Sprite2DWithState(sprite, st) => EngineNode.Sprite2DWithState(CanvasItem.setVisible(visible, sprite), st)
        case EngineNode.Area2DWithState(area, st) => EngineNode.Area2DWithState(CanvasItem.setVisible(visible, area), st)
        case EngineNode.Body2DWithState(body, st) => EngineNode.Body2DWithState(CanvasItem.setVisible(visible, body), st)
        case EngineNode.RigidBody2DWithState(body, st) => EngineNode.RigidBody2DWithState(CanvasItem.setVisible(visible, body), st)
        case EngineNode.AnimSprite2DWithState(sprite, st) => EngineNode.AnimSprite2DWithState(CanvasItem.setVisible(visible, sprite), st)
        case EngineNode.Label2DWithState(label, st) => EngineNode.Label2DWithState(CanvasItem.setVisible(visible, label), st)
        case EngineNode.Marker2DWithState(marker, st) => EngineNode.Marker2DWithState(CanvasItem.setVisible(visible, marker), st)
        case EngineNode.Path2DWithState(path, st) => EngineNode.Path2DWithState(CanvasItem.setVisible(visible, path), st)
        case EngineNode.ScreenNotifier2DWithState(_, _) => node
        case EngineNode.TimerWithState(timer, st) => EngineNode.TimerWithState(CanvasItem.setVisible(visible, timer), st)
        case EngineNode.ColorRectWithState(rect, st) => EngineNode.ColorRectWithState(CanvasItem.setVisible(visible, rect), st)
        case EngineNode.GPUParticles2DWithState(emitter, st) => EngineNode.GPUParticles2DWithState(CanvasItem.setVisible(visible, emitter), st)
        case EngineNode.CanvasLayerWithState(cl, st) => EngineNode.CanvasLayerWithState(CanvasItem.setVisible(visible, cl), st)
        case EngineNode.ControlWithState(ctrl, st) => EngineNode.ControlWithState(CanvasItem.setVisible(visible, ctrl), st)
        case EngineNode.ButtonWithState(btn, st) => EngineNode.ButtonWithState(CanvasItem.setVisible(visible, btn), st)
        case EngineNode.TextureButtonWithState(btn, st) => EngineNode.TextureButtonWithState(CanvasItem.setVisible(visible, btn), st)
        case EngineNode.Camera2DWithState(cam, st) => EngineNode.Camera2DWithState(CanvasItem.setVisible(visible, cam), st)
        case EngineNode.StaticBody2DWithState(body, st) => EngineNode.StaticBody2DWithState(CanvasItem.setVisible(visible, body), st)
    }
    pub def getModulate(node: EngineNode[s]): Color = match node {
        case EngineNode.Sprite2DWithState(sprite, _) => CanvasItem.getModulate(sprite)
        case EngineNode.Area2DWithState(area, _) => CanvasItem.getModulate(area)
        case EngineNode.Body2DWithState(body, _) => CanvasItem.getModulate(body)
        case EngineNode.RigidBody2DWithState(body, _) => CanvasItem.getModulate(body)
        case EngineNode.AnimSprite2DWithState(sprite, _) => CanvasItem.getModulate(sprite)
        case EngineNode.Label2DWithState(label, _) => CanvasItem.getModulate(label)
        case EngineNode.Marker2DWithState(marker, _) => CanvasItem.getModulate(marker)
        case EngineNode.Path2DWithState(path, _) => CanvasItem.getModulate(path)
        case EngineNode.ScreenNotifier2DWithState(_, _) => {r = 1.0f32, g = 1.0f32, b = 1.0f32}
        case EngineNode.TimerWithState(timer, _) => CanvasItem.getModulate(timer)
        case EngineNode.ColorRectWithState(rect, _) => CanvasItem.getModulate(rect)
        case EngineNode.GPUParticles2DWithState(emitter, _) => CanvasItem.getModulate(emitter)
        case EngineNode.CanvasLayerWithState(cl, _) => CanvasItem.getModulate(cl)
        case EngineNode.ControlWithState(ctrl, _) => CanvasItem.getModulate(ctrl)
        case EngineNode.ButtonWithState(btn, _) => CanvasItem.getModulate(btn)
        case EngineNode.TextureButtonWithState(btn, _) => CanvasItem.getModulate(btn)
        case EngineNode.Camera2DWithState(cam, _) => CanvasItem.getModulate(cam)
        case EngineNode.StaticBody2DWithState(body, _) => CanvasItem.getModulate(body)
    }
    pub def setModulate(color: Color, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.Sprite2DWithState(sprite, st) => EngineNode.Sprite2DWithState(CanvasItem.setModulate(color, sprite), st)
        case EngineNode.Area2DWithState(area, st) => EngineNode.Area2DWithState(CanvasItem.setModulate(color, area), st)
        case EngineNode.Body2DWithState(body, st) => EngineNode.Body2DWithState(CanvasItem.setModulate(color, body), st)
        case EngineNode.RigidBody2DWithState(body, st) => EngineNode.RigidBody2DWithState(CanvasItem.setModulate(color, body), st)
        case EngineNode.AnimSprite2DWithState(sprite, st) => EngineNode.AnimSprite2DWithState(CanvasItem.setModulate(color, sprite), st)
        case EngineNode.Label2DWithState(label, st) => EngineNode.Label2DWithState(CanvasItem.setModulate(color, label), st)
        case EngineNode.Marker2DWithState(marker, st) => EngineNode.Marker2DWithState(CanvasItem.setModulate(color, marker), st)
        case EngineNode.Path2DWithState(path, st) => EngineNode.Path2DWithState(CanvasItem.setModulate(color, path), st)
        case EngineNode.ScreenNotifier2DWithState(_, _) => node
        case EngineNode.TimerWithState(timer, st) => EngineNode.TimerWithState(CanvasItem.setModulate(color, timer), st)
        case EngineNode.ColorRectWithState(rect, st) => EngineNode.ColorRectWithState(CanvasItem.setModulate(color, rect), st)
        case EngineNode.GPUParticles2DWithState(emitter, st) => EngineNode.GPUParticles2DWithState(CanvasItem.setModulate(color, emitter), st)
        case EngineNode.CanvasLayerWithState(cl, st) => EngineNode.CanvasLayerWithState(CanvasItem.setModulate(color, cl), st)
        case EngineNode.ControlWithState(ctrl, st) => EngineNode.ControlWithState(CanvasItem.setModulate(color, ctrl), st)
        case EngineNode.ButtonWithState(btn, st) => EngineNode.ButtonWithState(CanvasItem.setModulate(color, btn), st)
        case EngineNode.TextureButtonWithState(btn, st) => EngineNode.TextureButtonWithState(CanvasItem.setModulate(color, btn), st)
        case EngineNode.Camera2DWithState(cam, st) => EngineNode.Camera2DWithState(CanvasItem.setModulate(color, cam), st)
        case EngineNode.StaticBody2DWithState(body, st) => EngineNode.StaticBody2DWithState(CanvasItem.setModulate(color, body), st)
    }
    pub def getZIndex(node: EngineNode[s]): Int32 = match node {
        case EngineNode.Sprite2DWithState(sprite, _) => CanvasItem.getZIndex(sprite)
        case EngineNode.Area2DWithState(area, _) => CanvasItem.getZIndex(area)
        case EngineNode.Body2DWithState(body, _) => CanvasItem.getZIndex(body)
        case EngineNode.RigidBody2DWithState(body, _) => CanvasItem.getZIndex(body)
        case EngineNode.AnimSprite2DWithState(sprite, _) => CanvasItem.getZIndex(sprite)
        case EngineNode.Label2DWithState(label, _) => CanvasItem.getZIndex(label)
        case EngineNode.Marker2DWithState(marker, _) => CanvasItem.getZIndex(marker)
        case EngineNode.Path2DWithState(path, _) => CanvasItem.getZIndex(path)
        case EngineNode.ScreenNotifier2DWithState(_, _) => 0
        case EngineNode.TimerWithState(timer, _) => CanvasItem.getZIndex(timer)
        case EngineNode.ColorRectWithState(rect, _) => CanvasItem.getZIndex(rect)
        case EngineNode.GPUParticles2DWithState(emitter, _) => CanvasItem.getZIndex(emitter)
        case EngineNode.CanvasLayerWithState(cl, _) => CanvasItem.getZIndex(cl)
        case EngineNode.ControlWithState(ctrl, _) => CanvasItem.getZIndex(ctrl)
        case EngineNode.ButtonWithState(btn, _) => CanvasItem.getZIndex(btn)
        case EngineNode.TextureButtonWithState(btn, _) => CanvasItem.getZIndex(btn)
        case EngineNode.Camera2DWithState(cam, _) => CanvasItem.getZIndex(cam)
        case EngineNode.StaticBody2DWithState(body, _) => CanvasItem.getZIndex(body)
    }
    pub def setZIndex(zIndex: Int32, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.Sprite2DWithState(sprite, st) => EngineNode.Sprite2DWithState(CanvasItem.setZIndex(zIndex, sprite), st)
        case EngineNode.Area2DWithState(area, st) => EngineNode.Area2DWithState(CanvasItem.setZIndex(zIndex, area), st)
        case EngineNode.Body2DWithState(body, st) => EngineNode.Body2DWithState(CanvasItem.setZIndex(zIndex, body), st)
        case EngineNode.RigidBody2DWithState(body, st) => EngineNode.RigidBody2DWithState(CanvasItem.setZIndex(zIndex, body), st)
        case EngineNode.AnimSprite2DWithState(sprite, st) => EngineNode.AnimSprite2DWithState(CanvasItem.setZIndex(zIndex, sprite), st)
        case EngineNode.Label2DWithState(label, st) => EngineNode.Label2DWithState(CanvasItem.setZIndex(zIndex, label), st)
        case EngineNode.Marker2DWithState(marker, st) => EngineNode.Marker2DWithState(CanvasItem.setZIndex(zIndex, marker), st)
        case EngineNode.Path2DWithState(path, st) => EngineNode.Path2DWithState(CanvasItem.setZIndex(zIndex, path), st)
        case EngineNode.ScreenNotifier2DWithState(_, _) => node
        case EngineNode.TimerWithState(timer, st) => EngineNode.TimerWithState(CanvasItem.setZIndex(zIndex, timer), st)
        case EngineNode.ColorRectWithState(rect, st) => EngineNode.ColorRectWithState(CanvasItem.setZIndex(zIndex, rect), st)
        case EngineNode.GPUParticles2DWithState(emitter, st) => EngineNode.GPUParticles2DWithState(CanvasItem.setZIndex(zIndex, emitter), st)
        case EngineNode.CanvasLayerWithState(cl, st) => EngineNode.CanvasLayerWithState(CanvasItem.setZIndex(zIndex, cl), st)
        case EngineNode.ControlWithState(ctrl, st) => EngineNode.ControlWithState(CanvasItem.setZIndex(zIndex, ctrl), st)
        case EngineNode.ButtonWithState(btn, st) => EngineNode.ButtonWithState(CanvasItem.setZIndex(zIndex, btn), st)
        case EngineNode.TextureButtonWithState(btn, st) => EngineNode.TextureButtonWithState(CanvasItem.setZIndex(zIndex, btn), st)
        case EngineNode.Camera2DWithState(cam, st) => EngineNode.Camera2DWithState(CanvasItem.setZIndex(zIndex, cam), st)
        case EngineNode.StaticBody2DWithState(body, st) => EngineNode.StaticBody2DWithState(CanvasItem.setZIndex(zIndex, body), st)
    }
}

// ── Node2D 実装 ──

instance Node2D[EngineNode[s]] {
    pub def getPosition(node: EngineNode[s]): Vec2.Vec2 = match node {
        case EngineNode.Sprite2DWithState(sprite, _) => Node2D.getPosition(sprite)
        case EngineNode.Area2DWithState(area, _) => Node2D.getPosition(area)
        case EngineNode.Body2DWithState(body, _) => Node2D.getPosition(body)
        case EngineNode.RigidBody2DWithState(body, _) => Node2D.getPosition(body)
        case EngineNode.AnimSprite2DWithState(sprite, _) => Node2D.getPosition(sprite)
        case EngineNode.Label2DWithState(label, _) => Node2D.getPosition(label)
        case EngineNode.Marker2DWithState(marker, _) => Node2D.getPosition(marker)
        case EngineNode.Path2DWithState(path, _) => Node2D.getPosition(path)
        case EngineNode.ScreenNotifier2DWithState(_, _) => Vec2.zero()
        case EngineNode.TimerWithState(timer, _) => Node2D.getPosition(timer)
        case EngineNode.ColorRectWithState(rect, _) => Node2D.getPosition(rect)
        case EngineNode.GPUParticles2DWithState(emitter, _) => Node2D.getPosition(emitter)
        case EngineNode.CanvasLayerWithState(cl, _) => Node2D.getPosition(cl)
        case EngineNode.ControlWithState(ctrl, _) => Node2D.getPosition(ctrl)
        case EngineNode.ButtonWithState(btn, _) => Node2D.getPosition(btn)
        case EngineNode.TextureButtonWithState(btn, _) => Node2D.getPosition(btn)
        case EngineNode.Camera2DWithState(cam, _) => Node2D.getPosition(cam)
        case EngineNode.StaticBody2DWithState(body, _) => Node2D.getPosition(body)
    }
    pub def setPosition(position: Vec2.Vec2, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.Sprite2DWithState(sprite, st) => EngineNode.Sprite2DWithState(Node2D.setPosition(position, sprite), st)
        case EngineNode.Area2DWithState(area, st) => EngineNode.Area2DWithState(Node2D.setPosition(position, area), st)
        case EngineNode.Body2DWithState(body, st) => EngineNode.Body2DWithState(Node2D.setPosition(position, body), st)
        case EngineNode.RigidBody2DWithState(body, st) => EngineNode.RigidBody2DWithState(Node2D.setPosition(position, body), st)
        case EngineNode.AnimSprite2DWithState(sprite, st) => EngineNode.AnimSprite2DWithState(Node2D.setPosition(position, sprite), st)
        case EngineNode.Label2DWithState(label, st) => EngineNode.Label2DWithState(Node2D.setPosition(position, label), st)
        case EngineNode.Marker2DWithState(marker, st) => EngineNode.Marker2DWithState(Node2D.setPosition(position, marker), st)
        case EngineNode.Path2DWithState(path, st) => EngineNode.Path2DWithState(Node2D.setPosition(position, path), st)
        case EngineNode.ScreenNotifier2DWithState(_, _) => node
        case EngineNode.TimerWithState(timer, st) => EngineNode.TimerWithState(Node2D.setPosition(position, timer), st)
        case EngineNode.ColorRectWithState(rect, st) => EngineNode.ColorRectWithState(Node2D.setPosition(position, rect), st)
        case EngineNode.GPUParticles2DWithState(emitter, st) => EngineNode.GPUParticles2DWithState(Node2D.setPosition(position, emitter), st)
        case EngineNode.CanvasLayerWithState(cl, st) => EngineNode.CanvasLayerWithState(Node2D.setPosition(position, cl), st)
        case EngineNode.ControlWithState(ctrl, st) => EngineNode.ControlWithState(Node2D.setPosition(position, ctrl), st)
        case EngineNode.ButtonWithState(btn, st) => EngineNode.ButtonWithState(Node2D.setPosition(position, btn), st)
        case EngineNode.TextureButtonWithState(btn, st) => EngineNode.TextureButtonWithState(Node2D.setPosition(position, btn), st)
        case EngineNode.Camera2DWithState(cam, st) => EngineNode.Camera2DWithState(Node2D.setPosition(position, cam), st)
        case EngineNode.StaticBody2DWithState(body, st) => EngineNode.StaticBody2DWithState(Node2D.setPosition(position, body), st)
    }
    pub def getRotation(node: EngineNode[s]): Float64 = match node {
        case EngineNode.Sprite2DWithState(sprite, _) => Node2D.getRotation(sprite)
        case EngineNode.Area2DWithState(area, _) => Node2D.getRotation(area)
        case EngineNode.Body2DWithState(body, _) => Node2D.getRotation(body)
        case EngineNode.RigidBody2DWithState(body, _) => Node2D.getRotation(body)
        case EngineNode.AnimSprite2DWithState(sprite, _) => Node2D.getRotation(sprite)
        case EngineNode.Label2DWithState(label, _) => Node2D.getRotation(label)
        case EngineNode.Marker2DWithState(marker, _) => Node2D.getRotation(marker)
        case EngineNode.Path2DWithState(path, _) => Node2D.getRotation(path)
        case EngineNode.ScreenNotifier2DWithState(_, _) => 0.0
        case EngineNode.TimerWithState(timer, _) => Node2D.getRotation(timer)
        case EngineNode.ColorRectWithState(rect, _) => Node2D.getRotation(rect)
        case EngineNode.GPUParticles2DWithState(emitter, _) => Node2D.getRotation(emitter)
        case EngineNode.CanvasLayerWithState(cl, _) => Node2D.getRotation(cl)
        case EngineNode.ControlWithState(ctrl, _) => Node2D.getRotation(ctrl)
        case EngineNode.ButtonWithState(btn, _) => Node2D.getRotation(btn)
        case EngineNode.TextureButtonWithState(btn, _) => Node2D.getRotation(btn)
        case EngineNode.Camera2DWithState(cam, _) => Node2D.getRotation(cam)
        case EngineNode.StaticBody2DWithState(body, _) => Node2D.getRotation(body)
    }
    pub def setRotation(rotation: Float64, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.Sprite2DWithState(sprite, st) => EngineNode.Sprite2DWithState(Node2D.setRotation(rotation, sprite), st)
        case EngineNode.Area2DWithState(area, st) => EngineNode.Area2DWithState(Node2D.setRotation(rotation, area), st)
        case EngineNode.Body2DWithState(body, st) => EngineNode.Body2DWithState(Node2D.setRotation(rotation, body), st)
        case EngineNode.RigidBody2DWithState(body, st) => EngineNode.RigidBody2DWithState(Node2D.setRotation(rotation, body), st)
        case EngineNode.AnimSprite2DWithState(sprite, st) => EngineNode.AnimSprite2DWithState(Node2D.setRotation(rotation, sprite), st)
        case EngineNode.Label2DWithState(label, st) => EngineNode.Label2DWithState(Node2D.setRotation(rotation, label), st)
        case EngineNode.Marker2DWithState(marker, st) => EngineNode.Marker2DWithState(Node2D.setRotation(rotation, marker), st)
        case EngineNode.Path2DWithState(path, st) => EngineNode.Path2DWithState(Node2D.setRotation(rotation, path), st)
        case EngineNode.ScreenNotifier2DWithState(_, _) => node
        case EngineNode.TimerWithState(timer, st) => EngineNode.TimerWithState(Node2D.setRotation(rotation, timer), st)
        case EngineNode.ColorRectWithState(rect, st) => EngineNode.ColorRectWithState(Node2D.setRotation(rotation, rect), st)
        case EngineNode.GPUParticles2DWithState(emitter, st) => EngineNode.GPUParticles2DWithState(Node2D.setRotation(rotation, emitter), st)
        case EngineNode.CanvasLayerWithState(cl, st) => EngineNode.CanvasLayerWithState(Node2D.setRotation(rotation, cl), st)
        case EngineNode.ControlWithState(ctrl, st) => EngineNode.ControlWithState(Node2D.setRotation(rotation, ctrl), st)
        case EngineNode.ButtonWithState(btn, st) => EngineNode.ButtonWithState(Node2D.setRotation(rotation, btn), st)
        case EngineNode.TextureButtonWithState(btn, st) => EngineNode.TextureButtonWithState(Node2D.setRotation(rotation, btn), st)
        case EngineNode.Camera2DWithState(cam, st) => EngineNode.Camera2DWithState(Node2D.setRotation(rotation, cam), st)
        case EngineNode.StaticBody2DWithState(body, st) => EngineNode.StaticBody2DWithState(Node2D.setRotation(rotation, body), st)
    }
    pub def getScale(node: EngineNode[s]): Vec2.Vec2 = match node {
        case EngineNode.Sprite2DWithState(sprite, _) => Node2D.getScale(sprite)
        case EngineNode.Area2DWithState(area, _) => Node2D.getScale(area)
        case EngineNode.Body2DWithState(body, _) => Node2D.getScale(body)
        case EngineNode.RigidBody2DWithState(body, _) => Node2D.getScale(body)
        case EngineNode.AnimSprite2DWithState(sprite, _) => Node2D.getScale(sprite)
        case EngineNode.Label2DWithState(label, _) => Node2D.getScale(label)
        case EngineNode.Marker2DWithState(marker, _) => Node2D.getScale(marker)
        case EngineNode.Path2DWithState(path, _) => Node2D.getScale(path)
        case EngineNode.ScreenNotifier2DWithState(_, _) => {x = 1.0, y = 1.0}
        case EngineNode.TimerWithState(timer, _) => Node2D.getScale(timer)
        case EngineNode.ColorRectWithState(rect, _) => Node2D.getScale(rect)
        case EngineNode.GPUParticles2DWithState(emitter, _) => Node2D.getScale(emitter)
        case EngineNode.CanvasLayerWithState(cl, _) => Node2D.getScale(cl)
        case EngineNode.ControlWithState(ctrl, _) => Node2D.getScale(ctrl)
        case EngineNode.ButtonWithState(btn, _) => Node2D.getScale(btn)
        case EngineNode.TextureButtonWithState(btn, _) => Node2D.getScale(btn)
        case EngineNode.Camera2DWithState(cam, _) => Node2D.getScale(cam)
        case EngineNode.StaticBody2DWithState(body, _) => Node2D.getScale(body)
    }
    pub def setScale(scale: Vec2.Vec2, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.Sprite2DWithState(sprite, st) => EngineNode.Sprite2DWithState(Node2D.setScale(scale, sprite), st)
        case EngineNode.Area2DWithState(area, st) => EngineNode.Area2DWithState(Node2D.setScale(scale, area), st)
        case EngineNode.Body2DWithState(body, st) => EngineNode.Body2DWithState(Node2D.setScale(scale, body), st)
        case EngineNode.RigidBody2DWithState(body, st) => EngineNode.RigidBody2DWithState(Node2D.setScale(scale, body), st)
        case EngineNode.AnimSprite2DWithState(sprite, st) => EngineNode.AnimSprite2DWithState(Node2D.setScale(scale, sprite), st)
        case EngineNode.Label2DWithState(label, st) => EngineNode.Label2DWithState(Node2D.setScale(scale, label), st)
        case EngineNode.Marker2DWithState(marker, st) => EngineNode.Marker2DWithState(Node2D.setScale(scale, marker), st)
        case EngineNode.Path2DWithState(path, st) => EngineNode.Path2DWithState(Node2D.setScale(scale, path), st)
        case EngineNode.ScreenNotifier2DWithState(_, _) => node
        case EngineNode.TimerWithState(timer, st) => EngineNode.TimerWithState(Node2D.setScale(scale, timer), st)
        case EngineNode.ColorRectWithState(rect, st) => EngineNode.ColorRectWithState(Node2D.setScale(scale, rect), st)
        case EngineNode.GPUParticles2DWithState(emitter, st) => EngineNode.GPUParticles2DWithState(Node2D.setScale(scale, emitter), st)
        case EngineNode.CanvasLayerWithState(cl, st) => EngineNode.CanvasLayerWithState(Node2D.setScale(scale, cl), st)
        case EngineNode.ControlWithState(ctrl, st) => EngineNode.ControlWithState(Node2D.setScale(scale, ctrl), st)
        case EngineNode.ButtonWithState(btn, st) => EngineNode.ButtonWithState(Node2D.setScale(scale, btn), st)
        case EngineNode.TextureButtonWithState(btn, st) => EngineNode.TextureButtonWithState(Node2D.setScale(scale, btn), st)
        case EngineNode.Camera2DWithState(cam, st) => EngineNode.Camera2DWithState(Node2D.setScale(scale, cam), st)
        case EngineNode.StaticBody2DWithState(body, st) => EngineNode.StaticBody2DWithState(Node2D.setScale(scale, body), st)
    }
    pub def getSkew(node: EngineNode[s]): Float64 = match node {
        case EngineNode.Sprite2DWithState(sprite, _) => Node2D.getSkew(sprite)
        case EngineNode.Area2DWithState(area, _) => Node2D.getSkew(area)
        case EngineNode.Body2DWithState(body, _) => Node2D.getSkew(body)
        case EngineNode.RigidBody2DWithState(body, _) => Node2D.getSkew(body)
        case EngineNode.AnimSprite2DWithState(sprite, _) => Node2D.getSkew(sprite)
        case EngineNode.Label2DWithState(label, _) => Node2D.getSkew(label)
        case EngineNode.Marker2DWithState(marker, _) => Node2D.getSkew(marker)
        case EngineNode.Path2DWithState(path, _) => Node2D.getSkew(path)
        case EngineNode.ScreenNotifier2DWithState(_, _) => 0.0
        case EngineNode.TimerWithState(timer, _) => Node2D.getSkew(timer)
        case EngineNode.ColorRectWithState(rect, _) => Node2D.getSkew(rect)
        case EngineNode.GPUParticles2DWithState(emitter, _) => Node2D.getSkew(emitter)
        case EngineNode.CanvasLayerWithState(cl, _) => Node2D.getSkew(cl)
        case EngineNode.ControlWithState(ctrl, _) => Node2D.getSkew(ctrl)
        case EngineNode.ButtonWithState(btn, _) => Node2D.getSkew(btn)
        case EngineNode.TextureButtonWithState(btn, _) => Node2D.getSkew(btn)
        case EngineNode.Camera2DWithState(cam, _) => Node2D.getSkew(cam)
        case EngineNode.StaticBody2DWithState(body, _) => Node2D.getSkew(body)
    }
    pub def setSkew(skew: Float64, node: EngineNode[s]): EngineNode[s] = match node {
        case EngineNode.Sprite2DWithState(sprite, st) => EngineNode.Sprite2DWithState(Node2D.setSkew(skew, sprite), st)
        case EngineNode.Area2DWithState(area, st) => EngineNode.Area2DWithState(Node2D.setSkew(skew, area), st)
        case EngineNode.Body2DWithState(body, st) => EngineNode.Body2DWithState(Node2D.setSkew(skew, body), st)
        case EngineNode.RigidBody2DWithState(body, st) => EngineNode.RigidBody2DWithState(Node2D.setSkew(skew, body), st)
        case EngineNode.AnimSprite2DWithState(sprite, st) => EngineNode.AnimSprite2DWithState(Node2D.setSkew(skew, sprite), st)
        case EngineNode.Label2DWithState(label, st) => EngineNode.Label2DWithState(Node2D.setSkew(skew, label), st)
        case EngineNode.Marker2DWithState(marker, st) => EngineNode.Marker2DWithState(Node2D.setSkew(skew, marker), st)
        case EngineNode.Path2DWithState(path, st) => EngineNode.Path2DWithState(Node2D.setSkew(skew, path), st)
        case EngineNode.ScreenNotifier2DWithState(_, _) => node
        case EngineNode.TimerWithState(timer, st) => EngineNode.TimerWithState(Node2D.setSkew(skew, timer), st)
        case EngineNode.ColorRectWithState(rect, st) => EngineNode.ColorRectWithState(Node2D.setSkew(skew, rect), st)
        case EngineNode.GPUParticles2DWithState(emitter, st) => EngineNode.GPUParticles2DWithState(Node2D.setSkew(skew, emitter), st)
        case EngineNode.CanvasLayerWithState(cl, st) => EngineNode.CanvasLayerWithState(Node2D.setSkew(skew, cl), st)
        case EngineNode.ControlWithState(ctrl, st) => EngineNode.ControlWithState(Node2D.setSkew(skew, ctrl), st)
        case EngineNode.ButtonWithState(btn, st) => EngineNode.ButtonWithState(Node2D.setSkew(skew, btn), st)
        case EngineNode.TextureButtonWithState(btn, st) => EngineNode.TextureButtonWithState(Node2D.setSkew(skew, btn), st)
        case EngineNode.Camera2DWithState(cam, st) => EngineNode.Camera2DWithState(Node2D.setSkew(skew, cam), st)
        case EngineNode.StaticBody2DWithState(body, st) => EngineNode.StaticBody2DWithState(Node2D.setSkew(skew, body), st)
    }
}

// ── CollisionObject2D 実装 ──

instance CollisionObject2D[EngineNode[s]] {
    pub def getCollisionShape(node: EngineNode[s]): Option[CollisionShape2D] = match node {
        case EngineNode.Area2DWithState(area, _) => CollisionObject2D.getCollisionShape(area)
        case EngineNode.Body2DWithState(body, _) => CollisionObject2D.getCollisionShape(body)
        case EngineNode.RigidBody2DWithState(body, _) => CollisionObject2D.getCollisionShape(body)
        case EngineNode.StaticBody2DWithState(body, _) => CollisionObject2D.getCollisionShape(body)
        case _ => None
    }
    pub def isMonitoring(node: EngineNode[s]): Bool = match node {
        case EngineNode.Area2DWithState(area, _) => CollisionObject2D.isMonitoring(area)
        case EngineNode.Body2DWithState(body, _) => CollisionObject2D.isMonitoring(body)
        case EngineNode.RigidBody2DWithState(body, _) => CollisionObject2D.isMonitoring(body)
        case EngineNode.StaticBody2DWithState(body, _) => CollisionObject2D.isMonitoring(body)
        case _ => false
    }
    pub def isMonitorable(node: EngineNode[s]): Bool = match node {
        case EngineNode.Area2DWithState(area, _) => CollisionObject2D.isMonitorable(area)
        case EngineNode.Body2DWithState(body, _) => CollisionObject2D.isMonitorable(body)
        case EngineNode.RigidBody2DWithState(body, _) => CollisionObject2D.isMonitorable(body)
        case EngineNode.StaticBody2DWithState(body, _) => CollisionObject2D.isMonitorable(body)
        case _ => false
    }
    redef getCollisionPriority(node: EngineNode[s]): Int32 = match node {
        case EngineNode.Area2DWithState(area, _) => CollisionObject2D.getCollisionPriority(area)
        case EngineNode.Body2DWithState(body, _) => CollisionObject2D.getCollisionPriority(body)
        case EngineNode.RigidBody2DWithState(body, _) => CollisionObject2D.getCollisionPriority(body)
        case EngineNode.StaticBody2DWithState(body, _) => CollisionObject2D.getCollisionPriority(body)
        case _ => 0
    }
}

// ── Renderable 実装 ──

instance GameEngine.Renderable[EngineNode[s]] {
    pub def toDrawables(node: EngineNode[s], globalPos: Vec2.Vec2): List[GameEngine.Drawable] =
        match node {
            case EngineNode.Sprite2DWithState(sprite, _) =>
                EngineNode.spriteToDrawable(sprite, globalPos) :: Nil
            case EngineNode.AnimSprite2DWithState(sprite, _) =>
                EngineNode.animSpriteToDrawable(sprite, globalPos) :: Nil
            case EngineNode.Label2DWithState(label, _) =>
                Label2D.toDrawables(label, globalPos)
            case EngineNode.ColorRectWithState(rect, _) =>
                ColorRect.toDrawable(rect, globalPos) :: Nil
            case EngineNode.GPUParticles2DWithState(emitter, _) =>
                GPUParticles2D.toDrawables(emitter, globalPos)
            case EngineNode.Path2DWithState(_, _) => Nil
            case EngineNode.ScreenNotifier2DWithState(_, _) => Nil
            case EngineNode.TimerWithState(_, _) => Nil
            case EngineNode.CanvasLayerWithState(_, _) => Nil
            case EngineNode.ControlWithState(_, _) => Nil
            case EngineNode.ButtonWithState(btn, _) =>
                Button.toDrawables(btn, globalPos)
            case EngineNode.TextureButtonWithState(btn, _) =>
                TextureButton.toDrawables(btn, globalPos)
            case EngineNode.Camera2DWithState(_, _) => Nil
            case EngineNode.StaticBody2DWithState(_, _) => Nil
            case EngineNode.RigidBody2DWithState(_, _) => Nil
            case EngineNode.Area2DWithState(_, _) => Nil
            case EngineNode.Body2DWithState(_, _) => Nil
            case EngineNode.Marker2DWithState(_, _) => Nil
        }
}
