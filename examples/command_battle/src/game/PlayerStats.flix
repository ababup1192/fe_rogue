/// PlayerStats — 勇者の初期ステータス Resource。
///
/// `resources/player.json` を起動時に読み込んで `HeroStats` 値を返す。
/// 数値は JSON 直接編集で変更でき、 ゲームを再起動すれば即反映される（負け戦闘の
/// シミュレーションなど数値調整に使う）。
mod PlayerStats {

    use Util.Json.Json
    use Util.Json.Json.{JObject, JNumber, JString}

    /// 勇者ステータス。 BattleScene.State の hero フィールドにそのまま入る型。
    pub type alias HeroStats = {
        name    = String,
        hp      = Int32, maxHp   = Int32,
        mp      = Int32, maxMp   = Int32,
        attack  = Int32, defense = Int32,
        level   = Int32
    }

    /// `resources/player.json` をロードする。 失敗時は panic でクラッシュ（起動時に即可視化）。
    pub def load(path: String): HeroStats \ Fs.FileRead =
        let readResult = run {
            Fs.ReadFile.read(path)
        } with Fs.ReadFile.runWithFileRead;
        match readResult {
            case Err(e) => bug!("PlayerStats.load file read failed: ${path} :: ${e}")
            case Ok(content) =>
                match JsonCompat.parse(content) {
                    case None => bug!("PlayerStats.load JSON parse failed: ${path}")
                    case Some(json) =>
                        match decode(json) {
                            case Some(h) => h
                            case None    => bug!("PlayerStats.load decode failed: ${path}")
                        }
                }
        }

    /// Json → HeroStats のデコード。 必要キーが欠けていれば None。
    def decode(element: Json): Option[HeroStats] =
        forM (
            obj      <- expectObject(element);
            nameJ    <- Map.get("name", obj);
            hpJ      <- Map.get("hp", obj);
            maxHpJ   <- Map.get("maxHp", obj);
            mpJ      <- Map.get("mp", obj);
            maxMpJ   <- Map.get("maxMp", obj);
            attackJ  <- Map.get("attack", obj);
            defenseJ <- Map.get("defense", obj);
            levelJ   <- Map.get("level", obj);
            name     <- expectString(nameJ);
            hp       <- expectInt(hpJ);
            maxHp    <- expectInt(maxHpJ);
            mp       <- expectInt(mpJ);
            maxMp    <- expectInt(maxMpJ);
            attack   <- expectInt(attackJ);
            defense  <- expectInt(defenseJ);
            level    <- expectInt(levelJ)
        ) yield ({
            name = name, hp = hp, maxHp = maxHp,
            mp = mp, maxMp = maxMp,
            attack = attack, defense = defense, level = level
        }: HeroStats)

    def expectObject(element: Json): Option[Map[String, Json]] =
        match element {
            case JObject(map) => Some(map)
            case _               => None
        }

    def expectString(element: Json): Option[String] =
        match element {
            case JString(text) => Some(text)
            case _                => None
        }

    def expectInt(element: Json): Option[Int32] =
        match element {
            case JNumber(bd) =>
                BigDecimal.tryToFloat64(bd) |> Option.flatMap(Float64.tryToInt32)
            case _              => None
        }
}
