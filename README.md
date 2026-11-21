# BitwardenBackup

This repo contains a script for backing up a Bitwarden vault and encrypting it for storage locally. It is an expansion of [this article](https://bitwarden.com/help/cli-auth-challenges/) on how to do scripted backups but it uses the users Bitwarden API Key so users with 2FA can have an automated backup.

## Key Takeaways
- Backups are encrypted
- A local copy can be kept safely

Fuller usage documentation can be [found here](https://binarypatrick.dev/posts/bitwarden-automated-backup/).

## Install

Install the Bitwarden CLI (`bw`) into `/usr/local/bin`:

```bash
./install.sh
```

The script elevates with `sudo` when needed and requires `wget` and `unzip`.

## Backup

Set the following environment variables before running the backup (all are required; the script fails fast if any are missing):

| Variable | Description |
| --- | --- |
| `BW_CLIENTID` | Bitwarden API Key Client ID |
| `BW_CLIENTSECRET` | Bitwarden API Key Client Secret |
| `BW_PASSWORD` | Bitwarden Vault Password |
| `BW_NOTIFICATION_EMAIL` | Address emailed (via `mail`) if the job fails |

Then run, passing the directory the encrypted backup should be written to:

```bash
./backup.sh /path/to/backup/directory
```

This logs in with the API key, unlocks the vault, exports it as JSON, and encrypts the export to `/path/to/backup/directory/bw_export_<timestamp>.enc` using AES-256-CBC (PBKDF2, 1,000,000 iterations) keyed on `BW_PASSWORD`. If any stage fails after retries, a notification email is sent and the vault is logged out.

## Restore (decrypt)

To decrypt a backup, pass the `.enc` file. You will be prompted for the vault password (`BW_PASSWORD`) that encrypted it:

```bash
./decrypt.sh bw_export_<timestamp>.enc
```

This writes the decrypted vault to `bw_export_<timestamp>.json` in the current directory, which can then be imported back into Bitwarden (**Tools → Import data**, format *Bitwarden (json)*).

> ⚠️ **The decrypted `.json` is your vault in plaintext.** Store it only on trusted, encrypted media and delete it as soon as the import is complete. `decrypt.sh` refuses to overwrite an existing `.json` rather than clobbering it silently.
