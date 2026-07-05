// SnapshotCatalog — スナップショット全 42 枚の目録（純データ）。
//
// ここは「何を撮るか」の唯一の宣言点。各エントリは名前・1 行説明・種別（PNG/GIF）・所属シナリオ・
// タグだけを持つ。実際にどう組んで描くか（drive）は TestUiSnapshots の driveByName、GIF の収録は
// TestGifSnapshots が受け持つ。名前がゴールデン/画像ファイル名・drive の分岐キー・不具合報告の正。
//
// シナリオは「コマンドメニュー」「タイトル画面」のようなゲーム機能単位（title / top-bar /
// action-menu / item-menu / weapon-select / trade / game-over / suspend / unit-cards / log /
// turn-end-hold / item-pickup）。複数 HUD の組み合わせ（旧 hud-combos）や満載・境界（旧
// edge-cases）は、それが最も体感される機能のページへ合流させ、タグで補足する。他機能をまたぐ
// エントリ（例: コマンド→アイテムの遷移 GIF）は主機能側に置き、もう一方の機能名を tags に足して
// タグページ経由で見えるようにする。エッジケースは tags に "edge-case" を必ず含める（SnapshotSite
// がこのタグでページ内の節を振り分ける）。
//
// 拡張の仕方:
//   - スナップショットを 1 枚足す = ここに 1 行足し（name/desc/kind/scenario/tags）、
//     TestUiSnapshots に driveByName の腕と drive 関数を 1 個足す（GIF なら TestGifSnapshots に
//     gen 関数を 1 個）。
//   - ゲーム機能を 1 つ足す = 新しい scenario 文字列を書くだけ。SnapshotSite が自動でページを増やし、
//     ハブのカードと前後導線に組み込む。
// 表示順・ページ順・前後導線の順序は、この entries() の宣言順に一致する。
mod SnapshotCatalog {

    /// スナップショットの種別。PNG は静止画（golden つき）、GIF は操作フローの動画。
    pub enum Kind with Eq {
        case Png
        case Gif
    }

    /// 目録 1 項目。
    pub type alias Entry = {
        name     = String,        // ゴールデン/画像のファイル名・drive の分岐キー・報告用の正
        desc     = String,        // index / ページに出す 1 行説明
        kind     = Kind,          // 静止画(Png) か 操作フロー(Gif) か
        scenario = String,        // 所属ゲーム機能（ページの束ね。宣言順が表示順）
        tags     = List[String]   // 分類タグ。"edge-case" はページ内節の振り分けに使われる予約タグ
    }

    /// 全エントリ（宣言順＝ページ順）。ゲーム機能の並びは
    /// title → top-bar → action-menu → item-menu → weapon-select → trade → game-over →
    /// suspend → unit-cards → log → turn-end-hold → item-pickup。
    pub def entries(): List[Entry] =
        // ── title: タイトル画面 ──
        {name = "title_menu", kind = Kind.Png, scenario = "title", tags = "title" :: Nil,
         desc = "タイトル画面（中断から再開あり・2 択 + 塗り箱ハイライト）"} ::
        // ── character-select: 出撃メンバー選択 ──
        // カルーセルは注目カードを中央に寄せ、左右のカードは画面外へはみ出す設計なので R3 を抑制する。
        {name = "character_select", kind = Kind.Png, scenario = "character-select",
         tags = "character-select" :: "lint-allow:R3" :: Nil,
         desc = "出撃メンバー選択（カード列カルーセル・3 人選択済みで出撃可・注目カードの拡大と枠色）"} ::
        {name = "flow_character_select", kind = Kind.Gif, scenario = "character-select",
         tags = "flow" :: "character-select" :: Nil,
         desc = "出撃メンバー選択の流れ（注目カードを右へ送るとカルーセルが滑らかに寄り、Z で 3 人選ぶと出撃ボタンが有効化）"} ::
        // ── top-bar: 上部バー（陣営・フェイズ表示） ──
        {name = "top_bar_ally", kind = Kind.Png, scenario = "top-bar", tags = "top-bar" :: "ally" :: Nil,
         desc = "上部バー・自軍確定（青帯・青下線・青ドット・自軍フェイズ）"} ::
        {name = "top_bar_enemy", kind = Kind.Png, scenario = "top-bar", tags = "top-bar" :: "enemy" :: Nil,
         desc = "上部バー・敵軍確定（赤帯・赤下線・赤ドット・ENEMY PHASE）"} ::
        {name = "top_bar_wipe", kind = Kind.Png, scenario = "top-bar", tags = "top-bar" :: "wipe" :: Nil,
         desc = "上部バー・陣営ワイプ 50%（青ベースに赤 sweep が半分）"} ::
        {name = "top_bar_gather", kind = Kind.Png, scenario = "top-bar", tags = "top-bar" :: "gather" :: Nil,
         desc = "上部バー・集合中（▶ + 集合中ラベル）"} ::
        {name = "topbar_wipe", kind = Kind.Gif, scenario = "top-bar", tags = "flow" :: "top-bar" :: Nil,
         desc = "上部バー・陣営ワイプ（自軍確定→敵ターン点火→赤ワイプが左から流れて確定）"} ::
        // ── action-menu: コマンドメニュー ──
        {name = "action_menu_7", kind = Kind.Png, scenario = "action-menu", tags = "action-menu" :: "full" :: Nil,
         desc = "アクションメニュー・フル（味方が拾う/あける/階段/攻撃の全条件を満たす）"} ::
        {name = "action_menu_3", kind = Kind.Png, scenario = "action-menu",
         tags = "action-menu" :: "empty-cell" :: Nil,
         desc = "空マスメニュー 3 項目（集合/ターンエンド/中断）"} ::
        {name = "hud_action_menu", kind = Kind.Png, scenario = "action-menu",
         tags = "action-menu" :: "combo" :: "top-bar" :: Nil,
         desc = "コマンド選択 HUD：TopBar + アクションメニュー(フル)"} ::
        {name = "flow_action_menu", kind = Kind.Gif, scenario = "action-menu", tags = "flow" :: "action-menu" :: Nil,
         desc = "コマンドメニューの選択移動（↓↓↓→↑・ハイライト箱が動く）"} ::
        {name = "flow_open_item", kind = Kind.Gif, scenario = "action-menu",
         tags = "flow" :: "action-menu" :: "item-menu" :: "transition" :: Nil,
         desc = "コマンド→アイテム確定で持ち物窓が開く（↓で選び Z で開き→↓↓→X で戻る・phase 遷移）"} ::
        // ── item-menu: 持ち物 ──
        {name = "item_menu_select", kind = Kind.Png, scenario = "item-menu", tags = "item-menu" :: Nil,
         desc = "持ち物（本物は 1 カテゴリ表示・◀ 武器 ▶・重量ヘッダ）"} ::
        {name = "item_menu_action", kind = Kind.Png, scenario = "item-menu",
         tags = "item-menu" :: "submenu" :: Nil,
         desc = "持ち物サブメニュー（武器選択中＝そうび/なげる/すてる）"} ::
        {name = "item_menu_full_top", kind = Kind.Png, scenario = "item-menu",
         tags = "item-menu" :: "scroll" :: "edge-case" :: Nil,
         desc = "持ち物満載・窓の上端を選択（重い在庫の重量ヘッダ色は実ロジック）"} ::
        {name = "item_menu_full_bottom", kind = Kind.Png, scenario = "item-menu",
         tags = "item-menu" :: "scroll" :: "edge-case" :: Nil,
         desc = "持ち物満載・窓の下端を選択（スクロール offset も実ロジック）"} ::
        {name = "hud_item_menu", kind = Kind.Png, scenario = "item-menu",
         tags = "item-menu" :: "combo" :: "top-bar" :: Nil,
         desc = "アイテム HUD：TopBar + 持ち物メニュー"} ::
        {name = "flow_item_scroll", kind = Kind.Gif, scenario = "item-menu",
         tags = "flow" :: "item-menu" :: "scroll" :: Nil,
         desc = "持ち物・満載で窓スクロール（↓×10・窓が選択に追従）"} ::
        // ── weapon-select: 武器選択 ──
        {name = "weapon_select", kind = Kind.Png, scenario = "weapon-select", tags = "weapon-select" :: Nil,
         desc = "武器選択（威力/耐久/重さサブライン・苦手バッジ・射程外は淡色）"} ::
        {name = "hud_attack_flow", kind = Kind.Png, scenario = "weapon-select",
         tags = "weapon-select" :: "combo" :: "action-menu" :: "top-bar" :: "unit-cards" :: Nil,
         desc = "攻撃フロー最盛：TopBar + アクション + 武器選択 + 自軍/敵カード（窓の重なり・z 序列）"} ::
        {name = "flow_attack_weapon", kind = Kind.Gif, scenario = "weapon-select",
         tags = "flow" :: "weapon-select" :: "action-menu" :: "transition" :: Nil,
         desc = "攻撃確定で武器窓が右に開く（Z で開き→↓で武器切替・ActionSelect→WeaponSelect 遷移）"} ::
        // ── trade: 交換 ──
        {name = "trade_menu", kind = Kind.Png, scenario = "trade", tags = "trade" :: Nil,
         desc = "交換メニュー 2 人ぶん（本物の syncPane が末尾に空きスロットを出す）"} ::
        {name = "trade_menu_4panes", kind = Kind.Png, scenario = "trade", tags = "trade" :: "edge-case" :: Nil,
         desc = "交換メニュー 4 ペイン満載（空きスロットの出方も実 syncPane 由来）"} ::
        // ── game-over: ゲームオーバー ──
        {name = "game_over_menu", kind = Kind.Png, scenario = "game-over", tags = "game-over" :: "modal" :: Nil,
         desc = "ゲームオーバーのモーダル選択（GameOver フェーズで可視）"} ::
        {name = "hud_game_over", kind = Kind.Png, scenario = "game-over",
         tags = "game-over" :: "combo" :: "top-bar" :: "modal" :: Nil,
         desc = "ゲームオーバー HUD：TopBar + モーダル"} ::
        {name = "flow_game_over", kind = Kind.Gif, scenario = "game-over", tags = "flow" :: "game-over" :: Nil,
         desc = "ゲームオーバーのモーダル選択移動（↓↓↑）"} ::
        // ── suspend: 中断確認 ──
        {name = "suspend_confirm", kind = Kind.Png, scenario = "suspend", tags = "suspend" :: "modal" :: Nil,
         desc = "中断確認のモーダル（SuspendConfirm フェーズで可視）"} ::
        // ── unit-cards: ユニットカード ──
        {name = "unit_card", kind = Kind.Png, scenario = "unit-cards", tags = "unit-cards" :: "ally" :: Nil,
         desc = "自軍ユニットカード（選択中味方・Lv/EXP/HP・武器/指輪アイコン）"} ::
        {name = "enemy_card", kind = Kind.Png, scenario = "unit-cards", tags = "unit-cards" :: "enemy" :: Nil,
         desc = "敵ユニットカード（WeaponSelect のカーソル上の敵・Lv/EXP 行なし・赤枠）"} ::
        {name = "hud_player_phase", kind = Kind.Png, scenario = "unit-cards",
         tags = "unit-cards" :: "combo" :: "top-bar" :: "ally" :: Nil,
         desc = "自軍フェイズ HUD：TopBar(自軍) + ユニットカード"} ::
        {name = "hud_enemy_phase", kind = Kind.Png, scenario = "unit-cards",
         tags = "unit-cards" :: "combo" :: "top-bar" :: "enemy" :: Nil,
         desc = "敵フェイズ HUD：TopBar(敵軍・赤) + ユニットカード"} ::
        // ── log: 一時ログ ──
        {name = "log_lines", kind = Kind.Png, scenario = "log", tags = "log" :: Nil,
         desc = "右下の一時ログ HUD（3 行表示中・半透明の黒帯）"} ::
        {name = "flow_log", kind = Kind.Gif, scenario = "log", tags = "flow" :: "log" :: Nil,
         desc = "一時ログの流れ（白=プレイヤー / 赤=敵 を時間差で注入 → 行が押し上がる → アイドルで帯ごと消える）"} ::
        // ── turn-end-hold: ターンスキップ長押し ──
        {name = "turn_end_hold_50", kind = Kind.Png, scenario = "turn-end-hold", tags = "turn-end-hold" :: Nil,
         desc = "ターンスキップ長押しゲージ 50%（ログ帯の上に充填リング 50% + 「ターンスキップ」）"} ::
        {name = "flow_turn_end_hold", kind = Kind.Gif, scenario = "turn-end-hold",
         tags = "flow" :: "turn-end-hold" :: Nil,
         desc = "ターンスキップ長押し（Shift 長押し → 充填リングが満ちる → 発動）"} ::
        // ── item-pickup: アイテム取得ポップアップ ──
        {name = "item_pickup_popup", kind = Kind.Png, scenario = "item-pickup", tags = "item-pickup" :: Nil,
         desc = "中央アイテム取得ポップアップ（表示中・窓 + 「○○を手に入れた」）"} ::
        // ── battle-panel: 攻撃前の戦闘予報ミニウィンドウ ──
        {name = "battle_panel", kind = Kind.Png, scenario = "battle-panel", tags = "battle-panel" :: Nil,
         desc = "戦闘予報ミニウィンドウ（命中/必殺/反撃の予報数値・相性三角。実 frameStep 由来）"} ::
        // ── level-up: レベルアップ演出パネル ──
        {name = "level_up_panel", kind = Kind.Png, scenario = "level-up", tags = "level-up" :: Nil,
         desc = "レベルアップのステータス変化パネル（増分表示の途中・上昇行に -> 新値 +1）"} ::
        {name = "flow_level_up", kind = Kind.Gif, scenario = "level-up", tags = "flow" :: "level-up" :: Nil,
         desc = "レベルアップ演出（出現 → 各ステータス増分が順に出る → 確定で閉じる）"} ::
        // ── minimap: ミニマップ（探索済みマップ・M で表示トグル。RenderWorld.renderMinimap 直描き） ──
        {name = "minimap_normal", kind = Kind.Png, scenario = "minimap", tags = "minimap" :: Nil,
         desc = "ミニマップ・一部探索（部屋1+通路を訪問・未訪問の隣接通路はヒント表示・味方/アイテム/敵マーカー）"} ::
        {name = "minimap_explored", kind = Kind.Png, scenario = "minimap", tags = "minimap" :: "full" :: Nil,
         desc = "ミニマップ・全探索（両部屋+通路を訪問・階段発見マーカーつき）"} ::
        // ── fire-fx: 魔法の炎着弾（閉形式パーティクル直描き・FireFx.quads）──
        // 10 プリセットの見比べページ。どれも 左=実寸 1 マス / 右=拡大、seed 1→2→3 の 3 連発。
        {name = "flow_fire_standard", kind = Kind.Gif, scenario = "fire-fx", tags = "flow" :: "fire-fx" :: Nil,
         desc = "焚き火型（標準）: 黄→橙→赤の舌がバランスよく燃え上がる"} ::
        {name = "flow_fire_pillar", kind = Kind.Gif, scenario = "fire-fx", tags = "flow" :: "fire-fx" :: Nil,
         desc = "火柱: 細くまとまった白熱の舌が勢いよく高く噴き上がる"} ::
        {name = "flow_fire_flare", kind = Kind.Gif, scenario = "fire-fx", tags = "flow" :: "fire-fx" :: Nil,
         desc = "爆炎: セル中心から全方位へ一斉に弾ける短く激しい爆発（閃光大きめ）"} ::
        {name = "flow_fire_smolder", kind = Kind.Gif, scenario = "fire-fx", tags = "flow" :: "fire-fx" :: Nil,
         desc = "残り火: 低く広く深紅の舌がゆっくりくすぶる（閃光なし・余韻長め）"} ::
        {name = "flow_fire_arcane", kind = Kind.Gif, scenario = "fire-fx", tags = "flow" :: "fire-fx" :: Nil,
         desc = "蒼炎: 青白い魔法の火。白→水色→青→菫色に冷める"} ::
        {name = "flow_fire_droplet", kind = Kind.Gif, scenario = "fire-fx", tags = "flow" :: "fire-fx" :: Nil,
         desc = "雫型: 丸底の柔らかな舌がゆらめく、ろうそく・鬼火のあかり"} ::
        {name = "flow_fire_fireball", kind = Kind.Gif, scenario = "fire-fx", tags = "flow" :: "fire-fx" :: Nil,
         desc = "火の玉: 脈動する大玉＋白熱の核（2 層）を舌と火の粉が舐める"} ::
        {name = "flow_fire_sidestream", kind = Kind.Gif, scenario = "fire-fx", tags = "flow" :: "fire-fx" :: Nil,
         desc = "横流れ: 風に吹かれて右へ流れ、強く傾いて燃える炎"} ::
        {name = "flow_fire_vortex", kind = Kind.Gif, scenario = "fire-fx", tags = "flow" :: "fire-fx" :: Nil,
         desc = "渦巻き: 舌が中心を公転しながら立ち上り、螺旋を描く"} ::
        {name = "flow_fire_sparkler", kind = Kind.Gif, scenario = "fire-fx", tags = "flow" :: "fire-fx" :: Nil,
         desc = "線香花火: 速度方向に伸びる streak の火の粉が長い弧を描き、儚くまたたく"} ::
        {name = "flow_tome_attack", kind = Kind.Gif, scenario = "fire-fx", tags = "flow" :: "fire-fx" :: "combat" :: Nil,
         desc = "魔導書攻撃の炎 3 幕: 詠唱者の頭上に火の玉が生まれ（詠唱）→対象へ飛び（飛翔）→大きく炸裂する（着弾）"} :: Nil

    /// PNG エントリだけ（TestUiSnapshots が drive + golden 比較する対象）。
    pub def pngEntries(): List[Entry] = List.filter(entry -> entry#kind == Kind.Png, entries())

    /// GIF エントリだけ（TestGifSnapshots が収録する対象）。
    pub def gifEntries(): List[Entry] = List.filter(entry -> entry#kind == Kind.Gif, entries())

    /// 目録を SnapshotSite の表示用 Item 列へ変換する。ここが Kind → 拡張子/表示幅/未生成案内の
    /// 対応表で、SnapshotSite にゲーム都合を持ち込ませないためのアダプタ。実ピクセル幅は撮影側の
    /// 定数（PNG/GIF で解像度が違う）なので引数で受ける。
    pub def toItems(widths: {pngPxWidth = Int32, gifPxWidth = Int32}, gifHint: String): List[SnapshotSite.Item] =
        List.map(entry -> match entry#kind {
            case Kind.Png =>
                {name = entry#name, desc = entry#desc, scenario = entry#scenario, tags = entry#tags,
                 ext = "png", pxWidth = widths#pngPxWidth, generateHint = (None: Option[String]),
                 lint = SnapshotSite.noLint()}
            case Kind.Gif =>
                {name = entry#name, desc = entry#desc, scenario = entry#scenario, tags = entry#tags,
                 ext = "gif", pxWidth = widths#gifPxWidth, generateHint = Some(gifHint),
                 lint = SnapshotSite.noLint()}
        }, entries())
}
