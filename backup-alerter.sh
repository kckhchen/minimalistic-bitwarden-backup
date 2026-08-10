#!/bin/zsh
export SCRIPT_DIR=${0:a:h}
export ENV_FILE="$SCRIPT_DIR/.env"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

terminal-notifier -title "Minimalistic Bitwarden Backup Reminder" -message "It's time to backup your vault. Click to start the backup process" -execute "$SCRIPT_DIR/bw-backup.sh" || echo "$(date): Notification failed" >>/tmp/bw-backup-alerter.log

