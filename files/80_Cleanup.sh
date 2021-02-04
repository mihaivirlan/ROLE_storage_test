#!/bin/bash
# Script-Name: 80_Cleanup.sh
# Owner: Thorsten Diehl
# Date: 04.02.2021
# Description:  Perform a cleanup
#
# SCSI:
# If parameter --cleanup_lvm is given, the entire LVM and all partitions are removed
# Be aware: the existing deviceList.txt is being considered!
# DASD & EDEV:
# t.b.d.
#

DEBUG=yes
CLEANUP_LVM=FALSE
# Load testlib
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"

source ${TESTLIBDIR}lib/common/environment.sh || exit 1
source ${TESTLIBDIR}lib/common/results.sh || exit 1
source ${TESTLIBDIR}lib/common/remote.sh || exit 1
source ${TESTLIBDIR}lib/toybox/common/libcommon.sh || exit 1
source ${TESTLIBDIR}lib/toybox/storage/libscsi.sh || exit 1
source ${TESTLIBDIR}functions.sh || exit 1
source ${TESTLIBDIR}00_config-file 

# the variable MOUNT_DIR is expected to be set in the <ATC>.yml file

start_section 0 "Cleaning up test system"

    while [ $# -ne 0 ]
    do
       case "$1" in
            --cleanup_lvm )
                CLEANUP_LVM=TRUE
                ;;
        esac
        shift
    done

# unmount filesystems first

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

start_section 1 "Deactivating disks"

    if [ "$MOUNT_DIR" == "/mnt1" ]; then  # path for SCSI LUNs 
        # determine if LVM is used
        if [ "${CLEANUP_LVM}" == "TRUE" ] && [ "${LVM}" == "TRUE" ]; then
            start_section 2 "Removing logical volumes"
                removeLogicalVolumes
            end_section 2

            start_section 2 "Removing volumegroups"
                removeVolumegroups
            end_section 2

            start_section 2 "Removing physical volumes"
                removePhysicalVolumes
            end_section 2

            # delete partition(s)
            start_section 2 "Deleting partition on multipath devices"
                deletePartitions
            end_section 2
        fi

        start_section 2 "Flush all multipath devices"
            dmsetup remove_all
            assert_exec 0 sleep 1
            multipath -F
        end_section 2

        start_section 2 "Stop multipath daemon"
            systemctl is-active multipathd.service
            if [ $? -eq 0 ]; then
                if (isUbuntu); then
                    assert_exec 0 "systemctl stop multipath-tools.service"
                else
                    assert_exec 0 "systemctl stop multipathd.service"
                fi
            fi
        end_section 2

        start_section 2 "Removing SCSI LUNs from test system"
            for ADAPTOR in ${ZFCPADAPTOR[@]}; do
                for WWPN in ${STORAGEPORTS[@]}; do
                    for LUN in ${SCSILUNS[@]}; do
                        if [ $(common::getDistributionName) == rhel-7 ]; then
                            scsi::removeLunSYSFS ${ADAPTOR} ${WWPN} ${LUN}
                        else
                            scsi::removeLun      ${ADAPTOR} ${WWPN} ${LUN}
                        fi
                        assert_fail $? 0 "PASSED if LUN ${LUN} could be removed from adaptor ${ADAPTOR} and remote port ${WWPN}"
                    done
                done
            done
        end_section 2
    fi
    
    if [ "$MOUNT_DIR" == "/mnt2" ] || [ "$MOUNT_DIR" == "/mnt3" ]; then  # path for DASDs and EDEVs
        echo "Thomas, hier gibt's noch was zu tun!"
    fi
  end_section 1
show_test_results
end_section 0
