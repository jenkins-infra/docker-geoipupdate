#!/bin/bash

set -eu -o pipefail
# Don't print any trace
set +x

GEOIPUPDATE_DB_DIR="$(mktemp -d)"
export GEOIPUPDATE_DB_DIR
export GEOIPUPDATE_FREQUENCY=0
export GEOIPUPDATE_EDITION_IDS="GeoLite2-ASN GeoLite2-City GeoLite2-Country"
export log_file="/var/log/geoipupdater.log"

if [ -z "$GEOIPUPDATE_ACCOUNT_ID" ] && [ -z  "$GEOIPUPDATE_ACCOUNT_ID_FILE" ]; then
    echo "ERROR: You must set the environment variable GEOIPUPDATE_ACCOUNT_ID or GEOIPUPDATE_ACCOUNT_ID_FILE!"
    exit 1
fi

if [ -z "$GEOIPUPDATE_LICENSE_KEY" ] && [ -z  "$GEOIPUPDATE_LICENSE_KEY_FILE" ]; then
    echo "ERROR: You must set the environment variable GEOIPUPDATE_LICENSE_KEY or GEOIPUPDATE_LICENSE_KEY_FILE!"
    exit 1
fi

if [ -z "$GEOIPUPDATE_EDITION_IDS" ]; then
    echo "ERROR: You must set the environment variable GEOIPUPDATE_EDITION_IDS!"
    exit 1
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
/usr/bin/geoipupdate --verbose --output --database-directory="${GEOIPUPDATE_DB_DIR}" 1>$log_file
echo "UPDATE DONE"

### AZCOPY
echo "LAUNCH AZCOPY"
echo "azure token"
export STORAGE_NAME="publick8spvdata"
export STORAGE_FILESHARE="geoip-data"
export STORAGE_DURATION_IN_MINUTE=5
export STORAGE_PERMISSIONS=dlrw

# Required variables that should be set useless as checked upper
fileShareSignedUrl="$(get-fileshare-signed-url.sh)"

echo "azcopy copy"
azcopy copy \
    --skip-version-check `# Do not check for new azcopy versions (we have updatecli + puppet for this)` \
    --log-level=ERROR `# Do not write too much logs (I/O...)` \
    "${GEOIPUPDATE_DB_DIR}/*.mmdb" "${fileShareSignedUrl}"

echo "azcopy list"
azcopy list "${fileShareSignedUrl}"

echo "AZCOPY DONE"

exit 0
