# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

~/.automated_script.sh

# The installer starts by itself on the first console (issue #124). A
# serial console, an SSH login and a second virtual console get the shell;
# so does this one once the installer stops or fails.
if [[ $(tty) == /dev/tty1 ]] && ! grep -qw 'script=' /proc/cmdline; then
    subarchy-setup
fi
