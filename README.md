# syno-plex-update

Checks for available Plex Media Server updates on Synology NAS, automatically downloads and installs them.

Can be set up as a scheduled task in DSM to run regularly. Can write log messages to Log Center.

Tested on DSM 6 and DSM 7. Also supports DSM 7.2.2+ builds incompatible with the earlier versions.

![image](https://user-images.githubusercontent.com/2750531/149373978-6e88c098-30f2-4c28-860e-5eb459faf369.png)

## Setup

### Prerequisites

#### DSM 6

Follow the instructions from [Plex Support](https://support.plex.tv/articles/205165858-how-to-add-plex-s-package-signing-public-key-to-synology-nas-package-center/) to set the package trust level on your NAS and import the package signing key from Plex Inc.

**Important**: do not skip this step otherwise automatic package installation will be forbidden by DSM 6.

#### DSM 7

No prerequisites required, just follow the installation instructions below.

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
![image](https://user-images.githubusercontent.com/2750531/97003865-ce6ad780-1544-11eb-9fa0-b2b42169ff18.png)

**Important**: make sure to run the scheduled task as the `root` user, otherwise automated package installation will fail.