//go:build windows

package checkd

import "os"

// terminate は相手を止める。
//
// WhyNot: SIGTERM を送らないのは、Windows にその仕組みが無く os.Process.Signal が
// 「対応していない」を返すだけで相手が止まらないため。
func terminate(proc *os.Process) error {
	return proc.Kill()
}
