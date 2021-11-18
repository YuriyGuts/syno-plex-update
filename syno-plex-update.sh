#!/usr/bin/env bash
#
# Check for available Plex Media Server updates on Synology NAS,
# automatically download and install them.
#
# Can be set up as a Scheduled Task in DSM (check the home page for details).
#
# Author: @YuriyGuts [https://github.com/YuriyGuts]
# Home page: https://github.com/YuriyGuts/syno-plex-update

# ========== [Begin Configuration] ==========

DSM_VERSION=$(cat /etc/VERSION | grep majorversion | tail -c 3 | head -c 1)
OS_ARCHITECTURE="linux-$(uname -m)"

# Path to the local Plex server preferences file (in NAS filesystem).
# Can be found fia `sudo find / -name "Preferences.xml" | grep Plex`
# Extracting and passing the online token seems optional though, so you can omit this.
if [ "${DSM_VERSION}" -ge "7" ]; then
    PLEX_PREFERENCES_FILE='/var/packages/PlexMediaServer/shares/PlexMediaServer/AppData/Plex Media Server/Preferences.xml'
else
    PLEX_PREFERENCES_FILE='/volume1/@apphome/PlexMediaServer/Plex Media Server/Preferences.xml'
fi

# Web endpoint for retrieving Plex release metadata.
PLEX_RELEASE_API='https://plex.tv/api/downloads/5.json?channel=plexpass&X-Plex-Token=TokenPlaceholder'

# Temporary directory for downloading .spk packages. Contents will be destroyed.
DOWNLOAD_DIR='/tmp/syno-plex-update'

# Whether to send log messages to syslog.
ENABLE_SYSLOG_LOGGING=true

# Whether to create system log messages in Synology Log Center.
ENABLE_LOG_CENTER_LOGGING=true

# ========== [End Configuration] ==========

if [ "${DSM_VERSION}" -ge "7" ]; then
    PACKAGE_NAME='PlexMediaServer'
else
    PACKAGE_NAME='Plex Media Server'
fi

set -eu

function write_log {
    local full_message="[syno-plex-update] $@"

    if [ "${ENABLE_SYSLOG_LOGGING}" = true ]; then
        # Write to rsyslog and mirror to stderr.
        logger --stderr "${full_message}"
    else
        # Just write to stderr.
        cat <<< "$(date) ${full_message}" 1>&2;
    fi

    if [ "${ENABLE_LOG_CENTER_LOGGING}" = true ]; then
        # Write to Synology Log Center.
        # Hack: for some reason, rapidly written logs appear out of order
        # in Log Center, so add a short sleep after each message.
        synologset1 sys info 0x11100000 "${full_message}" && sleep 1
    fi
}

function exit_trap {
    local exit_code="$?"
    if [[ ${exit_code} -eq "0" ]]; then
        write_log "${PACKAGE_NAME} auto-update completed successfully"
    else
        write_log "${PACKAGE_NAME} auto-update failed with exit code ${exit_code}"
    fi
}

function get_plex_token {
    # Extract Plex server token from local preferences file.
    cat "${PLEX_PREFERENCES_FILE}" | grep -oP 'PlexOnlineToken="\K[^"]+'
}

function get_installed_version {
    # Retrieve the version currently installed on NAS.
    local installed_version=$(synopkg version "${PACKAGE_NAME}")
    # Truncate everything after the dash so that we get a version in A.B.C.D format.
    echo ${installed_version%-*}
}

function download_release_metadata {
    # Grab release information from Plex API (as JSON).
    local release_url=${PLEX_RELEASE_API/TokenPlaceholder/$(get_plex_token)}
    local response

    write_log "Downloading Plex release metadata from '${release_url}'"
    response=$(curl --fail --silent "${release_url}")
    local curl_exit_code="$?"
    if [[ ${curl_exit_code} != 0 ]]; then
        write_log "Error: Web request returned a non-zero exit code (${curl_exit_code})"
        return ${curl_exit_code}
    fi
    echo ${response}
}

function parse_latest_version {
    # Given a Plex release JSON, extract the latest Synology build version.
    local release_meta=$1
    if [ "${DSM_VERSION}" -ge "7" ]; then
        local query='.nas."Synology (DSM 7)".version'
    else
        local query='.nas.Synology.version'
    fi
    local latest_version=$(echo "${release_meta}" | jq -r "${query}")
    # Truncate everything after the dash so that we get a version in A.B.C.D format.
    echo ${latest_version%-*}
}

function parse_download_url {
    # Given a Plex release JSON, extract the latest Synology build download URL.
    local release_meta=$1
    if [ "${DSM_VERSION}" -ge "7" ]; then
        local query=".nas.\"Synology (DSM 7)\".releases[] | select(.build==\"${OS_ARCHITECTURE}\") | .url"
    else
        local query=".nas.Synology.releases[] | select(.build==\"${OS_ARCHITECTURE}\") | .url"
    fi
    local download_url=$(echo "${release_meta}" | jq -r "${query}")
    echo ${download_url}
}

function notify_update_available {
    # Create a DSM notification that a new update is available.
    synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "Plex Media Server", "%COMPANY_NAME%": "Plex Inc."}'
}

function download_and_install_package {
    # Given a download URL for an SPK package, download and install it.
    local url=$1

    write_log "Downloading latest version from ${url}"
    rm -rf "${DOWNLOAD_DIR}"
    mkdir -p "${DOWNLOAD_DIR}" > /dev/null 2>&1
    wget ${url} -P "${DOWNLOAD_DIR}/"

    local downloaded_package_file="${DOWNLOAD_DIR}/*.spk"
    write_log "Installing SPK package from ${downloaded_package_file}"
    synopkg install ${downloaded_package_file}
    sleep 30

    write_log "Starting the new ${PACKAGE_NAME} package"
    synopkg start "${PACKAGE_NAME}"

    write_log "Cleaning up ${downloaded_package_file}"
    rm -rf "${downloaded_package_file}"
}

function main {
    write_log "${PACKAGE_NAME} auto-update started"

    installed_version=$(get_installed_version)
    release_meta=$(download_release_metadata)
    latest_version=$(parse_latest_version "${release_meta}")

    write_log "Installed version: ${installed_version}"
    write_log "Latest available version: ${latest_version}"

    set +eu
	/usr/bin/dpkg --compare-versions "$latest_version" gt "$installed_version"
    if [ "$?" -eq "0" ]; then
        set -eu
        write_log 'Update available. Trying to download and install'
        notify_update_available
        download_url=$(parse_download_url "${release_meta}")
        download_and_install_package "${download_url}"
    else
        set -eu
        write_log 'No updates available'
    fi
}

trap "exit_trap" EXIT
main
