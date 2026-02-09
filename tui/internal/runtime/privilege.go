package runtime

import (
	"fmt"
	"os"
)

func IsRoot() bool {
	return os.Geteuid() == 0
}

func RequireRoot(action string) error {
	if IsRoot() {
		return nil
	}
	return fmt.Errorf("%s requires root privileges; rerun with sudo auto-ssl-tui", action)
}
