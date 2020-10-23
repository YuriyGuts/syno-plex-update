# syno-plex-update

Checks for available Plex Media Server updates on Synology NAS, automatically downloads and installs them.

Can be set up as a scheduled task in DSM to run regularly. Can write log messages to Log Center.

## Setup

### Prerequisites

Follow the instructions from [Plex Support](https://support.plex.tv/articles/205165858-how-to-add-plex-s-package-signing-public-key-to-synology-nas-package-center/) to set the package trust level on your NAS and import the package signing key from Plex Inc.

**Important**: do not skip this step otherwise automatic package installation will be forbidden by DSM.

### Installation

Enter a root shell on your NAS (log in via SSH, then `sudo -i`) and run:
```
# mkdir -p /volume1/Scripts
# cd /volume1/Scripts
# wget -O syno-plex-update.sh https://raw.githubusercontent.com/YuriyGuts/syno-plex-update/master/syno-plex-update.sh
# chmod +x syno-plex-update.sh
```

### Scheduled Task Setup

In `Control Panel` > `Task Scheduler`, click `Create` > `Scheduled Task` > `User-defined script`:

```
bash /volume1/Scripts/syno-plex-update.sh
```
