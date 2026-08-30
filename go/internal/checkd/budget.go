package checkd

// 常駐が使ってよいメモリと、誰も来ないときに消えるまでの時間。

import (
	"os"
	"strconv"
	"time"

	"github.com/ababup1192/flix_game_engine/go/internal/hooks"
)

// rssLimitMB は repl 1 本を使い捨てるメモリの線 (MB)。
//
// 約束は 1 つ「常駐が全部太りきっても物理メモリの memoryShare まで」。台数と
// 1 本の太さを別々の定数で持つと、機械を変えたとき片方だけ古い値が残るので、
// 台数は hooks.MaxDaemonCount の 1 本だけを読む。
//
// WhyNot: 台数が 1 でも 2 で割るのは、1 台しか立てない小さい機械でその 1 本に
// 予算を丸ごと渡すと、他のアプリの居場所が無くなるため。
func rssLimitMB(r *hooks.Rules) int {
	lim := r.Checkd.Daemon.RSSLimit
	mb := *lim.FallbackMB
	if total, ok := hooks.MachineMemoryMB(); ok {
		daemons := hooks.MaxDaemonCount(r)
		if daemons < 2 {
			daemons = 2
		}
		mb = int(float64(total) * *lim.MemoryShare / float64(daemons))
		if mb < *lim.MinMB {
			mb = *lim.MinMB
		}
		if mb > *lim.MaxMB {
			mb = *lim.MaxMB
		}
	}
	if v := os.Getenv(*lim.EnvVar); v != "" {
		if parsed, err := strconv.Atoi(v); err == nil {
			mb = parsed
		}
	}
	if mb < *lim.FloorMB {
		mb = *lim.FloorMB
	}
	// heapMinMB より狭い rssLimit は成立しない — repl がウォームアップできないか、
	// できても毎回 rssLimit を超えて捨てられて常駐が 1 度も効かない。環境変数で
	// 狭められても、rssLimit は heapMinMB + heapHeadroomMB を下回らせない。
	if viable := *r.Checkd.Daemon.HeapMinMB + *r.Checkd.Daemon.HeapHeadroomMB; mb < viable {
		mb = viable
	}
	return mb
}

// heapCapMB は repl の JVM に渡すヒープの上限 (-Xmx の MB)。
//
// 蓋をしないと JVM は既定の最大ヒープ (物理の 1/4) まで自由に太るので、rssLimitMB の
// 線をいつか必ず超えて毎回使い捨てられ、常駐が 1 度も効かない。線を上げても太る先が
// 上がるだけなので、線の側でなく repl の側に蓋をする。
//
// ヒープの外にも JVM は場所を要る (クラスの置き場・JIT が吐いた機械語・スレッドの
// 積み場) ので、線からその分を引く。引く量は heapHeadroomMB。
func heapCapMB(r *hooks.Rules) int {
	mb := rssLimitMB(r) - *r.Checkd.Daemon.HeapHeadroomMB
	if mb < *r.Checkd.Daemon.HeapMinMB {
		mb = *r.Checkd.Daemon.HeapMinMB
	}
	return mb
}

// idleSec は誰も check しなければ常駐が自分で消えるまでの時間。
//
// 型検査の引き金が Stop/SubagentStop hook (作業の区切り) に移ったので、
// 保存のたび起動していた頃より次の要求までの間隔が空きやすい —
// 温め直しの数秒より、抱え続ける JVM のメモリを優先して短くしてある。
func idleSec(r *hooks.Rules) time.Duration {
	v := *r.Checkd.Daemon.IdleSec
	if s := os.Getenv(*r.Checkd.Daemon.IdleEnvVar); s != "" {
		if parsed, err := strconv.ParseFloat(s, 64); err == nil {
			v = parsed
		}
	}
	return seconds(v)
}
