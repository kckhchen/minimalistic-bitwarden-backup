#!/bin/zsh
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export SCRIPT_DIR=${0:a:h}
export ENV_FILE="$SCRIPT_DIR/.env"

echo "Setting up the tool..."

# check dependencies
REQUIRED_TOOLS=("bw" "terminal-notifier")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v $tool &>/dev/null; then
        echo "Error: '$tool' is not installed or not in PATH."
        exit 1
    fi
done

# check .env configurations
if [ -f "$ENV_FILE" ]; then
    # protect .env file and make scripts executable
    chmod 600 "$ENV_FILE" 2>/dev/null
    chmod +x "$SCRIPT_DIR/backup-alerter.sh"
    chmod +x "$SCRIPT_DIR/bw-backup.sh"

    # load env variables
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "ERROR: Configuration file (.env) is missing."
    echo "Please copy .env.example to .env (cp ./.env.example ./.env) and edit it."
    exit 1
fi

# check api keys
if [ -z "$BW_CLIENTID" ] || [ -z "$BW_CLIENTSECRET" ]; then
    echo "ERROR: Bitwarden API credentials are missing in .env"
    exit 1
fi

# create backup directory
if [ -n "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
else
    echo "Backup directory variable is empty in .env."
    exit 1
fi

# make .zshrc alias
ALIAS_LINE="alias bw-backup=\"$SCRIPT_DIR/bw-backup.sh\""
RC_FILE="$HOME/.zshrc"

if grep -Fxq "$ALIAS_LINE" "$RC_FILE"; then
    echo "Alias 'bw-backup' already exists in $RC_FILE"
else
    read -q "REPLY?Would you like to add 'bw-backup' as a shortcut command? [y/n] "
    echo ""

    if [[ "$REPLY" == "y" ]]; then
        echo "" >>"$RC_FILE"
        echo "# Bitwarden Backup Tool Shortcut" >>"$RC_FILE"
        echo "$ALIAS_LINE" >>"$RC_FILE"

        echo "Installed! Restart your terminal or run: source $RC_FILE"
        echo "You can now type 'bw-backup' anywhere to run this tool."
        echo "If you plan to move the script folder to another directory, please remember to change the alias setting in ~/.zshrc accordingly."
    else
        echo "Skipping alias setup."
    fi
fi

echo "Setup completed!"
