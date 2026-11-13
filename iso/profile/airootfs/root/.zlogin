# fix for screen readers
if grep -Fqa 'accessibility=' /proc/cmdline &> /dev/null; then
    setopt SINGLE_LINE_ZLE
fi

~/.automated_script.sh

# The installer starts by itself on the first console (issue #124). A
# serial console, an SSH login and a second virtual console get the shell;
# so does this one once the installer stops or fails.
if [[ $(tty) == /dev/tty1 ]] && ! grep -qw 'script=' /proc/cmdline; then
    # This screen is /dev/console, so systemd's status lines show the boot's
    # progress here; units still starting would print over the installer,
    # so turn them off (SIGRTMIN+21, systemd(1)). The boot's messages and
    # the login's motd stay on the screen until the installer draws; clear
    # them so the installer is the first thing seen.
    /usr/bin/kill -s RTMIN+21 1 2>/dev/null
    printf '\e[H\e[2J'
    # The graphics driver may still be loading; when it takes the console
    # over, the font and size change under the installer.
    udevadm settle --timeout=10
    subarchy-setup
    # The shell the installer leaves behind gets the help it cleared.
    cat /etc/motd
fi
