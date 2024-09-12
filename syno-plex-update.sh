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

# Web endpoint for retrieving Plex release metadata.
PLEX_RELEASE_API='https://plex.tv/api/downloads/5.json?X-Plex-Token=TokenPlaceholder'

# Temporary directory for downloading .spk packages. Contents will be destroyed.
DOWNLOAD_DIR='/tmp/syno-plex-update'

# Whether to send log messages to syslog.
ENABLE_SYSLOG_LOGGING=true

# Whether to create system log messages in Synology Log Center.
ENABLE_LOG_CENTER_LOGGING=true

# ========== [End Configuration] ==========

set -eu

DSM_MAJOR_VERSION=$(grep -oP 'majorversion="\K[^"]+' /etc/VERSION)
DSM_PRODUCT_VERSION=$(grep -oP 'productversion="\K[^"]+' /etc/VERSION)
OS_ARCHITECTURE="linux-$(uname -m)"

if [ "${DSM_MAJOR_VERSION}" -ge "7" ]; then
    PACKAGE_NAME='PlexMediaServer'
else
    PACKAGE_NAME='Plex Media Server'
fi

# Path to the local Plex server preferences file (in NAS filesystem).
# https://support.plex.tv/articles/202915258-where-is-the-plex-media-server-data-directory-located/
# Can also be found fia `sudo find / -name "Preferences.xml" | grep Plex`
# Extracting and passing the online token seems optional though, so you can omit this.
if [ "${DSM_MAJOR_VERSION}" -ge "7" ]; then
    PLEX_PREFERENCES_FILE='/volume1/PlexMediaServer/AppData/Plex Media Server/Preferences.xml'
else
    PLEX_PREFERENCES_FILE='/volume1/Plex/Library/Application Support/Plex Media Server/Preferences.xml'
fi

function write_log {
    local full_message="[syno-plex-update] $*"

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

function warn_if_preferences_not_found {
    if [ ! -f "${PLEX_PREFERENCES_FILE}" ]; then
        write_log "Warning: preferences file not found at the expected path: '${PLEX_PREFERENCES_FILE}'. Please edit the script manually"
    fi
}

function get_update_channel {
    # Extract Plex server update channel value from local preferences file.
    grep -oPs 'ButlerUpdateChannel="\K[^"]+' "${PLEX_PREFERENCES_FILE}" || echo "Public"
}

function get_plex_token {
    # Extract Plex server token from local preferences file.
    grep -oPs 'PlexOnlineToken="\K[^"]+' "${PLEX_PREFERENCES_FILE}" || echo ""
}

function get_installed_version {
    # Retrieve the version currently installed on NAS.
    local installed_version
    installed_version=$(synopkg version "${PACKAGE_NAME}")
    # Truncate everything after the dash so that we get a version in A.B.C.D format.
    echo "${installed_version%-*}"
}

function get_nas_release_name {
    # Determine the name of the NAS build in the Plex metadata to use for the update.
    local release_name

    # DSM 6, DSM 7, and DSM 7.2.2+ versions are incompatible; pick the right one.
    if /usr/bin/dpkg --compare-versions "${DSM_PRODUCT_VERSION}" lt 7.0; then
        release_name="Synology (DSM 6)"
    elif /usr/bin/dpkg --compare-versions "${DSM_PRODUCT_VERSION}" ge 7.0 && /usr/bin/dpkg --compare-versions "${DSM_PRODUCT_VERSION}" lt 7.2.2; then
        release_name="Synology (DSM 7)"
    elif /usr/bin/dpkg --compare-versions "${DSM_PRODUCT_VERSION}" ge 7.2.2; then
        release_name="Synology (DSM 7.2.2+)"
    else
        release_name="Synology"
    fi

    echo "${release_name}"
}

function download_release_metadata {
    # Grab release information from Plex API (as JSON).
    local release_url=${PLEX_RELEASE_API/TokenPlaceholder/$(get_plex_token)}

    local update_channel_name
    update_channel_name=$(get_update_channel)
    write_log "Using update channel: ${update_channel_name}"
    if [ "${update_channel_name}" != "Public" ]; then
        release_url="${release_url}&channel=plexpass"
    fi

    # Do not write tokens to logs
    local release_url_with_masked_secrets
    release_url_with_masked_secrets=$(echo "${release_url}" | sed -e 's/Token=[A-Za-z0-9]\+/Token=<hidden>/g')
    write_log "Downloading Plex release metadata from '${release_url_with_masked_secrets}'"

    local response
    response=$(curl --fail --silent "${release_url}")
    local curl_exit_code="$?"
    if [[ ${curl_exit_code} != 0 ]]; then
        write_log "Error: Web request returned a non-zero exit code (${curl_exit_code})"
        return ${curl_exit_code}
    fi
    echo "${response}"
}

function parse_latest_version {
    # Given a Plex release JSON, extract the latest Synology build version.
    local release_meta=$1
    local query

    local release_name
    release_name=$(get_nas_release_name)
    local query=".nas.\"${release_name}\".version"

    local latest_version
    latest_version=$(echo "${release_meta}" | jq -r "${query}")
    # Truncate everything after the dash so that we get a version in A.B.C.D format.
    echo "${latest_version%-*}"
}

function parse_download_url {
    # Given a Plex release JSON, extract the latest Synology build download URL.
    local release_meta=$1

    local release_name
    release_name=$(get_nas_release_name)
    local query=".nas.\"${release_name}\".releases[] | select(.build==\"${OS_ARCHITECTURE}\") | .url"

    local download_url
    download_url=$(echo "${release_meta}" | jq -r "${query}")
    echo "${download_url}"
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
    wget "${url}" -P "${DOWNLOAD_DIR}/"

    local downloaded_package_file
    downloaded_package_file=$(find "${DOWNLOAD_DIR}" -type f -name "*.spk" | head -n 1)

    write_log "Installing SPK package from ${downloaded_package_file}"
    synopkg install "${downloaded_package_file}"
    sleep 30

    write_log "Starting the new ${PACKAGE_NAME} package"
    synopkg start "${PACKAGE_NAME}"

    write_log "Cleaning up ${DOWNLOAD_DIR}"
    rm -rf "${DOWNLOAD_DIR}"
}

function is_latest_version_installed {
    # Check that the installed version is at least as high as the available version.
    local available_version=$1
    local installed_version=$2

    # dpkg version comparison uses exit codes so we'll tolerate errors temporarily.
    set +eu
    /usr/bin/dpkg --compare-versions "${available_version}" gt "${installed_version}"
    local result="$?"
    set -eu

    echo ${result}
}

function main {
    write_log "${PACKAGE_NAME} auto-update started"
    warn_if_preferences_not_found

    installed_version=$(get_installed_version)
    release_meta=$(download_release_metadata)
    latest_version=$(parse_latest_version "${release_meta}")

    write_log "Installed version: ${installed_version}"
    write_log "Latest available version: ${latest_version}"

    is_latest=$(is_latest_version_installed "$latest_version" "$installed_version")
    if [ "$is_latest" -eq "0" ]; then
        write_log 'Update available. Trying to download and install'
        notify_update_available
        download_url=$(parse_download_url "${release_meta}")
        download_and_install_package "${download_url}"
    else
        write_log 'No updates available'
    fi
}

trap "exit_trap" EXIT
main
