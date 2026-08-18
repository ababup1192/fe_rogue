package checkd

// 常駐側 — flix repl を 1 本抱えて温め、127.0.0.1 の TCP で注文を受ける。

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/ababup1192/flix_game_engine/go/internal/hooks"
)

// errorHeading は check のエラー見出し (-- Resolution Error [E2136] ---)。
var errorHeading = regexp.MustCompile(`(?m)^-- .*\bError\b`)

// testSummary は test のまとめ行。
var testSummary = regexp.MustCompile(`Passed: (\d+), Failed: (\d+)\.`)

type daemon struct {
	r    *hooks.Rules
	root string
	pkg  string
	sd   string
	ln   net.Listener

	cmd    *exec.Cmd
	stdin  *os.File
	out    chan []byte
	gone   chan struct{} // repl が終わったら閉じる
	seq    int
	checks int

	// snapshot は依存の実体の新しさ。変わったら repl を作り直す。
	snapshot map[string]int64

	// 直前に失敗した check の (出力, その時点の最新ソース mtime)。
	// 「ソースを編集したのに同一のエラーが返る」= repl の増分コンパイルの
	// 持ち越しを見破る材料。
	prevFail     string
	prevFailTime float64
	hasPrevFail  bool

	rssLimitMB int
}

// serve は常駐を立てて注文を受け続ける。1 パッケージに 1 匹しか立たない。
func serve(r *hooks.Rules, root, pkg string) int {
	d := &daemon{r: r, root: root, pkg: pkg, sd: stateDir(r, pkg), rssLimitMB: rssLimitMB(r)}
	// pid ファイルの O_EXCL 作成が「1 匹だけ」の鍵。作れなければ先客が居る。
	if !d.acquirePidFile() {
		return 0
	}
	meta, _ := json.Marshal(map[string]string{"pkg": pkg})
	_ = os.WriteFile(filepath.Join(d.sd, "meta.json"), meta, 0o644)

	portPath := filepath.Join(d.sd, "port")
	_ = os.Remove(portPath)
	// 127.0.0.1 限定 + ポート 0 (OS 採番)。外から届く口は開けない。
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		d.log(fmt.Sprintf("口を開けない: %v", err))
		d.releasePidFile()
		return 1
	}
	d.ln = ln
	port := ln.Addr().(*net.TCPAddr).Port
	// port ファイルは書き終えてから置く。書きかけを読ませない。
	tmp := portPath + ".tmp"
	if err := os.WriteFile(tmp, []byte(strconv.Itoa(port)), 0o644); err == nil {
		_ = os.Rename(tmp, portPath)
	}

	d.loop()
	d.shutdown()
	return 0
}

func (d *daemon) log(msg string) {
	fmt.Fprintf(os.Stderr, "[%s] %s\n", time.Now().Format("15:04:05"), msg)
}

func (d *daemon) acquirePidFile() bool {
	pidPath := filepath.Join(d.sd, "pid")
	for i := 0; i < 2; i++ {
		f, err := os.OpenFile(pidPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o644)
		if err == nil {
			fmt.Fprint(f, os.Getpid())
			f.Close()
			return true
		}
		// 残骸 (死んだ pid) なら片付けてもう 1 度だけ試す。
		pid := readPidFile(d.sd)
		if pid > 0 && hooks.PidAlive(pid) {
			return false
		}
		_ = os.Remove(pidPath)
	}
	return false
}

func (d *daemon) releasePidFile() {
	// 消すのは自分の分だけ。STOP の直後に次の常駐が立っていることがあり、
	// 無条件に消すと入れ替わりの新入りのファイルを消してしまう。
	if readPidFile(d.sd) != os.Getpid() {
		return
	}
	for _, f := range []string{"port", "pid"} {
		_ = os.Remove(filepath.Join(d.sd, f))
	}
}

// --- repl の寿命管理

func (d *daemon) startRepl() error {
	env := os.Environ()
	// repl 起動時に依存解決が走る。素の匿名アクセスは GitHub の
	// rate limit にすぐ当たるので、取れるなら token を持たせる。
	if os.Getenv("GITHUB_TOKEN") == "" {
		if out, err := exec.Command("gh", "auth", "token").Output(); err == nil {
			if tok := strings.TrimSpace(string(out)); tok != "" {
				env = append(env, "GITHUB_TOKEN="+tok)
			}
		}
	}
	// :test で GLFW と AWT の初期化がぶつかると固まるパッケージがある。
	// checkd は run を扱わないので常時 headless で害がない。
	//
	// -Xmx は「使い捨ての線 (rssLimitMB) に収まる repl」にするための蓋。
	// 蓋が無いと JVM は物理の 1/4 まで太り、1 回検査するたびに線を超えて
	// 捨てられる = 常駐が 1 度も効かない (実測 RSS 2,277MB 対 線 1,802MB)。
	env = append(env, fmt.Sprintf("JAVA_TOOL_OPTIONS=%s -Xmx%dm", headlessOpts(), heapCapMB(d.r)))

	// 素のパイプで十分 (端末は要らない)。エコーが無いので、番兵文字列は
	// repl が処理した応答の中にだけ現れる。
	//
	// WhyNot: exec の StdinPipe/StdoutPipe を使わないのは、それらを Wait が
	// 閉じにいき、出力を読む goroutine と取り合いになるため。
	inR, inW, err := os.Pipe()
	if err != nil {
		return err
	}
	outR, outW, err := os.Pipe()
	if err != nil {
		inR.Close()
		inW.Close()
		return err
	}
	cmd := exec.Command(flixBin(d.root, d.pkg), "repl")
	cmd.Dir = d.pkg
	cmd.Env = env
	cmd.Stdin, cmd.Stdout, cmd.Stderr = inR, outW, outW
	if err := cmd.Start(); err != nil {
		inR.Close()
		inW.Close()
		outR.Close()
		outW.Close()
		return err
	}
	inR.Close()
	outW.Close()
	d.cmd, d.stdin = cmd, inW
	// パイプの読みはブロックする一方、check には締め切りが要る。
	// 読み専用の脇 goroutine がチャネルへ流し、本流は締め切り付きで待つ。
	ch := make(chan []byte, 64)
	gone := make(chan struct{})
	d.out, d.gone = ch, gone
	go pump(outR, ch)
	go func() {
		_ = cmd.Wait()
		close(gone)
	}()
	d.checks = 0

	// 初回コンパイルが終わるまで repl は入力を処理しない。
	// 番兵を投げて応答が返る = 温まった、とみなす。
	work := seconds(*d.r.Checkd.Daemon.WorkTimeoutSec)
	if err := d.send(":zzz-warm\n"); err != nil {
		d.killRepl()
		return err
	}
	if ok, _ := d.waitFor("zzz-warm", work); !ok {
		d.killRepl()
		return fmt.Errorf("repl の起動がタイムアウト")
	}
	// 鮮度の基準は温め完了後に撮る。起動中の依存解決が lib/ を触るので、
	// 先に撮ると 1 回目の照合が必ず「変わった」になってしまう。
	d.snapshot = d.takeSnapshot()
	// 作り立ての repl の結果は持ち越しを含まないので、疑いも白紙に戻す。
	d.hasPrevFail = false
	return nil
}

func pump(r *os.File, ch chan []byte) {
	defer close(ch)
	defer r.Close()
	buf := make([]byte, 65536)
	for {
		n, err := r.Read(buf)
		if n > 0 {
			chunk := make([]byte, n)
			copy(chunk, buf[:n])
			ch <- chunk
		}
		if err != nil {
			return
		}
	}
}

func (d *daemon) send(s string) error {
	if d.stdin == nil {
		return io.ErrClosedPipe
	}
	_, err := d.stdin.WriteString(s)
	return err
}

// killRepl は repl を畳む。まず入力を閉じて自分で降りてもらい、駄目なら止める。
func (d *daemon) killRepl() {
	if d.cmd == nil {
		return
	}
	if d.stdin != nil {
		d.stdin.Close()
		d.stdin = nil
	}
	if d.gone == nil {
		_ = d.cmd.Process.Kill()
	} else {
		select {
		case <-d.gone:
		case <-time.After(5 * time.Second):
			_ = d.cmd.Process.Kill()
			<-d.gone
		}
	}
	d.cmd = nil
	d.out = nil
	d.gone = nil
}

func (d *daemon) replGone() bool {
	if d.cmd == nil || d.gone == nil {
		return true
	}
	select {
	case <-d.gone:
		return true
	default:
		return false
	}
}

// rssMB は repl が今どれだけメモリを抱えているか。測れない環境では -1。
//
// WhyNot: 測れないときに 0 を返さないのは、0 なら「痩せている」と読めてしまい、
// 上限による立て直しが永久に来なくなるため (-1 は回数の上限に任せる印)。
func (d *daemon) rssMB() int {
	if d.cmd == nil || d.cmd.Process == nil {
		return -1
	}
	// PATH に頼ると make 経由以外の起動で見つからないことがあるので絶対パスを先に見る。
	ps := "ps"
	if isFile("/bin/ps") {
		ps = "/bin/ps"
	}
	out, err := exec.Command(ps, "-p", strconv.Itoa(d.cmd.Process.Pid), "-o", "rss=").Output()
	if err != nil {
		return -1
	}
	kb, err := strconv.Atoi(strings.TrimSpace(string(out)))
	if err != nil {
		return -1
	}
	return kb / 1024
}

// --- 鮮度 (make sync-engine で lib/ の fpkg 実体が差し替わったら作り直す)

func (d *daemon) takeSnapshot() map[string]int64 {
	items := map[string]int64{}
	toml := filepath.Join(d.pkg, "flix.toml")
	items[toml] = mtimeNS(toml)
	seen := map[string]bool{}
	suffixes := d.r.Checkd.Daemon.DepSuffixes
	var walk func(dir string)
	walk = func(dir string) {
		real, err := filepath.EvalSymlinks(dir)
		if err != nil {
			real = dir
		}
		if seen[real] {
			return
		}
		seen[real] = true
		entries, err := os.ReadDir(dir)
		if err != nil {
			return
		}
		for _, e := range entries {
			p := filepath.Join(dir, e.Name())
			// Stat は symlink の先を見る (配った実体の新しさが知りたい)。
			info, err := os.Stat(p)
			if err != nil {
				continue
			}
			if info.IsDir() {
				walk(p)
				continue
			}
			// 依存の実体だけ見る。cache の lock 等まで見ると、無関係な
			// 更新のたびに repl を作り直してしまう。
			for _, s := range suffixes {
				if strings.HasSuffix(e.Name(), s) {
					items[p] = info.ModTime().UnixNano()
					break
				}
			}
		}
	}
	walk(filepath.Join(d.pkg, "lib"))
	return items
}

func mtimeNS(path string) int64 {
	info, err := os.Stat(path)
	if err != nil {
		return 0
	}
	return info.ModTime().UnixNano()
}

func sameSnapshot(a, b map[string]int64) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		if w, ok := b[k]; !ok || w != v {
			return false
		}
	}
	return true
}

func snapshotDiff(now, old map[string]int64) []string {
	var diff []string
	for k, v := range now {
		if w, ok := old[k]; !ok || w != v {
			diff = append(diff, k)
		}
	}
	for k := range old {
		if _, ok := now[k]; !ok {
			diff = append(diff, k)
		}
	}
	if len(diff) > 5 {
		diff = diff[:5]
	}
	return diff
}

// --- 入出力

func (d *daemon) waitFor(marker string, timeout time.Duration) (bool, []byte) {
	deadline := time.Now().Add(timeout)
	var out []byte
	ch := d.out
	for time.Now().Before(deadline) {
		select {
		case chunk, ok := <-ch:
			if !ok {
				return false, out // repl が居なくなった
			}
			out = append(out, chunk...)
			if bytes.Contains(ansi.ReplaceAll(out, nil), []byte(marker)) {
				return true, out
			}
		case <-time.After(250 * time.Millisecond):
		}
	}
	return false, out
}

// settle は書きかけ読みを避けて少し待ち、最新ソースの mtime を返す (持ち越し検出に使う)。
func (d *daemon) settle() float64 {
	// ファイル保存の直後に check すると書きかけを読むことがある。
	// 一番新しい .flix の保存から settleSec 経つまで待つ (古ければ待たない)。
	skip := map[string]bool{}
	for _, s := range d.r.Checkd.Daemon.SkipDirs {
		skip[s] = true
	}
	var newest float64
	_ = filepath.Walk(d.pkg, func(path string, info os.FileInfo, err error) error {
		if err != nil || info == nil {
			return nil
		}
		if info.IsDir() {
			if path != d.pkg && skip[filepath.Base(path)] {
				return filepath.SkipDir
			}
			return nil
		}
		name := info.Name()
		if strings.HasSuffix(name, ".flix") || name == "flix.toml" {
			t := float64(info.ModTime().UnixNano()) / 1e9
			if t > newest {
				newest = t
			}
		}
		return nil
	})
	settle := *d.r.Checkd.Daemon.SettleSec
	wait := settle - (float64(time.Now().UnixNano())/1e9 - newest)
	if wait > 0 && wait <= settle {
		time.Sleep(seconds(wait))
	}
	return newest
}

// scrub は repl の飾り (プロンプト・番兵の応答) を落とし、check の出力だけ残す。
func scrub(raw []byte, sentinel string) string {
	txt := string(ansi.ReplaceAll(raw, nil))
	txt = strings.ReplaceAll(txt, "\r\n", "\n")
	var lines []string
	for _, line := range strings.Split(txt, "\n") {
		// 残った \r は「行頭に戻って上書き」の印。スピナーの描き捨てを消して、
		// その行で最後に描かれた文字だけを残す。
		if i := strings.LastIndex(line, "\r"); i >= 0 {
			line = line[i+1:]
		}
		if strings.Contains(line, sentinel) {
			continue
		}
		line = strings.ReplaceAll(line, "flix> ", "")
		line = strings.ReplaceAll(line, "flix>", "")
		// repl がコンパイル中に出す進捗ドット (=>....) は CLI には無いので削る
		if line != "" && strings.Trim(line, "=>. ") == "" {
			continue
		}
		lines = append(lines, line)
	}
	out := strings.Trim(strings.Join(lines, "\n"), "\n")
	if out == "" {
		return ""
	}
	return out + "\n"
}

// exitCodeOf は CLI と同じ終了コードを出力から復元する。読み取れなければ負 (=素の CLI へ)。
func exitCodeOf(verb, text string) int {
	// ヒープの蓋が足りないと JVM が音を上げる。これは「ソースが悪い」ではないので、
	// 赤として持ち帰らず素の CLI へ投げ直す (蓋の無い JVM なら通る)。
	if strings.Contains(text, "OutOfMemoryError") {
		return -1
	}
	if strings.Contains(text, "Compilation failed") {
		return 1
	}
	if verb == "check" {
		// このバージョンの flix は check のエラーで "Compilation failed" を
		// 出さない。代わりにエラーは "-- Resolution Error [E2136] ----" の
		// ような "-- 〜 Error" 見出しで始まるので、それをマーカーにする。
		if errorHeading.MatchString(text) {
			return 1
		}
		return 0
	}
	// test はまとめ行 (Passed: N, Failed: M.) が唯一の頼り。行が無い出力は
	// 途中で切れた可能性があるので、推測せず素の CLI に投げ直す。
	m := testSummary.FindStringSubmatch(text)
	if m == nil {
		return -1
	}
	if m[2] == "0" {
		return 0
	}
	return 1
}

// doCheck は (終了コード, 出力)。コードが負なら「素の CLI で確かめて」の意味。
func (d *daemon) doCheck(verb string, retried bool) (int, string) {
	t0 := time.Now()
	if d.replGone() {
		d.log("repl が居ないので起動")
		d.killRepl()
		if err := d.startRepl(); err != nil {
			d.log(fmt.Sprintf("%s 失敗: %v", verb, err))
			d.killRepl()
			return -1, ""
		}
	} else if now := d.takeSnapshot(); !sameSnapshot(now, d.snapshot) {
		// 依存の実体が変わった。温めた結果は古い依存で出るので作り直す。
		d.log(fmt.Sprintf("依存が変わったので repl を作り直す: %v", snapshotDiff(now, d.snapshot)))
		d.killRepl()
		if err := d.startRepl(); err != nil {
			d.log(fmt.Sprintf("%s 失敗: %v", verb, err))
			d.killRepl()
			return -1, ""
		}
	}
	srcNewest := d.settle()
	// 前のコマンドの残り (遅れて届いたプロンプト等) を捨てる。
	// 混ざると check の出力に無関係な欠片が載ってしまう。
	for drained := false; !drained; {
		select {
		case _, ok := <-d.out:
			if !ok {
				drained = true
			}
		default:
			drained = true
		}
	}
	d.seq++
	sentinel := fmt.Sprintf("zzz%d", d.seq)
	if err := d.send(fmt.Sprintf(":%s\n:%s\n", verb, sentinel)); err != nil {
		d.log(fmt.Sprintf("%s 失敗: %v", verb, err))
		d.killRepl()
		return -1, ""
	}
	ok, raw := d.waitFor(sentinel, seconds(*d.r.Checkd.Daemon.WorkTimeoutSec))
	if !ok {
		d.log(fmt.Sprintf("%s #%d が番兵まで届かずタイムアウト", verb, d.checks+1))
		d.killRepl()
		return -1, ""
	}
	text := scrub(raw, sentinel)
	code := exitCodeOf(verb, text)
	if code < 0 {
		// 判定できない出力を返すと exit code が嘘になる。repl も疑わしいので捨てる
		d.log(fmt.Sprintf("%s の出力から結果を読み取れない → 素の CLI へ", verb))
		d.killRepl()
		return -1, ""
	}
	d.checks++
	rss := d.rssMB()
	d.log(fmt.Sprintf("%s #%d 完了 exit=%d %.2fs RSS=%dMB",
		verb, d.checks, code, time.Since(t0).Seconds(), rss))
	// 持ち越しの防波堤: ソースが前回の失敗より後に編集されたのに、
	// バイト同一のエラーが返った。repl の増分コンパイルがエラーを
	// 抱え込んだ疑いがあるので、作り直して素の状態で確かめ直す。
	// 本当に直っていなければ再検査も同じエラーで、結果は変わらない。
	if code == 1 && !retried && d.hasPrevFail &&
		text == d.prevFail && srcNewest > d.prevFailTime {
		d.log("編集後も同一エラー — repl の持ち越しを疑い、作り直して確かめる")
		d.killRepl()
		d.hasPrevFail = false
		return d.doCheck(verb, true)
	}
	if code == 1 {
		d.prevFail, d.prevFailTime, d.hasPrevFail = text, srcNewest, true
	} else {
		d.hasPrevFail = false
	}
	// :test は 1 回で数百 MB 増えることがある。上限超えは次回の作り直しに
	// 回さず、その場で使い捨てて漏れを持ち越さない。
	if d.checks >= *d.r.Checkd.Daemon.MaxChecks || rss > d.rssLimitMB {
		d.log("repl を使い捨てる (回数か RSS の上限)")
		d.killRepl()
	}
	return code, text
}

// --- 本体ループ

func respond(conn net.Conn, code int, body string) {
	_, _ = io.WriteString(conn, fmt.Sprintf("RES %d %d\n%s", code, len(body), body))
}

func (d *daemon) loop() {
	idle := idleSec(d.r)
	convTimeout := seconds(*d.r.Checkd.Daemon.ConvTimeoutSec)
	for {
		if tl, ok := d.ln.(*net.TCPListener); ok {
			_ = tl.SetDeadline(time.Now().Add(idle))
		}
		conn, err := d.ln.Accept()
		if err != nil {
			return // 誰も来ないなら消える。溜まった常駐でマシンを重くしない
		}
		_ = conn.SetDeadline(time.Now().Add(convTimeout))
		command := readCommand(conn)
		switch command {
		case "CHECK", "TEST":
			_ = conn.SetDeadline(time.Time{})
			code, body := d.doCheck(strings.ToLower(command), false)
			respond(conn, code, body)
		case "PING":
			respond(conn, 0, "")
		case "STOP":
			respond(conn, 0, "")
			conn.Close()
			return
		default:
			respond(conn, -1, "")
		}
		conn.Close()
	}
}

func readCommand(conn net.Conn) string {
	var data []byte
	buf := make([]byte, 4096)
	for !bytes.Contains(data, []byte("\n")) {
		n, err := conn.Read(buf)
		if n > 0 {
			data = append(data, buf[:n]...)
		}
		if err != nil {
			break
		}
	}
	line, _, _ := bytes.Cut(data, []byte("\n"))
	return strings.TrimSpace(string(line))
}

func (d *daemon) shutdown() {
	d.killRepl()
	if d.ln != nil {
		d.ln.Close()
	}
	d.releasePidFile()
}
