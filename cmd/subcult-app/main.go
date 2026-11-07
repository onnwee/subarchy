// Command subcult-app serves `subcult app ...`: it lists the app catalogue,
// installs and removes apps, and sets the default app per role (ADR 0044).
package main

import (
	"os"

	"git.subcult.tv/subculture-collective/subarchy/internal/apps"
)

func main() {
	cli := &cli{
		stdout: os.Stdout,
		stderr: os.Stderr,
		paths:  apps.DefaultPaths,
		run:    runStep,
	}
	os.Exit(cli.main(os.Args[1:]))
}
