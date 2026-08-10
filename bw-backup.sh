#!/bin/zsh

# Automated Bitwarden Backup Script

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
SCRIPT_DIR=${0:a:h}
ENV_FILE="$SCRIPT_DIR/.env"
ATTEMPT=1

# source variables from .env
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    osascript -e 'display dialog ".env file is missing. Process aborted." with title "Minimalistic Bitwarden Backup Tool" buttons {"OK"} default button "OK" with icon stop' >/dev/null 2>&1
    exit 1
fi

# set default values if not found in .env
: ${LOG_FILE:="/tmp/bw-backup.log"}
: ${BACKUP_DIR:="$HOME/Backups/Bitwarden"}
: ${MAX_ATTEMPTS:=5}
: ${KEEP_LAST_N:=3}

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
echo "------- Log timestamp: $TIMESTAMP -------" >>"$LOG_FILE"
export BACKUP_FILE="$BACKUP_DIR/Bitwarden-Backup-$(date '+%Y-%m-%d_%H%M%S').json"
TMP_FILE="${BACKUP_FILE}.part"

osascript -e 'display alert "Bitwarden Password Backup" message "You are about to backup your Bitwarden passwords.\n\nClick Proceed to enter your Master Password, or Cancel to skip." buttons {"Cancel", "Proceed"} default button "Proceed" cancel button "Cancel"' >>"$LOG_FILE"

if [ $? -ne 0 ]; then
    echo "User clicked Cancel on the dialog. Exiting." >>"$LOG_FILE"
    exit 0
fi

# prevent error caused by previous login
bw logout >/dev/null 2>&1

# spinner dialog when logging in
osascript -e 'display dialog "Logging in to Bitwarden...\nThis may take a few seconds." with title "Minimalistic Bitwarden Backup Tool" buttons {"Processing..."} default button 1 with icon note giving up after 30' >/dev/null 2>&1 &
SPINNER_PID=$!

bw login --apikey >>"$LOG_FILE" 2>&1 && echo "" >>"$LOG_FILE"
LOGIN_EXIT_CODE=$?

if [ $LOGIN_EXIT_CODE -eq 1 ]; then
    kill "$SPINNER_PID" 2>/dev/null
    osascript -e 'display dialog "client_id or client_secret is incorrect. Please check your .env settings. Process aborted." with title "Minimalistic Bitwarden Backup Tool" buttons {"OK"} default button "OK" with icon stop' >/dev/null
    exit 1
elif [ $LOGIN_EXIT_CODE -ne 0 ]; then
    kill "$SPINNER_PID" 2>/dev/null
    osascript -e "display dialog \"Login failed with exit code $LOGIN_EXIT_CODE.\" with title \"Minimalistic Bitwarden Backup Tool\" buttons {\"OK\"} default button \"OK\" with icon stop" >/dev/null
    exit 1
fi

kill "$SPINNER_PID" 2>/dev/null

PROMPT_TEXT="Please enter your master password below."

# handle master password authentication and session key issue

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do

    BW_PASSWORD=$(osascript -e "display dialog \"$PROMPT_TEXT\" default answer \"\" with title \"Minimalistic Bitwarden Backup Tool\" with icon caution with hidden answer" -e "text returned of result" 2>>"$LOG_FILE")
    DIALOG_EXIT=$?
    export BW_PASSWORD
    if [ $DIALOG_EXIT -ne 0 ]; then
        echo "Process cancelled by user." >>"$LOG_FILE"
        bw logout >>"$LOG_FILE" 2>&1 && echo "" >>"$LOG_FILE"
        exit 1
    fi

    BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>&1)
    EXIT_CODE=$?

    # invalid master password, accumulate attempts
    if [ "$EXIT_CODE" -eq 1 ]; then
        if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
            osascript -e 'display dialog "Too many incorrect attempts. Backup Aborted." buttons {"OK"} default button "OK" with icon stop'
            echo "Process terminated due to too many failed attempts." >>"$LOG_FILE"
            bw logout >>"$LOG_FILE" 2>&1 && echo "" >>"$LOG_FILE"
            exit 1
        fi

        REMAINING=$((MAX_ATTEMPTS - ATTEMPT))
        PROMPT_TEXT="Incorrect password. ($REMAINING attempts remaining)\n\nPlease try again:"
        echo "Invalid Password. Attempts ($ATTEMPT / $MAX_ATTEMPTS)." >>"$LOG_FILE"
        ((ATTEMPT++))
        continue

    # other possible errors
    elif [ "$EXIT_CODE" -ne 0 ]; then
        echo "Unlock failed. Error message from Bitwarden: $BW_SESSION" >>"$LOG_FILE"
        bw logout >>"$LOG_FILE" 2>&1 && echo "" >>"$LOG_FILE"
        exit 1
    fi

    # sometimes Bitwarden doesn't provide the session key even when the exit code is 0
    # this block checks for an empty session key and reprompt login.
    if [ -z "$BW_SESSION" ]; then
        echo "BW_SESSION not found. Retry login..." >>$LOG_FILE
        osascript -e 'display dialog "Bitwarden session key not found. Retry login. Click OK to try again or Cancel to abort." buttons {"Cancel", "OK"} default button "OK" cancel button "Cancel" with icon stop' >>"$LOG_FILE"
        if [ $? -ne 0 ]; then
            echo "Process cancelled by user." >>"$LOG_FILE"
            bw logout >>"$LOG_FILE" 2>&1 && echo "" >>"$LOG_FILE"
            exit 1
        fi
        bw logout >>"$LOG_FILE" 2>&1 && echo "" >>"$LOG_FILE"
        bw login --apikey >>"$LOG_FILE" 2>&1 && echo "" >>"$LOG_FILE"
        continue
    fi

    # if nothing goes wrong, export the session key for later use.
    export BW_SESSION
    break
done

# clean up api key as soon as authenticated
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

# clean up env variables and log out
unset BW_SESSION
unset BW_PASSWORD
bw logout >>"$LOG_FILE" 2>&1 && echo "" >>"$LOG_FILE" && echo "" >>"$LOG_FILE"

# handle potential export errors
if [ $EXPORT_EXIT_CODE -eq 0 ]; then
    echo "Backup completed. Backup file stored at $BACKUP_FILE" >>"$LOG_FILE"
else
    echo "Backup failed." >>"$LOG_FILE"
    kill "$BACKUP_PID" 2>/dev/null
    osascript -e 'display dialog "Backup failed." with title "Backup Failed" buttons {"OK"} default button "OK" with icon stop' >/dev/null 2>&1
    exit 1
fi

# cd to the backup directory. stop immediately if directory not found to prevent unexpected deletion.
cd "$BACKUP_DIR" || {
    echo "Cannot find backup directory. Process aborted." >>"$LOG_FILE"
    osascript -e 'display dialog "Cannot find backup directory. Process aborted." with title "Minimalistic Bitwarden Backup Tool" buttons {"OK"} default button "OK" with icon stop' >/dev/null 2>&1
    kill "$BACKUP_PID" 2>/dev/null
    exit 1
}

# keep the last n files and delete older backups
if [[ ! "$KEEP_LAST_N" =~ ^[0-9]+$ ]] || [ "$KEEP_LAST_N" -lt 1 ]; then
    echo "Invalid KEEP_LAST_N ('$KEEP_LAST_N'), fallback to 3." >>"$LOG_FILE"
    KEEP_LAST_N=3
fi

TAIL_START=$(($KEEP_LAST_N + 1))
ls -t Bitwarden-Backup-*.json 2>/dev/null | tail -n +$TAIL_START | while IFS= read -r f; do
    rm -- "$f" && echo "Rotated out: $f" >>"$LOG_FILE"
done

kill "$BACKUP_PID" 2>/dev/null

# notify user about completion
terminal-notifier -title 'Minimalistic Bitwarden Backup Tool' -message 'Backup completed. Click on this notification to navigate to your backup folder.' -execute "open '$BACKUP_DIR'"
