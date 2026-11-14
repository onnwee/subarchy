package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"git.subcult.tv/subculture-collective/subarchy/internal/atomicfile"
	"git.subcult.tv/subculture-collective/subarchy/internal/systheme"
)

const screensUsage = "Usage: subcult theme screens [set [--boot SET] [--login SET] [--lock SET] | add [--replace] <name> <folder>]"

// shippedSets are the package's art sets; `screens add` does not shadow them.
var shippedSets = map[string]bool{"subcult": true, "subarchy": true}

func (a *app) screens(args []string) int {
	if len(args) == 0 {
		return a.screensShow()
	}
	switch args[0] {
	case "set":
		return a.screensSet(args[1:])
	case "add":
		return a.screensAdd(args[1:])
	}
	fmt.Fprintln(a.stderr, screensUsage)
	return 2
}

func (a *app) screensShow() int {
	user, err := a.userScreens()
	if err != nil {
		fmt.Fprintf(a.stderr, "subcult theme screens: %s: %v\n", a.screensPath(), err)
		return 1
	}
	s := user.WithDefaults()
	for _, row := range [][3]string{{"boot", s.Boot, user.Boot}, {"login", s.Login, user.Login}, {"lock", s.Lock, user.Lock}} {
		note := ""
		if row[2] == "" {
			note = " (default)"
		}
		fmt.Fprintf(a.stdout, "%-6s %s%s\n", row[0], row[1], note)
	}
	fmt.Fprintln(a.stdout)
	fmt.Fprintln(a.stdout, "art sets:")
	for _, name := range systheme.ScreenSets(a.root) {
		var has []string
		for _, f := range systheme.ScreenFiles {
			if _, _, ok, err := systheme.ScreenFile(a.root, name, f); ok && err == nil {
				has = append(has, strings.TrimSuffix(strings.TrimSuffix(f, ".png"), ".txt"))
			}
		}
		fmt.Fprintf(a.stdout, "  %-12s %s\n", name, strings.Join(has, ", "))
	}
	return 0
}

func (a *app) screensSet(args []string) int {
	fs := flag.NewFlagSet("subcult theme screens set", flag.ContinueOnError)
	fs.SetOutput(a.stderr)
	boot := fs.String("boot", "", "art set for the boot splash and boot menu")
	login := fs.String("login", "", "art set for the login screen")
	lock := fs.String("lock", "", "art set for the lock screen")
	if err := fs.Parse(args); err != nil || fs.NArg() != 0 {
		fmt.Fprintln(a.stderr, screensUsage)
		return 2
	}
	if *boot == "" && *login == "" && *lock == "" {
		fmt.Fprintln(a.stderr, "subcult theme screens set: name at least one of --boot, --login, --lock")
		return 2
	}
	s, err := a.userScreens()
	if err != nil {
		fmt.Fprintf(a.stderr, "subcult theme screens: %s: %v\n", a.screensPath(), err)
		return 1
	}
	sets := map[string]bool{}
	for _, n := range systheme.ScreenSets(a.root) {
		sets[n] = true
	}
	for _, c := range []struct {
		val  string
		dst  *string
		file string
	}{{*boot, &s.Boot, "boot.png"}, {*login, &s.Login, "login.png"}, {*lock, &s.Lock, "lock.png"}} {
		if c.val == "" {
			continue
		}
		if !sets[c.val] {
			fmt.Fprintf(a.stderr, "subcult theme screens set: no art set %q (subcult theme screens lists them)\n", c.val)
			return 1
		}
		if _, _, ok, err := systheme.ScreenFile(a.root, c.val, c.file); err != nil {
			fmt.Fprintf(a.stderr, "subcult theme screens set: %v\n", err)
			return 1
		} else if !ok {
			fmt.Fprintf(a.stdout, "note: %s has no %s; that screen keeps its packaged art\n", c.val, c.file)
		}
		*c.dst = c.val
	}
	data, _ := json.MarshalIndent(s, "", "  ")
	if err := atomicfile.Write(a.screensPath(), append(data, '\n'), 0o644); err != nil {
		fmt.Fprintf(a.stderr, "subcult theme screens set: %v\n", err)
		return 1
	}
	fmt.Fprintln(a.stdout, "wrote", a.screensPath())
	if *boot != "" || *login != "" {
		fmt.Fprintln(a.stdout, "run subcult theme apply-system to carry it to the boot and login screens")
	}
	if *lock != "" {
		fmt.Fprintln(a.stdout, "the lock screen uses it the next time it locks")
	}
	return 0
}

func (a *app) screensAdd(args []string) int {
	fs := flag.NewFlagSet("subcult theme screens add", flag.ContinueOnError)
	fs.SetOutput(a.stderr)
	replace := fs.Bool("replace", false, "replace a set added before")
	if err := fs.Parse(args); err != nil || fs.NArg() != 2 {
		fmt.Fprintln(a.stderr, "Usage: sudo subcult theme screens add [--replace] <name> <folder>")
		return 2
	}
	name, src := fs.Arg(0), fs.Arg(1)
	if !systheme.ValidSetName(name) {
		fmt.Fprintf(a.stderr, "subcult theme screens add: %q is not a set name (a-z, 0-9 and -, up to 32)\n", name)
		return 2
	}
	if shippedSets[name] {
		fmt.Fprintf(a.stderr, "subcult theme screens add: %s is a shipped set; choose another name\n", name)
		return 2
	}
	if a.root == "/" && a.euid() != 0 {
		fmt.Fprintln(a.stderr, "subcult theme screens add: run it with sudo: the boot and login screens read the set as root")
		return 1
	}
	dst := filepath.Join(a.root, systheme.ScreensLocalDir, name)
	if _, err := os.Stat(dst); err == nil && !*replace {
		fmt.Fprintf(a.stderr, "subcult theme screens add: /%s exists; add --replace to replace it\n", filepath.Join(systheme.ScreensLocalDir, name))
		return 1
	}
	files := map[string][]byte{}
	for _, f := range systheme.ScreenFiles {
		p := filepath.Join(src, f)
		fi, err := os.Stat(p)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			fmt.Fprintf(a.stderr, "subcult theme screens add: %v\n", err)
			return 1
		}
		if !fi.Mode().IsRegular() || fi.Size() > systheme.MaxScreenImage {
			fmt.Fprintf(a.stderr, "subcult theme screens add: %s: not a regular file of up to %d MiB\n", p, systheme.MaxScreenImage>>20)
			return 1
		}
		data, err := os.ReadFile(p)
		if err != nil {
			fmt.Fprintf(a.stderr, "subcult theme screens add: %v\n", err)
			return 1
		}
		if strings.HasSuffix(f, ".png") {
			err = systheme.CheckScreenImage(data)
		} else {
			var t string
			t, err = systheme.CheckScreenTitle(data)
			data = []byte(t + "\n")
		}
		if err != nil {
			fmt.Fprintf(a.stderr, "subcult theme screens add: %s: %v\n", p, err)
			return 1
		}
		files[f] = data
	}
	if len(files) == 0 {
		fmt.Fprintf(a.stderr, "subcult theme screens add: %s has none of %s\n", src, strings.Join(systheme.ScreenFiles, ", "))
		return 1
	}
	if err := os.RemoveAll(dst); err != nil {
		fmt.Fprintf(a.stderr, "subcult theme screens add: %v\n", err)
		return 1
	}
	for f, data := range files {
		if err := atomicfile.Write(filepath.Join(dst, f), data, 0o644); err != nil {
			fmt.Fprintf(a.stderr, "subcult theme screens add: %v\n", err)
			return 1
		}
		fmt.Fprintln(a.stdout, "wrote", "/"+filepath.Join(systheme.ScreensLocalDir, name, f))
	}
	fmt.Fprintf(a.stdout, "choose it with: subcult theme screens set --boot %s (or --login, --lock)\n", name)
	return 0
}
