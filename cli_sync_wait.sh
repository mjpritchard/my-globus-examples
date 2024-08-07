#!/bin/bash

# Adapted from https://github.com/globus/automation-examples/blob/master/cli-sync.sh

# PREREQUISITES
#
# The Globus CLI must be installed and have an active login session.
#

# DESCRIPTION
#
# Sync one folder with another, across two endpoints.
# The sync will recurse through all subdirectories.
# Uses "globus task wait -H" to wait for async task completion before exiting
#
# Source: Globus Tutorial Endpoint 1: /share/godata
# Destination: Globus Tutorial Endpoint 2: /~/sync-demo/ # Your account home directory
# 
# Default values are below in CAPS for
# SOURCE_ENDPOINT, DESTINATION_ENDPOINT, SOURCE_PATH,
# DESTINATION_PATH, LAST_TRANSFER_ID_FILE, and SYNCTYPE
# 
# Changes these to make this script suit your needs.
#
# Visit https://www.globus.org/app/transfer?destination_id=ddb59af0-6d04-11e5-ba46-22000b92c6ec
# to view the transferred data.

## Globus Tutorial Endpoint 1
#SOURCE_ENDPOINT='ddb59aef-6d04-11e5-ba46-22000b92c6ec'
# ARCHER2 file systems
SOURCE_ENDPOINT='3e90d018-0d05-461a-bbaf-aab605283d21'

## Globus Tutorial Endpoint 2
#DESTINATION_ENDPOINT='ddb59af0-6d04-11e5-ba46-22000b92c6ec'
# JASMIN Default Collection
DESTINATION_ENDPOINT='a2f53b7f-1b4e-4dce-9b7c-349ae760fee0'

# Sample data
SOURCE_PATH='/src/path/'

# Destination Path
# The directory will be created if it doesn't exist
DESTINATION_PATH='/dst/path/'

# Where the ID of the previous transfer (if exists) is stored
LAST_TRANSFER_ID_FILE='last-transfer-id.txt'

# Sync options:
#   exists   Copy files that do not exist at the destination.
#   size     Copy files if the size of the destination does not match the size of the source.
#   mtime    Copy files if the timestamp of the destination is older than the timestamp of the source.
#   checksum Copy files if checksums of the source and destination do not match. Files on the destination are never deleted.
# For more information:
# $ globus transfer --help
# < OR >
# https://docs.globus.org/api/transfer/task_submit/#transfer_and_delete_documents
SYNCTYPE='checksum'

# always start unset
unset abort_message

# start with default of 0
rc=0

# Abort with message
function abort () {
    echo "$abort_message" >&2
    exit $rc
}

function wait_active () {
    echo "Waiting for active task:" $1

    wait_output=$(globus task wait -H $1)
    echo "Wait output: $wait_output"
} 

# Check if abort is necessary, and if so do it
function check_rc () {
    if [ $# -gt 0 ];
    then
        abort_message="$1"
    fi

    if [ $rc -ne 0 ];
    then
        abort
    fi

    if [ $rc -eq 0 -a "$2" != "" ];
    then
        printf "$2"
    fi
}

# Check if abort is necessary, fetching rc first
function check_last_rc () {
    # must be the first command of the function
    rc=$?
    check_rc "$@"
}

# Only continue if the previous transfer succeeded or failed
# Other statuses will mean that previous transfer is either still
# running or requires human intervention (e.g., PAUSED)

echo "Checking for a previous transfer"

if [ -e "$LAST_TRANSFER_ID_FILE" ]
then
    last_transfer_id=$(cat "$LAST_TRANSFER_ID_FILE")
    last_transfer_status=$(globus task show --format unix --jmespath 'status' $last_transfer_id)
    case "$last_transfer_status" in
        "ACTIVE")
            abort_message="Last transfer $last_transfer_id status was $last_transfer_status, no new task."
            rc=1
            wait_active "$last_transfer_id"
            abort
            ;;

        "PAUSED")
            abort_message="Last transfer $last_transfer_id status is $last_transfer_status, aborting"
            rc=1
            echo "Check https://app.globus.org/activity/$last_transfer_id/overview for details"
            abort
            ;;

        "SUCCEEDED" | "FAILED")
            echo "Last transfer $last_transfer_id $last_transfer_status, continuing"
            ;;

        *)
            echo "Unknown status"
            abort
            ;;
    esac
fi

# Verify that the source paths is a directory
globus ls --format unix --jmespath 'code' "$SOURCE_ENDPOINT:$SOURCE_PATH" >& /dev/null
check_last_rc "Could not list source directory" "Verified that source is a directory\n"

# Submit sync transfer, get the task ID
globus_output=$(globus transfer --format unix --jmespath 'task_id'  --recursive \
                       --delete --sync-level $SYNCTYPE \
                       "$SOURCE_ENDPOINT:$SOURCE_PATH" \
                       "$DESTINATION_ENDPOINT:$DESTINATION_PATH")

success_msg="Submitted sync from $SOURCE_ENDPOINT:$SOURCE_PATH to $DESTINATION_ENDPOINT:$DESTINATION_PATH"
source_path_enc=$(echo $SOURCE_PATH | sed 's?/?%%2F?g')
destination_path_enc=$(echo $DESTINATION_PATH | sed 's?/?%%2F?g')
# Note the double percent signs and \n for the printf statement
link="Link:\nhttps://app.globus.org/activity/$globus_output/overview\n"
wait_active $globus_output

# Check status
check_last_rc "Globus transfer submission failed" "$success_msg\n$link"

# Save ID of new sync transfer
echo "Saving sync transfer ID to $LAST_TRANSFER_ID_FILE"
echo $globus_output > "$LAST_TRANSFER_ID_FILE"