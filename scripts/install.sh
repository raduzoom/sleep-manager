#!/bin/zsh
# Installs Sleep Manager to /Applications and starts it at every login.
# Usage: scripts/install.sh [install|uninstall]
# The password rule is separate: sudo scripts/setup.sh [install|uninstall]
set -euo pipefail
cd "${0:A:h}/.."

app=/Applications/SleepManager.app
label=local.sleep-manager
agent=~/Library/LaunchAgents/$label.plist
domain=gui/$(id -u)

quit_running() {
    pkill -x SleepManager 2>/dev/null || true
    sleep 1
}

case ${1:-install} in
install)
    ./scripts/build.sh
    quit_running
    rm -rf "$app"
    cp -R build/SleepManager.app "$app"

    # A login item that opens the app once at login. No KeepAlive, so quitting it sticks.
    mkdir -p "${agent:h}"
    cat > "$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>$app</string>
    </array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
    plutil -lint "$agent" >/dev/null

    # Loading the agent runs it once now, which also starts the app.
    launchctl bootout "$domain/$label" 2>/dev/null || true
    launchctl bootstrap "$domain" "$agent"
    echo "Installed $app and the login item."
    if ! /usr/bin/sudo -n -l /usr/bin/pmset -a disablesleep 1 >/dev/null 2>&1; then
        echo "Lid Closed Mode still needs the one-time setup: sudo scripts/setup.sh"
    fi
    ;;
uninstall)
    launchctl bootout "$domain/$label" 2>/dev/null || true
    rm -f "$agent"
    quit_running
    rm -rf "$app"
    echo "Removed $app and the login item."
    if [[ -e /etc/sudoers.d/sleep-manager ]]; then
        echo "To remove the password rule too: sudo scripts/setup.sh uninstall"
    fi
    ;;
*)
    echo "Usage: $0 [install|uninstall]" >&2
    exit 1
    ;;
esac
