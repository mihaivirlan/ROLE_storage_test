#!/bin/bash  
# Script-Name: 80_Unmount_Filesystems.sh
# Owner: Thorsten Diehl
# Date: 13.02.2015
# Description:  Unmounting filesystems 
#
#
#
#
# Load testlib 
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"

source ${TESTLIBDIR}lib/common/environment.sh || exit 1
source ${TESTLIBDIR}lib/common/results.sh || exit 1
source ${TESTLIBDIR}lib/common/remote.sh || exit 1
source ${TESTLIBDIR}00_config-file || exit 1
source ${TESTLIBDIR}functions.sh || exit 1
source ${TESTLIBDIR}variables.sh || exit 1

start_section 0 "Unmounting multiple filesystems from multipath devices"

    start_section 1 "Creating a device list for all attached multipath devices"
        createDeviceList
    end_section 1

    start_section 1 "Unmounting multiple filesystems"
        unmountFilesystem
    end_section 1

end_section 0
