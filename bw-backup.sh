#!/bin/zsh

# Automated Bitwarden Backup Script

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
SCRIPT_DIR=${0:a:h}
ENV_FILE="$SCRIPT_DIR/.env"

die_gui() {
    local TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$TIMESTAMP] [FATAL] $1" >>"$LOG_FILE"
    osascript - "$1" <<'EOF' >/dev/null 2>&1
on run argv
    display dialog (item 1 of argv) with title "Minimalistic Bitwarden Backup Tool" ¬
        buttons {"OK"} default button "OK" with icon stop
end run
EOF
    exit 1
}

kill_spinner() {
    [ -n "$1" ] || return
    [[ "$(ps -p "$1" -o comm= 2>/dev/null)" == *osascript* ]] && kill "$1" 2>/dev/null
}

# source variables from .env
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    die_gui ".env file is missing. Process aborted."
fi

# set default values if not found in .env
: ${LOG_FILE:="$HOME/Library/Logs/bw-backup.log"}
: ${BACKUP_DIR:="$HOME/Backups/Bitwarden"}
: ${MAX_ATTEMPTS:=5}
: ${KEEP_LAST_N:=3}

log_message() {
    local LOG_LEVEL="$1"
    local MESSAGE="$2"
    # Format: YYYY-MM-DD HH:MM:SS
    local TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

    echo "[$TIMESTAMP] [$LOG_LEVEL] $MESSAGE" | tee -a "$LOG_FILE"
}

notify() {
    local title="$1" msg="$2" exec_cmd="${3:-}"
    if command -v terminal-notifier >/dev/null 2>&1; then
        if [ -n "$exec_cmd" ]; then
            terminal-notifier -title "$title" -message "$msg" -execute "$exec_cmd"
        else
            terminal-notifier -title "$title" -message "$msg"
        fi
    else
        osascript -e "display notification \"$msg\" with title \"$title\"" >/dev/null 2>&1
        log_message "WARNING" "terminal-notifier not found, fell back to native notification."
    fi
}

# add permission to backup directory
umask 077
mkdir -p "${LOG_FILE:h}" && touch "$LOG_FILE" && chmod 600 "$LOG_FILE"

log_message "INFO" "-----New backup session begins-----"

# dependency checks
command -v bw >/dev/null 2>&1 || die_gui "Bitwarden CLI not found. Install it with: brew install bitwarden-cli"
command -v osascript >/dev/null 2>&1 || die_gui "osascript missing."

# log setup
log_message "INFO" "bw version: $(bw --version 2>&1)"
command -v terminal-notifier >/dev/null 2>&1 &&
    log_message "INFO" "terminal-notifier: $(command -v terminal-notifier)" ||
    log_message "INFO" "terminal-notifier"

# check env variables
[ -n "$BW_CLIENTID" ] && [ -n "$BW_CLIENTSECRET" ] ||
    die_gui "Bitwarden API credentials are missing in .env"

# make backup setup
mkdir -p "$BACKUP_DIR" 2>/dev/null ||
    die_gui "Cannot create backup directory: $BACKUP_DIR"
chmod 700 "$BACKUP_DIR" 2>/dev/null

export BACKUP_FILE="$BACKUP_DIR/Bitwarden-Backup-$(date '+%Y-%m-%d-%H%M%S').json"
TMP_FILE="${BACKUP_FILE}.part"

CLEANED=0
cleanup() {
    [ "$CLEANED" -eq 1 ] && return
    CLEANED=1
    [ -n "${TMP_FILE:-}" ] && rm -f "$TMP_FILE" 2>/dev/null
    [ -n "${PW_FILE:-}" ] && rm -P -f "$PW_FILE" 2>/dev/null
    kill_spinner "${SPINNER_PID:-}"
    kill_spinner "${BACKUP_PID:-}"
    unset BW_PASSWORD BW_SESSION BW_CLIENTID BW_CLIENTSECRET
    bw logout >/dev/null 2>&1
    log_message "INFO" "--- cleanup done ---"
}
trap cleanup EXIT INT TERM

osascript -e 'display alert "Bitwarden Password Backup" message "You are about to backup your Bitwarden passwords.\n\nClick Proceed to enter your Master Password, or Cancel to skip." buttons {"Cancel", "Proceed"} default button "Proceed" cancel button "Cancel"' >>"$LOG_FILE"

if [ $? -ne 0 ]; then
    log_message "INFO" "User clicked Cancel on the dialog. Exiting."
    exit 0
fi

# spinner dialog when logging in
osascript -e 'display dialog "Logging in to Bitwarden...\nThis may take a few seconds." with title "Minimalistic Bitwarden Backup Tool" buttons {"Processing..."} default button 1 with icon note giving up after 600' >/dev/null 2>&1 &
SPINNER_PID=$!

bw login --apikey >>"$LOG_FILE" 2>&1
LOGIN_EXIT_CODE=$?

kill_spinner "$SPINNER_PID"

if [ $LOGIN_EXIT_CODE -eq 1 ]; then
    die_gui "client_id or client_secret is incorrect. Please check your .env settings. Process aborted."
elif [ $LOGIN_EXIT_CODE -ne 0 ]; then
    die_gui "Login failed with exit code $LOGIN_EXIT_CODE."
fi

# prompt message assembly
BW_EMAIL=$(bw status 2>/dev/null | sed -n 's/.*"userEmail":"\([^"]*\)".*/\1/p')
LAST_BACKUP=$(ls -t "$BACKUP_DIR"/Bitwarden-Backup-*.json 2>/dev/null | head -1)
if [ -n "$LAST_BACKUP" ]; then
    LAST_DATE=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$LAST_BACKUP")
else
    LAST_DATE="(no previous backup)"
fi

if [ -n "$SAFETY_PHRASE" ]; then
    HEADER="Safety Phrase: $SAFETY_PHRASE"
else
    HEADER="Warning: SAFETY_PHRASE not set — see README"
fi

PROMPT_TEXT="$HEADER

Account: ${BW_EMAIL:-unknown}
Last backup: $LAST_DATE
Backing up to: $BACKUP_DIR

Enter your master password:"

# handle master password authentication and session key issue
ATTEMPT=1
SESSION_RETRY=0
while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    BW_PASSWORD=$(osascript -e "display dialog \"$PROMPT_TEXT\" default answer \"\" with title \"Minimalistic Bitwarden Backup Tool\" with icon caution with hidden answer" -e "text returned of result" 2>>"$LOG_FILE")
    DIALOG_EXIT=$?
    export BW_PASSWORD
    if [ $DIALOG_EXIT -ne 0 ]; then
        log_message "INFO" "Process cancelled by user."
        exit 0
    fi

    BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>>"$LOG_FILE")
    EXIT_CODE=$?

    # invalid master password, accumulate attempts
    if [ "$EXIT_CODE" -eq 1 ]; then
        if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
            osascript -e 'display dialog "Too many incorrect attempts. Backup Aborted." buttons {"OK"} default button "OK" with icon stop'
            log_message "ERROR" "Process terminated due to too many failed attempts."
            exit 1
        fi

        REMAINING=$((MAX_ATTEMPTS - ATTEMPT))
        PROMPT_TEXT="Incorrect password. ($REMAINING attempts remaining)\n\nPlease try again:"
        log_message "INFO" "Invalid Password. Attempts ($ATTEMPT / $MAX_ATTEMPTS)."
        ((ATTEMPT++))
        continue

    # other possible errors
    elif [ "$EXIT_CODE" -ne 0 ]; then
        log_message "ERROR" "Unlock failed. Error message from Bitwarden: $BW_SESSION"
        exit 1
    fi

    # sometimes Bitwarden doesn't provide the session key even when the exit code is 0
    # this block checks for an empty session key and reprompt login.
    if [ -z "$BW_SESSION" ]; then
        ((SESSION_RETRY++))
        if [ $SESSION_RETRY -gt 3 ]; then
            log_message "ERROR" "Bitwarden repeatedly returned an empty session. Peocess aborted."
            die_gui "Bitwarden repeatedly returned an empty session, Aborting."
        fi
        log_message "ERROR" "BW_SESSION not found. Retry login..."
        log_message "ERROR" "$(bw status 2>&1)"
        osascript -e 'display dialog "Bitwarden session key not found. Retry login. Click OK to try again or Cancel to abort." buttons {"Cancel", "OK"} default button "OK" cancel button "Cancel" with icon stop' >>"$LOG_FILE"
        if [ $? -ne 0 ]; then
            log_message "INFO" "Process cancelled by user."
            exit 0
        fi
        bw login --apikey >>"$LOG_FILE" 2>&1
        continue
    fi

    # if nothing goes wrong, export the session key for later use.
    export BW_SESSION
    break
done

unset BW_CLIENTID
unset BW_CLIENTSECRET

osascript -e 'display dialog "Authentication succeeded. Backup has started. You will be notified when the process is completed. You can close this dialog." with title "Minimalistic Bitwarden Backup Tool" buttons {"OK"} default button "OK" with icon note' >/dev/null 2>&1 &
BACKUP_PID=$!

# export to encrypted json file protected by the master password
bw export --format encrypted_json --password "$BW_PASSWORD" --output "$TMP_FILE" 2>>"$LOG_FILE"
EXPORT_EXIT_CODE=$?

# check the content
if [ $EXPORT_EXIT_CODE -eq 0 ] && [ -s "$TMP_FILE" ] &&
    grep -q '"encrypted"' "$TMP_FILE"; then
    chmod 600 "$TMP_FILE"
    mv -f "$TMP_FILE" "$BACKUP_FILE"
else
    rm -f "$TMP_FILE"
    EXPORT_EXIT_CODE=1
fi

# count bakcup items and warn about potentially lost items
ITEM_COUNT=$(bw list items | grep -o '"object":"item"' | wc -l | tr -d ' ')
log_message "INFO" "Vault contains $ITEM_COUNT items."

# handle potential export errors
if [ $EXPORT_EXIT_CODE -eq 0 ]; then
    log_message "INFO" "Backup completed. Backup file stored at $BACKUP_FILE"
else
    log_message "ERROR" "Backup failed."
    kill_spinner "$BACKUP_PID"
    die_gui "Backup failed."
fi

# cd to the backup directory. stop immediately if directory not found to prevent unexpected deletion.
cd "$BACKUP_DIR" || {
    log_meesage "ERROR" "Cannot find backup directory. Process aborted."
    kill_spinner "$BACKUP_PID"
    die_gui -"Cannot find backup directory. Process aborted."
}

# keep the last n files and delete older backups
if [[ ! "$KEEP_LAST_N" =~ ^[0-9]+$ ]] || [ "$KEEP_LAST_N" -lt 1 ]; then
    log_message "WARNING" "Invalid KEEP_LAST_N ('$KEEP_LAST_N'), fallback to 3."
    KEEP_LAST_N=3
fi

TAIL_START=$(($KEEP_LAST_N + 1))
ls -t Bitwarden-Backup-*.json 2>/dev/null | tail -n +$TAIL_START | while IFS= read -r f; do
    rm -- "$f" && log_message "INFO" "Rotated out: $f"
done

kill_spinner "$BACKUP_PID"

# notify user about completion
notify "Minimalistic Bitwarden Backup Tool" "Backup complete ($ITEM_COUNT items are stored to $BACKUP_FILE).  Click to open the backup folder." "open '$BACKUP_DIR'"
