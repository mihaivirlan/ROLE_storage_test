#!/bin/bash
# Script-Name: 10_Umount_Filesystems.sh
# Owner: Thomas Lambart
# Date: 04. Feb. 2021
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

# the variable MOUNT_DIR is expected to be set in the <ATC>.yml file

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
