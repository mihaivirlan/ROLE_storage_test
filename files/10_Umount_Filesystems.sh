#!/bin/bash
# Script-Name: 10_Umount_Filesystems.sh
# Owner: Thomas Lambart
# Date: 03. Feb. 2021
# Description:  Perform a unmount_file_systems
#
#
#

# Load testlib
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"

source ${TESTLIBDIR}lib/common/environment.sh || exit 1
source ${TESTLIBDIR}lib/common/results.sh || exit 1
source ${TESTLIBDIR}lib/common/remote.sh || exit 1
source ${TESTLIBDIR}functions.sh || exit 1

start_section 1 "Unmounting filesystems"
    echo "$0 is running with"
    echo "MOUNT_DIR  = $MOUNT_DIR"
    echo " "
    unmountFilesystem
end_section 1
