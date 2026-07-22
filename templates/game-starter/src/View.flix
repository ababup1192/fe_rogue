// View — World から「(置き場所, 見せたい物) のリスト」への投影（純粋）。
// 背景はテーマの bg を全面に塗り、主人公はドット絵（PxSprite + ThemeDoc の resolver）。
// スプライトが読めないときは同じ差し色の四角に倒す（fail-open）。
mod View {

    def zBg(): Int32 = 0
    def zHero(): Int32 = 10

    /// スプライトの格子は 1 セル = 2px で描く。
    def px(): Int32 = 2

    pub def frame(_ctx: App.ViewCtx, w: World.World): List[Render.PlacedItem] =
        List.append(bg(w#theme), hero(w))

    def bg(theme: ThemeDoc.Doc): List[Render.PlacedItem] =
        { at = { x = 0.0, y = 0.0 },
          item = Render.box({ x = World.width(), y = World.height() }, theme#bg, zBg()) } :: Nil

    def hero(w: World.World): List[Render.PlacedItem] =
        let s = World.heroSize();
        let topLeft = { x = w#x - s / 2.0, y = w#y - s / 2.0 };
        let items = PxSprite.draw(w#sprites, "hero", "idle", topLeft,
            false, px(), key -> ThemeDoc.resolver(w#theme, key), zHero());
        if (List.isEmpty(items))
            // fail-open: スプライトが無い・読めないときは差し色の四角。
            { at = topLeft, item = Render.box({ x = s, y = s }, w#theme#accent, zHero()) } :: Nil
        else
            items
}
