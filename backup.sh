#!/bin/bash

# Before you run this script you will need to have the following environment variables set
# BW_CLIENTID           // Bitwarden API Key Client ID
# BW_CLIENTSECRET       // Bitwarden API Key Client Secret
# BW_PASSWORD           // Bitwarden Vault Password
# BW_NOTIFICATION_EMAIL // Email address used for notification if job fails

DIRECTORY=$1

NOTIFICATION_EMAIL_SUBJECT="Bitwarden Backup Failed"
NOTIFICATION_EMAIL_BODY="The automated Bitwarden backup failed when trying to unlock the vault"

MAX_RETRIES=3
RETRY_DELAY=5  # seconds between retries

# Generic retry function
# Usage: retry <max_attempts> <delay> <command> [args...]
retry() {
    local max_attempts=$1
    local delay=$2
    shift 2
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt of $max_attempts: $1"
        if "$@"; then
            return 0
        fi
        echo "Attempt $attempt failed."
        if [ $attempt -lt $max_attempts ]; then
            echo "Retrying in ${delay}s..."
            sleep $delay
        fi
        attempt=$((attempt + 1))
    done

    echo "All $max_attempts attempts failed for: $1"
    return 1
}

# Login with retry
if ! retry $MAX_RETRIES $RETRY_DELAY bw login --apikey; then
    echo "$NOTIFICATION_EMAIL_BODY (login failed)" | mail -s "$NOTIFICATION_EMAIL_SUBJECT" "$BW_NOTIFICATION_EMAIL"
    exit 1
fi

# Unlock with retry — captures session key on success
attempt=1
while [ $attempt -le $MAX_RETRIES ]; do
    echo "Unlock attempt $attempt of $MAX_RETRIES"
    export BW_SESSION=$(bw unlock --raw $BW_PASSWORD)
    if [ -n "$BW_SESSION" ]; then
        echo "Vault unlocked successfully."
        break
    fi
    echo "Unlock attempt $attempt failed."
    if [ $attempt -lt $MAX_RETRIES ]; then
        echo "Retrying in ${RETRY_DELAY}s..."
        sleep $RETRY_DELAY
    fi
    attempt=$((attempt + 1))
done

if [ -z "$BW_SESSION" ]; then
    echo "$NOTIFICATION_EMAIL_BODY" | mail -s "$NOTIFICATION_EMAIL_SUBJECT" "$BW_NOTIFICATION_EMAIL"
    bw logout
    exit 1
fi

EXPORT_OUTPUT_BASE="bw_export_"
TIMESTAMP=$(date "+%Y%m%d%H%M%S")
ENC_OUTPUT_FILE=$DIRECTORY/$EXPORT_OUTPUT_BASE$TIMESTAMP.enc

# Export and encrypt with retry
if ! retry $MAX_RETRIES $RETRY_DELAY bash -c \
    "bw --raw --session $BW_SESSION export --format json | openssl enc -aes-256-cbc -pbkdf2 -iter 1000000 -k $BW_PASSWORD -out $ENC_OUTPUT_FILE"; then
    echo "Backup export failed after $MAX_RETRIES attempts." | mail -s "$NOTIFICATION_EMAIL_SUBJECT" "$BW_NOTIFICATION_EMAIL"
    bw logout
    unset BW_SESSION
    exit 1
fi

bw logout
unset BW_SESSION

echo "Backup completed successfully: $ENC_OUTPUT_FILE"
