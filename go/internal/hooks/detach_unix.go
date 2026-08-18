//go:build !windows

package hooks

import (
	"os/exec"
	"syscall"
)

// detach は起こす子を親のセッションから切り離す。
// WhyNot: 同じセッションに残すと、フックの終了時に届く合図を子まで受け取り、
// 温めたばかりの常駐がその場で死ぬため。
func detach(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
}
