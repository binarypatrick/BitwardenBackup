#!/bin/bash

# Fail hard on errors, unset variables, and failed pipeline stages:
#   -e            exit on any unhandled command failure (explicit failures are
#                 still handled via `if`/`||` and the retry function)
#   -u            treat use of an unset variable as an error (catches missing
#                 BW_* configuration early)
#   -o pipefail   a pipeline fails if ANY stage fails, not just the last — so a
#                 failed "bw export" can't be masked by a successful "openssl
#                 enc" and reported as a good (but empty) backup.
set -euo pipefail

# Before you run this script you will need to have the following environment variables set
# BW_CLIENTID           // Bitwarden API Key Client ID
# BW_CLIENTSECRET       // Bitwarden API Key Client Secret
# BW_PASSWORD           // Bitwarden Vault Password
# BW_NOTIFICATION_EMAIL // Email address used for notification if job fails

# ${1:-} rather than $1 so `set -u` doesn't abort before we can use it.
DIRECTORY="${1:-}"
DIRECTORY="${DIRECTORY%/}"  # normalize a trailing slash
NOTIFICATION_EMAIL="${BW_NOTIFICATION_EMAIL:-}"

# Validate the target directory before doing any vault work, so we fail fast
# instead of after login/unlock/export — and never fall back to writing to /.
if [ -z "$DIRECTORY" ]; then
    echo "Usage: $0 <backup-directory>" >&2
    exit 1
fi
if [ ! -d "$DIRECTORY" ]; then
    echo "Backup directory does not exist: $DIRECTORY" >&2
    exit 1
fi
if [ ! -w "$DIRECTORY" ]; then
    echo "Backup directory is not writable: $DIRECTORY" >&2
    exit 1
fi

# Ensure all required configuration is present before doing any vault work.
# This fails fast on a missing/empty BW_PASSWORD (otherwise bw/openssl would
# error mid-run) and guarantees the failure-notification email has a recipient.
MISSING=""
for var in BW_CLIENTID BW_CLIENTSECRET BW_PASSWORD BW_NOTIFICATION_EMAIL; do
    if [ -z "${!var:-}" ]; then
        MISSING="$MISSING $var"
    fi
done
if [ -n "$MISSING" ]; then
    echo "Missing required environment variable(s):$MISSING" >&2
    exit 1
fi

NOTIFICATION_EMAIL_SUBJECT="Bitwarden Backup Failed"
NOTIFICATION_EMAIL_BODY="The automated Bitwarden backup failed when trying to unlock the vault"

MAX_RETRIES=3
RETRY_DELAY=5  # seconds between retries

# Generic retry function
# Usage: retry <max_attempts> <delay> <command> [args...]
retry() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local attempt=1

    while [ "$attempt" -le "$max_attempts" ]; do
        echo "Attempt $attempt of $max_attempts: $1"
        if "$@"; then
            return 0
        fi
        echo "Attempt $attempt failed."
        if [ "$attempt" -lt "$max_attempts" ]; then
            echo "Retrying in ${delay}s..."
            sleep "$delay"
        fi
        attempt=$((attempt + 1))
    done

    echo "All $max_attempts attempts failed for: $1"
    return 1
}

# Login with retry — but skip if a previous run already left us authenticated.
# `bw login` exits non-zero ("You are already logged in.") when a session
# lingers, which would otherwise burn every retry and fail the whole run.
# `|| true` keeps `set -e`/pipefail from aborting when grep finds no match.
BW_STATUS=$(bw status 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4) || true
if [ "$BW_STATUS" = "unauthenticated" ] || [ -z "$BW_STATUS" ]; then
    if ! retry "$MAX_RETRIES" "$RETRY_DELAY" bw login --apikey; then
        echo "$NOTIFICATION_EMAIL_BODY (login failed)" | mail -s "$NOTIFICATION_EMAIL_SUBJECT" "$NOTIFICATION_EMAIL" || true
        exit 1
    fi
fi

# Unlock with retry — captures session key on success.
# The `export` prefix masks the command-substitution exit status, so a failed
# unlock does not trip `set -e`; the loop below handles the empty-session case.
attempt=1
BW_SESSION=""
while [ "$attempt" -le "$MAX_RETRIES" ]; do
    echo "Unlock attempt $attempt of $MAX_RETRIES"
    export BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw)
    if [ -n "$BW_SESSION" ]; then
        echo "Vault unlocked successfully."
        break
    fi
    echo "Unlock attempt $attempt failed."
    if [ "$attempt" -lt "$MAX_RETRIES" ]; then
        echo "Retrying in ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
    fi
    attempt=$((attempt + 1))
done

if [ -z "$BW_SESSION" ]; then
    echo "$NOTIFICATION_EMAIL_BODY" | mail -s "$NOTIFICATION_EMAIL_SUBJECT" "$NOTIFICATION_EMAIL" || true
    bw logout || true
    exit 1
fi

EXPORT_OUTPUT_BASE="bw_export_"
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
ENC_OUTPUT_FILE="$DIRECTORY/$EXPORT_OUTPUT_BASE$TIMESTAMP.enc"

# Export the vault and encrypt it. Kept in a function (rather than a
# `bash -c "...$BW_PASSWORD..."` string) so the password is never placed on a
# command line — it would otherwise be visible in `ps` and, worse, re-parsed by
# the shell (a password containing spaces or shell metacharacters would break
# the command or inject into it). openssl reads the password from the
# environment via `-pass env:`. pipefail (set at the top) makes a failed
# `bw export` fail the whole pipeline instead of encrypting empty output.
export_and_encrypt() {
    bw --raw --session "$BW_SESSION" export --format json \
        | openssl enc -aes-256-cbc -pbkdf2 -iter 1000000 -pass env:BW_PASSWORD -out "$ENC_OUTPUT_FILE"
}

# Export and encrypt with retry
if ! retry "$MAX_RETRIES" "$RETRY_DELAY" export_and_encrypt; then
    echo "Backup export failed after $MAX_RETRIES attempts." | mail -s "$NOTIFICATION_EMAIL_SUBJECT" "$NOTIFICATION_EMAIL" || true
    bw logout || true
    unset BW_SESSION
    exit 1
fi

bw logout || true
unset BW_SESSION

echo "Backup completed successfully: $ENC_OUTPUT_FILE"
