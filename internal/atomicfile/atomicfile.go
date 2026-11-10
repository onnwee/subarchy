// Package atomicfile replaces a file's contents in one step, so a reader or
// a crash never sees half of it.
package atomicfile

import (
	"os"
	"path/filepath"
)

// Write puts data at path with the given mode, creating the folder.
//
// The data goes to a temporary file of its own beside the destination, is
// flushed to disk and renamed over it. Two writers at once (a timer and a
// command) each rename a whole file; with a shared temporary name one could
// rename the other's half-written data. A path that is a symbolic link, as
// dotfile managers make, stays a link: the file it points at is replaced.
func Write(path string, data []byte, perm os.FileMode) error {
	if target, err := filepath.EvalSymlinks(path); err == nil {
		path = target
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	f, err := os.CreateTemp(dir, "."+filepath.Base(path)+".*")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp) // gone already once renamed
	if _, err = f.Write(data); err == nil {
		err = f.Chmod(perm)
	}
	if err == nil {
		err = f.Sync()
	}
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
