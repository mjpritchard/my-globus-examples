#!/bin/bash

# ARCHER2 file systems
SOURCE_ENDPOINT='3e90d018-0d05-461a-bbaf-aab605283d21'

# JASMIN Default Collection
DESTINATION_ENDPOINT='a2f53b7f-1b4e-4dce-9b7c-349ae760fee0'

# Sample data
SOURCE_PATH='/src/path/'

# Destination Path
# The directory will be created if it doesn't exist
DESTINATION_PATH='/dst/path/'

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

# Submit sync transfer, get the task ID
task_id=$(globus transfer --format unix --jmespath 'task_id'  --recursive \
                       --delete --sync-level $SYNCTYPE \
                       "$SOURCE_ENDPOINT:$SOURCE_PATH" \
                       "$DESTINATION_ENDPOINT:$DESTINATION_PATH")

success_msg="Submitted sync from $SOURCE_ENDPOINT:$SOURCE_PATH to $DESTINATION_ENDPOINT:$DESTINATION_PATH"
source_path_enc=$(echo $SOURCE_PATH | sed 's?/?%%2F?g')
destination_path_enc=$(echo $DESTINATION_PATH | sed 's?/?%%2F?g')
# Note the double percent signs and \n for the printf statement
link="https://app.globus.org/activity/$task_id/overview"

echo "Task submitted, see here:\n$link"
echo "Waiting"
globus task wait -H $task_id

