#!/bin/bash
# Script-Name: 90_Remove_LVM.sh 
# Owner: Thorsten Diehl
# Date: 13.02.2015
# Description:  Remove LVM and LUNs (for debug purposes)
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


start_section 0 "Removing LVM setup (logical volumes, volume groups and physical volumes)"

    start_section 1 "Unmount logical volumes if neccessary"
        unmountFilesystem    
    end_section 1
   
    start_section 1 "Removing logical volumes"
        removeLogicalVolumes
    end_section 1

    start_section 1 "Removing volumegroups"
        removeVolumegroups
    end_section 1

    start_section 1 "Removing physical volumes"
        removePhysicalVolumes
    end_section 1

    start_section 1 "Deleting LVM partition on multipath devices"
        createDeviceList
        deletePartitions    
        multipath -F 
    end_section 1
 
show_test_results
end_section 0
