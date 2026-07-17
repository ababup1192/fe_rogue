// SettingsCodec — World.Settings の saves/settings.json への読み書き。
// Saveable instance は nominal 型にしか付けられない（World.Settings は type alias で不可）ため、
// レコードを enum でラップする（fe_rogue SuspendSave / catalog 群と同じ理由）。
mod SettingsCodec {

    /// 保存用の nominal ラップ。中身は World.Settings と同じフィールドそのまま。
    pub enum Save {
        case Save(World.Settings)
    }

    pub def wrap(settings: World.Settings): Save = Save.Save(settings)

    pub def unwrap(save: Save): World.Settings =
        let Save.Save(settings) = save;
        settings
}

instance Saveable[SettingsCodec.Save] {
    pub def toJson(value: SettingsCodec.Save): Util.Json.Json =
        let settings = SettingsCodec.unwrap(value);
        Util.Json.Json.JObject(Map#{
            "masterVolume"  => Util.Json.Json.JNumber(JsonCodec.floatToBd(settings#masterVolume)),
            "bgmOn"         => Util.Json.Json.JBool(settings#bgmOn),
            "fullscreen"    => Util.Json.Json.JBool(settings#fullscreen),
            "cursorVisible" => Util.Json.Json.JBool(settings#cursorVisible)
        })

    pub def fromJson(element: Util.Json.Json): Option[SettingsCodec.Save] =
        forM (
            map           <- JsonCodec.expectObject(element);
            masterVolumeJ <- Map.get("masterVolume", map);
            masterVolume  <- JsonCodec.expectFloat(masterVolumeJ);
            bgmOnJ        <- Map.get("bgmOn", map);
            bgmOn         <- JsonCodec.expectBool(bgmOnJ);
            fullscreenJ   <- Map.get("fullscreen", map);
            fullscreen    <- JsonCodec.expectBool(fullscreenJ);
            cursorJ       <- Map.get("cursorVisible", map);
            cursorVisible <- JsonCodec.expectBool(cursorJ)
        ) yield SettingsCodec.wrap({ masterVolume = masterVolume, bgmOn = bgmOn,
                                     fullscreen = fullscreen, cursorVisible = cursorVisible })
}
