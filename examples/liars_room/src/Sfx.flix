// Sfx — このフレームがどう聞こえるかの投影。実体は LiarsRoom.sfxEvent（純粋）で、
// 実際に鳴らす行為は App が引き受ける。
mod Sfx {

    pub def events(delta: { before = LiarsRoom.Session, after = LiarsRoom.Session }): List[String] =
        let oneShot = LiarsRoom.sfxEvent((delta#before)#world, (delta#after)#world) |> Option.toList;
        let bgm = if (LiarsRoom.bgmStarts((delta#before)#world, (delta#after)#world))
            "bgm" :: Nil else Nil;
        List.append(bgm, oneShot)
}
