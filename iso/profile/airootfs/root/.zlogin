# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

~/.automated_script.sh

# The installer starts by itself on the first console (issue #124). A
# serial console, an SSH login and a second virtual console get the shell;
# so does this one once the installer stops or fails.
if [[ $(tty) == /dev/tty1 ]] && ! grep -qw 'script=' /proc/cmdline; then
    # The graphics driver may still be loading; when it takes the console
    # over, the font and size change under the installer.
    udevadm settle --timeout=10
    subarchy-setup
fi
