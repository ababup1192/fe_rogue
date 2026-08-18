//go:build windows

package hooks

import (
	"os/exec"
	"syscall"
)

// detach は起こす子を親のコンソールから切り離す。
// WhyNot: そのまま起こすと常駐のたびにコンソールの窓が開き、Ctrl-C が子へも届く。
func detach(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{
		CreationFlags: syscall.CREATE_NEW_PROCESS_GROUP | 0x08000000, // CREATE_NO_WINDOW
	}
}
