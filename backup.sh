#!/bin/bash

# Before you run this script you will need to have the following environment variables set
# BW_CLIENTID           // Bitwarden API Key Client ID
# BW_CLIENTSECRET       // Bitwarden API Key Client Secret
# BW_PASSWORD           // Bitwarden Vault Password
# BW_NOTIFICATION_EMAIL // Email address used for notification if job fails

DIRECTORY=$1

NOTIFICATION_EMAIL_SUBJECT="Bitwarden Backup Failed"
NOTIFICATION_EMAIL_BODY="The automated Bitwarden backup failed when trying to unlock the vault"

bw login --apikey
export BW_SESSION=$(bw unlock --raw $BW_PASSWORD)

if [ "$BW_SESSION" == "" ]; then
    echo $NOTIFICATION_EMAIL_BODY | mail -s $NOTIFICATION_EMAIL_SUBJECT $BW_NOTIFICATION_EMAIL
    bw logout
    exit 1
fi;

EXPORT_OUTPUT_BASE="bw_export_"
TIMESTAMP=$(date "+%Y%m%d%H%M%S")
ENC_OUTPUT_FILE=$DIRECTORY/$EXPORT_OUTPUT_BASE$TIMESTAMP.enc

bw --raw --session $BW_SESSION export --format json | openssl enc -aes-256-cbc -pbkdf2 -iter 1000000 -k $BW_PASSWORD -out $ENC_OUTPUT_FILE
bw logout
unset BW_SESSION
