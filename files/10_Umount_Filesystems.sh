#!/bin/bash
# Script-Name: 10_Umount_Filesystems.sh
# Owner: Thomas Lambart
# Date: 03. Feb. 2021
# Description:  Perform an unmount of file systems
#
#
#

# Load testlib
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"

source ${TESTLIBDIR}lib/common/environment.sh || exit 1
source ${TESTLIBDIR}lib/common/results.sh || exit 1
source ${TESTLIBDIR}lib/common/remote.sh || exit 1
source ${TESTLIBDIR}functions.sh || exit 1

# determine the type of ATC to compute the variable MOUNT_DIR
echo $(basename $(pwd)) | grep SCSI_ && MOUNT_DIR="/mnt1" 
echo $(basename $(pwd)) | grep DASD_ && MOUNT_DIR="/mnt2" 
echo $(basename $(pwd)) | grep EDEV_ && MOUNT_DIR="/mnt3" 

start_section 1 "Unmounting filesystems"
    echo "$0 is running with"
    echo "MOUNT_DIR  = $MOUNT_DIR"
    echo " "
    if [ "$MOUNT_DIR" != "" ]; then
      unmountFilesystem
    else
      echo "No valid mount directory determined, exiting..."
      exit 1;
    fi
end_section 1
