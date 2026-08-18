//go:build !windows

package checkd

import (
	"os"
	"syscall"
)

// terminate は行儀よく終わってくれと頼む。
func terminate(proc *os.Process) error {
	return proc.Signal(syscall.SIGTERM)
}
