#!/bin/bash

set -Eeu -o pipefail

GEOIPUPDATE_DB_DIR="$(mktemp -d)"
export GEOIPUPDATE_DB_DIR

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

if [ -z "$GEOIPUPDATE_FREQUENCY" ]; then
    GEOIPUPDATE_FREQUENCY=0
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

### GEOUPDATEIP
echo "LAUNCH GEOIP UPDATE"
if [ "${GEOIPUPDATE_DRYRUN-default}" == "default" ]; then #if GEOIPUPDATE_DRYRUN is not set
    /usr/bin/geoipupdate --verbose --output --database-directory="${GEOIPUPDATE_DB_DIR}"
else
    echo "DRY MODE ON" #if GEOIPUPDATE_DRYRUN is set
    [[ "$(uname  || true)" == "Darwin" ]] && dateCmd="gdate" || dateCmd="date"
    currentUTCdatetime="$("${dateCmd}" --utc +"%Y%m%dT%H%MZ")"
    echo "drymode" >"${GEOIPUPDATE_DB_DIR}/dryrun-${currentUTCdatetime}.mmdb"
fi
echo "UPDATE DONE"

### AZCOPY

if [ -z "$STORAGE_NAME" ]; then
    echo "ERROR: You must set the environment variable STORAGE_NAME!"
    exit 1
fi

if [ -z "$STORAGE_FILESHARE" ]; then
    echo "ERROR: You must set the environment variable STORAGE_FILESHARE!"
    exit 1
fi

echo "LAUNCH AZCOPY"
echo "azure token"
export STORAGE_DURATION_IN_MINUTE=5
export STORAGE_PERMISSIONS=dlrw

fileShareSignedUrl="$(get-fileshare-signed-url.sh)"

echo "azcopy copy"
AZCOPY_FOLDER="$(mktemp -d)"
AZCOPY_LOG_LOCATION="${AZCOPY_FOLDER}"
AZCOPY_JOB_PLAN_LOCATION="${AZCOPY_FOLDER}"
export AZCOPY_LOG_LOCATION
export AZCOPY_JOB_PLAN_LOCATION
set +e #do not failfast on error for azcopy
azcopy copy \
    --skip-version-check `# Do not check for new azcopy versions (we have updatecli + puppet for this)` \
    --log-level=ERROR `# Do not write too much logs (I/O...)` \
    "${GEOIPUPDATE_DB_DIR}/*.mmdb" "${fileShareSignedUrl}" \
|| \
    cat "${AZCOPY_LOG_LOCATION}/.azcopy/*" #dump the logs in case of error during azcopy copy

echo "azcopy list"
azcopy list \
    --skip-version-check `# Do not check for new azcopy versions (we have updatecli + puppet for this)` \
    "${fileShareSignedUrl}"

echo "AZCOPY DONE"

exit 0
