// CopyDoc — 表紙、HUD、結果画面の文言。Viewは数値を差し込むだけにする。
mod CopyDoc {
    use Util.Json.Json

    /// プレイヤーの目に入る固定文言。
    pub type alias Doc = {
        version = Int32,
        titleTop = String, titleMain = String, tagline = String,
        steerHint = String, speedHint = String, boostHint = String, startHint = String,
        positionLabel = String, lapLabel = String, speedLabel = String,
        timeLabel = String, energyLabel = String, sectorLabel = String,
        readyLabel = String, offRoadLabel = String,
        finishTitle = String, crashedTitle = String, gameOverTitle = String,
        retryHint = String
    }

    pub def path(): String = "assets/apex.copy.json"

    /// JSONが無い時にも操作と結果が伝わる文言。
    pub def defaults(): Doc =
        { version = 1,
          titleTop = "MIDNIGHT", titleMain = "APEX",
          tagline = "CHASE THE LAST LIGHT",
          steerHint = "ARROWS / A D   STEER",
          speedHint = "UP   THROTTLE    DOWN   BRAKE",
          boostHint = "SPACE   BOOST", startHint = "PRESS SPACE",
          positionLabel = "POS", lapLabel = "LAP", speedLabel = "KM/H",
          timeLabel = "TIME", energyLabel = "ENERGY", sectorLabel = "SECTOR",
          readyLabel = "GET READY", offRoadLabel = "GRIP LOST",
          finishTitle = "FINISH", crashedTitle = "POWER FAILURE",
          gameOverTitle = "MACHINE LOST", retryHint = "SPACE TO RUN AGAIN" }

    /// 欠けた文言だけ既定値へ戻す。
    pub def fromJson(text: String): Option[Doc] =
        DocValue.root(text) |> Option.map(root -> {
            let d = defaults();
            { version = DocValue.int("version", d#version, DocValue.IntRule.Any, root),
              titleTop = DocValue.text("titleTop", d#titleTop, root),
              titleMain = DocValue.text("titleMain", d#titleMain, root),
              tagline = DocValue.text("tagline", d#tagline, root),
              steerHint = DocValue.text("steerHint", d#steerHint, root),
              speedHint = DocValue.text("speedHint", d#speedHint, root),
              boostHint = DocValue.text("boostHint", d#boostHint, root),
              startHint = DocValue.text("startHint", d#startHint, root),
              positionLabel = DocValue.text("positionLabel", d#positionLabel, root),
              lapLabel = DocValue.text("lapLabel", d#lapLabel, root),
              speedLabel = DocValue.text("speedLabel", d#speedLabel, root),
              timeLabel = DocValue.text("timeLabel", d#timeLabel, root),
              energyLabel = DocValue.text("energyLabel", d#energyLabel, root),
              sectorLabel = DocValue.text("sectorLabel", d#sectorLabel, root),
              readyLabel = DocValue.text("readyLabel", d#readyLabel, root),
              offRoadLabel = DocValue.text("offRoadLabel", d#offRoadLabel, root),
              finishTitle = DocValue.text("finishTitle", d#finishTitle, root),
              crashedTitle = DocValue.text("crashedTitle", d#crashedTitle, root),
              gameOverTitle = DocValue.text("gameOverTitle", d#gameOverTitle, root),
              retryHint = DocValue.text("retryHint", d#retryHint, root) }
        })

    /// ファイル全体が壊れていても既定値で続ける。
    pub def load(filePath: String): Doc \ Fs.FileRead =
        DocValue.load(filePath, defaults(), fromJson)
}
