mod Sample {
    // 予約語を 3 か所で踏む。踏むと Flix は型検査が終わらなくなる。
    pub def installArgs(r: {tool = String, into = String, from = String}): List[String] =
        r#tool :: r#into :: r#from :: Nil

    pub def place(): String =
        let into = "engines";
        into

    // 踏まない形 (連結・比較・match の矢印を項目名と読み違えないこと)
    pub def safe(xs: List[Bool]): String =
        match xs {
            case true :: _ => "yes"
            case _         => if (1 == 1) "no" else "maybe"
        }
}
