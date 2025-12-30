# Minimalistic Bitwarden Backup Tool

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)

We all love [Bitwarden](https://bitwarden.com/). However, sometimes we just don't feel comfortable storing all the passwords on the cloud. Although Bitwarden [stores local cache for 30 days](https://bitwarden.com/blog/configuring-bitwarden-clients-for-offline-access/#staying-logged-in-to-browser-extension-desktop-and-mobile-clients) when you go offline, it always gives a peace of mind if you know you have a secure local backup copy in your hard drive or USB thumb drive. It's also hard to keep track of all your backups, or you might completely forget to backup your passwords sometimes. **Minimalistic Bitwarden Backup Tool** is made with these concerns in mind.

This is a simple yet robust automated shell script tool that backups your Bitwarden vault in an instant on macOS. It utilizes the official [bitwarden-cli](https://bitwarden.com/help/cli/) to authenticate and automatically store backups, exporting a **portable (password-protected)** JSON file that you can import back to Bitwarden or other supported password managers (e.g. [KeePassXC](https://keepassxc.org/)). You can even set up reminders with [terminal-notifier](https://github.com/julienXX/terminal-notifier) to send notifications when it's time for backup so you'll never forget.

No Docker, no endless dependencies, no complexities. Just a simple, transparent, hassle-free, minimalistic shell script backup tool for your local storage.

## Features

- 🖥️ **GUI Prompts:** Uses macOS native dialogs to request the master password and send notifications. No typing passwords into the terminal.
- 🛏️ **One-Click Backup**: Type the command or click on the notification, then enter your master password. Sit back and let the tool handle the rest.
- 📂 **Portable Backups:** Creates password-protected JSON exports that can be imported into _any_ Bitwarden account (unlike account-restricted backups). The backup files are protected with the same master password for your Bitwarden vault.
- 🧹 **Automated Cleanup:** Automatically keeps only the last `N` backups (configurable) to save disk space and prevent potential security threats.
- ⏰ **Reminders:** Uses `terminal-notifier` to send polite, non-intrusive notifications to you when it's time for backup (frequency configurable). You can click on the notification and start the backup whenever you're ready.

## How to Use

To initiate a backup process, simply type this command in your terminal:

```
bw-backup
```

or, if you don't want to use the alias, `cd` to the project folder and type:

```bash
./bw-backup.sh
```

And that's it!

A dialog window will appear requesting your Bitwarden master password. Once you enter the correct password, it handles everything and stores the encrypted JSON file in the directory of your choice. You will receive a notification after ~10 seconds confirming the backup.

If you set up a reminder with `crontab` (detailed below), you will receive a notification regularly that looks like this:

<img src="./assets/backup-alert.png"/>

Clicking on it will bring out the same dialog requesting your master password. Enter the password and you are good to go.

A little GIF showing you how easy it is:

<img src="./assets/backup-demo.gif"/>

## Setup

### Prerequisites

You need `bitwarden-cli` and `terminal-notifier` installed on your macOS system. You can install them easily via [Homebrew](https://brew.sh/):

```
brew install bitwarden-cli terminal-notifier
```

### Configuring `.env` file

First, clone this repository and go to the project directory:

```bash
git clone https://github.com/kckhchen/minimalistic-bitwarden-backup.git
cd minimalistic-bitwarden-backup
```

Copy the `.env.example` file in the repository and rename it `.env` before configuring.

```bash
cp ./.env.example ./.env
```

Log in to Bitwarden on your web browser and follow the steps from the [official documentation](https://bitwarden.com/help/personal-api-key/#get-your-personal-api-key) to get your API key. Copy and paste your `client_id` and `client_secret` in the corresponding fields in the `.env` file. Other configurable variables are listed here:

| Name              | Description                                            | Default                   |
| ----------------- | ------------------------------------------------------ | ------------------------- |
| `BW_CLIENTID`     | Your `client_id` from Bitwarden                        | none                      |
| `BW_CLIENTSECRET` | Your `client_secret` from Bitwarden                    | none                      |
| `BACKUP_DIR`      | Directory to store your backup files                   | `$HOME/Backups/Bitwarden` |
| `LOG_FILE`        | Path to the log file                                   | `/tmp/bw-backup.log`      |
| `MAX_ATTEMPTS`    | Maximum attempts of password before the process aborts | 5                         |
| `KEEP_LAST_N`     | Number of backups to keep                              | 3                         |

### Installation

This repository comes with a `setup.sh` shell script. Use the following commands to quickly set things up.

```bash
# make executable
chmod +x ./setup.sh

# run the script
./setup.sh
```

`setup.sh` will check dependencies, create the backup directory, validate configurations, and make sure your `.env` file is secure. Specifically, it runs `chmod 600` for your `.env` to make sure only you, the owner, can access the sensitive information inside.

The setup script also enables the command `bw-backup` for you to backup your file manually in the terminal (you can opt out of it, of course)

### Scheduling the Backup (Optional)

Besides typing the command and running the backup task manually, you can set up a cron scheduler for `backup-alerter.sh` to remind you on a regular basis. First, edit the `crontab` file by typing this command in the terminal:

```
crontab -e
```

Then use any cron expression to set up the frequency with which you want to be reminded. For example, to have cron remind you on the first day of every month at noon, enter the following and save the file (You might need to give permissions to cron):

```
0 12 1 * * /path/to/repo/backup-alerter.sh
```

You will get a clickable notification when it's time to backup. For more crontab settings you can refer to [crontab guru](https://crontab.guru/).

## How to Restore

If you ever need to use your backup:

1.  Log in to your [Bitwarden Web Vault](https://vault.bitwarden.com/).
2.  Go to **Tools** → **Import Data**.
3.  Select format: **Bitwarden (json)**.
4.  Choose the `Backup-YYYY-MM-DD.json` file generated by this tool.
5.  **Important:** Because the file is encrypted, Bitwarden will ask for the password you used when the backup was created (which is your master password).

Or you might want a cold storage in KeePassXC:

1. Open the KeePassXC application.
2. Select **Import File**, choose **Bitwarden (.json)**.
3. Use **Browse** to locate your backup `Backup-YYYY-MM-DD.json` and enter your master password in the **Password** field.
4. Encrypt the database with your password.

## ⚠️ Security Disclosure

This tool creates **password-protected** backups using the official `bw export` command.

To create a backup that is portable (password-protected), we must pass the password to the CLI using the `--password` flag. This means that when this particular line of code is running, it may be visible to malware or other users who are actively monitoring process lists. **Do not run this script on a shared computer or multi-user server** where other users might be monitoring processes.

Unfortunately currently there's no way around this limitation as the `bw export` does not support reading passwords from an environment variable, but on a personal computer this tool is generally safe to run.

Alternatively, if you do not plan to import your password to other Bitwarden accounts or password managers, simply look for the line with the command `bw export` in `bw-backup.sh` and delete the `--password` flag and the argument:

```bash
bw export --format encrypted_json --output "$BACKUP_FILE"
```

This will create an [account-restricted export](https://bitwarden.com/help/encrypted-export/) that can only be imported to the same account that generated the encrypted export. You **WILL NOT** be able to use this backup elsewhere.

If you prefer, you can also export unencrypted JSON by modifying the same line: Remove the `--password` flage and argument and change the argument for `--format` to `json`.

```bash
bw export --format json --output "$BACKUP_FILE"
```

> [!WARNING]
> Having your unencrypted password backups stored on your local machine can be very dangerous. Please proceed at your own discretion.

## Technical Notes

### Log File

When the script runs, it creates a log file at `/tmp/bw-backup.log`. You can check the log here should anything go wrong. You may also change the log file path in the `.env` file.

### Possibility of Full Automation

Technically this can be achieved. However, not having to manually type in the master password to initiate the backup process generally means that the user has to store the master password in plain text as an environment variable, which is dangerous practice. For this reason, manually typing the master password via the secure OS prompt is the intended design.

### Known issue

For unknown reasons, sometimes even when the master password is correct, Bitwarden returns an empty session key string. A detection code block is included to capture this issue and prompt a re-login automatically.

<img src="./assets/empty-session-key.png" width="300" />

Generally, 1 or 2 re-logins solve the issue. If you know the solution to this issue, please let me know.

---

Please feel free to let me know if there are any issues or suggestions. I will be more than happy to accomodate.

_Disclaimer: I have no association with Bitwarden. This is purely an interest project._
