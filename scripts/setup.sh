#!/bin/zsh
# One-time setup: lets your user run exactly these two commands without a password,
#   /usr/bin/pmset -a disablesleep 0
#   /usr/bin/pmset -a disablesleep 1
# Usage: sudo scripts/setup.sh [install|uninstall]
set -euo pipefail

rule_file=/etc/sudoers.d/sleep-manager
action=${1:-install}

if [[ $EUID -ne 0 ]]; then
    echo "Run it with sudo: sudo $0 $action" >&2
    exit 1
fi
user=${SUDO_USER:-}
if [[ -z $user || $user == root ]]; then
    echo "Run this with sudo from your own account, not as root." >&2
    exit 1
fi
if [[ ! $user =~ '^[A-Za-z0-9._-]+$' ]]; then
    echo "Unexpected user name '$user'; not writing a sudoers rule for it." >&2
    exit 1
fi

case $action in
install)
    if ! grep -qE '^[#@]includedir /private/etc/sudoers.d' /etc/sudoers; then
        echo "/etc/sudoers doesn't include /etc/sudoers.d, so the rule would have no effect." >&2
        exit 1
    fi
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<RULE
# Installed by Sleep Manager. Remove with: sudo scripts/setup.sh uninstall
$user ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
RULE
    visudo -cf "$tmp"
    install -m 0440 -o root -g wheel "$tmp" "$rule_file"
    visudo -c >/dev/null
    echo "Installed $rule_file for $user."
    ;;
uninstall)
    rm -f "$rule_file"
    echo "Removed $rule_file."
    ;;
*)
    echo "Usage: sudo $0 [install|uninstall]" >&2
    exit 1
    ;;
esac
