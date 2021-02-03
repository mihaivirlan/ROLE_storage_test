#!/bin/bash
# Script-Name: 80_Cleanup.sh
# Owner: Thorsten Diehl
# Date: 03.02.2021
# Description:  Perform a cleanup
#
# SCSI:
# If parameter -cleanup_lvm is given, the entire LVM and all partitions are removed
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
source ${TESTLIBDIR}functions.sh || exit 1
source ${TESTLIBDIR}00_config-file 
source ${TESTLIBDIR}variables.sh 

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
                createDeviceList
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
                        if [ -d  /sys/bus/ccw/drivers/zfcp/${ADAPTOR}/${WWPN}/${LUN} ]; then
                            echo ${LUN} > /sys/bus/ccw/drivers/zfcp/${ADAPTOR}/${WWPN}/unit_remove
                            assert_fail $? 0 "PASSED if LUN ${LUN} could be removed from adaptor ${ADAPTOR} and remote port ${WWPN}"
                        else
                            assert_warn 0 0 "LUN ${LUN} could not be found on adaptor ${ADAPTOR} and remote port ${WWPN}"
                        fi
                    done
                done
            done
        end_section 2
    fi
    
    if [ "$MOUNT_DIR" == "/mnt2" ] || [ "$MOUNT_DIR" == "/mnt3" ]; then  # path for DASDs and EDEVs
        # Thomas, hier gibt's noch was zu tun
    fi
  end_section 1
end_section 0
