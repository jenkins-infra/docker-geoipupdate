#!/bin/bash

set -Eeu -o pipefail
echo "----------------------- Start "
date

GEOIPUPDATE_DB_DIR="$(mktemp -d)"
export GEOIPUPDATE_DB_DIR
export GEOIPUPDATE_FREQUENCY=0

if [ -z "$GEOIPUPDATE_ACCOUNT_ID" ] && [ -z  "$GEOIPUPDATE_ACCOUNT_ID_FILE" ]; then
    echo "ERROR: You must set the environment variable GEOIPUPDATE_ACCOUNT_ID or GEOIPUPDATE_ACCOUNT_ID_FILE!"
    exit 1
fi

if [ -z "$GEOIPUPDATE_LICENSE_KEY" ] && [ -z  "$GEOIPUPDATE_LICENSE_KEY_FILE" ]; then
    echo "ERROR: You must set the environment variable GEOIPUPDATE_LICENSE_KEY or GEOIPUPDATE_LICENSE_KEY_FILE!"
    exit 1
fi

if [ -z "$GEOIPUPDATE_EDITION_IDS" ]; then
    GEOIPUPDATE_EDITION_IDS="GeoLite2-ASN GeoLite2-City GeoLite2-Country"
fi

if [ -z "$JENKINS_INFRA_FILESHARE_CLIENT_ID" ]; then
    echo "ERROR: You must set the environment variable JENKINS_INFRA_FILESHARE_CLIENT_ID!"
    exit 1
fi

if [ -z "$JENKINS_INFRA_FILESHARE_CLIENT_SECRET" ]; then
    echo "ERROR: You must set the environment variable JENKINS_INFRA_FILESHARE_CLIENT_SECRET!"
    exit 1
fi

if [ -z "$JENKINS_INFRA_FILESHARE_TENANT_ID" ]; then
    echo "ERROR: You must set the environment variable JENKINS_INFRA_FILESHARE_TENANT_ID!"
    exit 1
fi

if [ -z "$STORAGE_NAME" ]; then
    echo "ERROR: You must set the environment variable STORAGE_NAME!"
    exit 1
fi

if [ -z "$STORAGE_FILESHARE" ]; then
    echo "ERROR: You must set the environment variable STORAGE_FILESHARE!"
    exit 1
fi

### Azure TOKEN
echo "LAUNCH AZ token"
echo "azure token"
export STORAGE_DURATION_IN_MINUTE=5
export STORAGE_PERMISSIONS=dlrw

fileShareSignedUrl="$(get-fileshare-signed-url.sh)"
urlWithoutToken=${fileShareSignedUrl%\?*}
token=${fileShareSignedUrl#*\?}

### AZ COPY dest to local
echo "LAUNCH AZCOPY dest to local"
AZCOPY_FOLDER="$(mktemp -d)"
AZCOPY_LOG_LOCATION="${AZCOPY_FOLDER}"
AZCOPY_JOB_PLAN_LOCATION="${AZCOPY_FOLDER}"
export AZCOPY_LOG_LOCATION
export AZCOPY_JOB_PLAN_LOCATION
echo "local folder = ${GEOIPUPDATE_DB_DIR}/"
set +e #do not failfast on error for azcopy
: | azcopy copy \
    "${urlWithoutToken}/*?${token}" "${GEOIPUPDATE_DB_DIR}" \
    --skip-version-check `# Do not check for new azcopy versions (we have updatecli + puppet for this)` \
    --log-level=ERROR `# Do not write too much logs (I/O...)` \
    --include-pattern='*.mmdb' `# only the mmdb databases files` \
|| \
    { cat "${AZCOPY_LOG_LOCATION}/.azcopy/*"; exit 1; }   #dump the logs in case of error during azcopy copy
set -e #set failfast back
echo "AZCOPY dest to local done"

echo "LISTING local: "
ls -lt "${GEOIPUPDATE_DB_DIR}"

### GEOUPDATEIP
echo "LAUNCH GEOIPUPDATE"
GEOIPUPDATEJSONDIR="$(mktemp -d)"
export GEOIPUPDATEJSONDIR
if [ "${GEOIPUPDATE_DRYRUN:-false}" != "true" ]; then
    geoipupdate --verbose --output="${GEOIPUPDATEJSONDIR}/geoipupdate.json" --database-directory="${GEOIPUPDATE_DB_DIR}"
else
    echo "DRY-RUN ON"
    [[ "$(uname  || true)" == "Darwin" ]] && dateCmd="gdate" || dateCmd="date"
    currentUTCdatetime="$("${dateCmd}" --utc +"%Y%m%dT%H%MZ")"
    echo "dry-run" >"${GEOIPUPDATE_DB_DIR}/dryrun-${currentUTCdatetime}.mmdb"
    echo '[{"edition_id":"GeoLite2-ASN","old_hash":"c54b6e64478adfd010c7a86db310033f","new_hash":"857a0cf8118b9961cf6789e1842bce2a","modified_at":1733403617,"checked_at":1733756616},{"edition_id":"GeoLite2-City","old_hash":"34a6a0ec4018c74a503134980c154502","new_hash":"fb3449d8252f74eac39fc55c32c19879","modified_at":1733501742,"checked_at":1733756620},{"edition_id":"GeoLite2-Country","old_hash":"627a1d220b5ef844e0f0f174a0161cd7","new_hash":"27b1f57ae9dd56e1923f5d458514794c","modified_at":1733506208,"checked_at":1733756621}]' > "${GEOIPUPDATEJSONDIR}/geoipupdate.json"
    # echo '[{"edition_id":"GeoLite2-ASN","old_hash":"857a0cf8118b9961cf6789e1842bce2a","new_hash":"857a0cf8118b9961cf6789e1842bce2a","checked_at":1733760216},{"edition_id":"GeoLite2-City","old_hash":"fb3449d8252f74eac39fc55c32c19879","new_hash":"fb3449d8252f74eac39fc55c32c19879","checked_at":1733760216},{"edition_id":"GeoLite2-Country","old_hash":"27b1f57ae9dd56e1923f5d458514794c","new_hash":"27b1f57ae9dd56e1923f5d458514794c","checked_at":1733760216}]' > "${GEOIPUPDATEJSONDIR}/geoipupdate.json"
    echo "json saved to file ${GEOIPUPDATEJSONDIR}/geoipupdate.json"
    cat "${GEOIPUPDATEJSONDIR}/geoipupdate.json"
fi
echo "GEOIPUPDATE DONE"

### PARSING JSON copy if hash have changed
# > /dev/null to avoid multiple true in output but keep errors output
if jq -e '.[] | select(.old_hash != .new_hash)' "${GEOIPUPDATEJSONDIR}/geoipupdate.json" > /dev/null; then
    echo "DATA CHANGED, update needed"
    ### AZCOPY local to dest
    echo "LAUNCH AZCOPY local to dest"
    set +e #do not failfast on error for azcopy
    : | azcopy copy \
        "${GEOIPUPDATE_DB_DIR}/*" "${fileShareSignedUrl}" \
        --skip-version-check `# Do not check for new azcopy versions (we have updatecli + puppet for this)` \
        --log-level=ERROR `# Do not write too much logs (I/O...)` \
        --include-pattern='*.mmdb' `# only the mmdb databases files` \
        --overwrite="ifSourceNewer" `# Upload if and only if the updategeoip as updated the files` \
    || \
        { cat "${AZCOPY_LOG_LOCATION}/.azcopy/*"; exit 1; }   #dump the logs in case of error during azcopy copy
    set -e #set failfast back
    ### AZCOPY List to ensure files are present on destination
    echo "azcopy list"
    azcopy list \
        --skip-version-check `# Do not check for new azcopy versions (we have updatecli + puppet for this)` \
        "${fileShareSignedUrl}"
    echo "AZCOPY local to dest done"

    if [ "${GEOIPUPDATE_ROLLOUT:-false}" != "false" ]; then
        echo "ROLLOUT RESTART"
        # Backup IFS
        OLDIFS=${IFS}
        # Split the entries by ";"
        IFS=';' read -ra entries <<< "${GEOIPUPDATE_ROLLOUT}"
        # Loop through the entries
        for entry in "${entries[@]}"; do
            # Split namespace and deployments by ":"
            IFS=':' read -r namespace deployments <<< "${entry}"
            # Split deployments by "," and loop through each
            IFS=',' read -ra deployment_list <<< "${deployments}"
            for deployment in "${deployment_list[@]}"; do
                # ROLLOUT RESTART and ROLLOUT STATUS
                echo kubectl -n "${namespace}" rollout restart deployment "${deployment}" && kubectl -n "${namespace}" rollout status deployment "${deployment}"
                kubectl -n "${namespace}" rollout restart deployment "${deployment}" && kubectl -n "${namespace}" rollout status deployment "${deployment}"
            done
        done
        # Restore IFS
        IFS=${OLDIFS}
        echo "ROLLOUT RESTART DONE"
    fi
else
    echo "Data are up to date"
fi

exit 0
