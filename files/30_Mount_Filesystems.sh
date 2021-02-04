#!/bin/bash  
# Script-Name: 30_Mount_Filesystems.sh
# Owner: Thorsten Diehl
# Date: 04.03.2021
# Description:  Mounting filesystems of logical volumes
#               or of the partitions under test
#
#
#
# Load testlib 
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"

source ${TESTLIBDIR}lib/common/environment.sh || exit 1
source ${TESTLIBDIR}lib/common/results.sh || exit 1
source ${TESTLIBDIR}lib/common/remote.sh || exit 1
source ${TESTLIBDIR}lib/toybox/common/libcommon.sh || exit 1
source ${TESTLIBDIR}00_config-file || exit 1
source ${TESTLIBDIR}functions.sh || exit 1

start_section 0 "Mounting filesystems"
    if [ "${LVM}" == "TRUE" ]; then
        mountingLogicalVolumes
    else
        mountingPartitions
    fi
end_section 0
