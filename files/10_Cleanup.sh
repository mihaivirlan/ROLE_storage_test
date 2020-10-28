#!/bin/bash
# Script-Name: 10_Cleanup.sh
# Owner: Thorsten Diehl
# Date: 13.12.2016
# Description:  Perform a cleanup
# If parameter -cleanup_all is given, the entire LVM and all partitiona are removed
# Be aware: the existing deviceList.txt is being considered!
#
#
#

DEBUG=yes
DOCLEANUP=FALSE
# Load testlib
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"

source ${TESTLIBDIR}lib/common/environment.sh || exit 1
source ${TESTLIBDIR}lib/common/results.sh || exit 1
source ${TESTLIBDIR}lib/common/remote.sh || exit 1
source ${TESTLIBDIR}00_config-file || exit 1
source ${TESTLIBDIR}functions.sh || exit 1
source ${TESTLIBDIR}variables.sh || exit 1

start_section 0 "Cleaning up test system"

    while [ $# -ne 0 ]
    do
       case "$1" in
            --cleanup_all )
                DOCLEANUP=TRUE
                ;;
            -cleanup_all )
                DOCLEANUP=TRUE
                ;;
        esac
        shift
    done

# unmount filesystems first

    start_section 1 "Unmounting filesystems"
        unmountFilesystem
    end_section 1

    if [ "${DOCLEANUP}" == "TRUE" ]; then

# determine if LVM is used

        if [ "${LVM}" == "TRUE" ]; then
            start_section 1 "Removing logical volumes"
                removeLogicalVolumes
            end_section 1

            start_section 1 "Removing volumegroups"
                removeVolumegroups
            end_section 1

            start_section 1 "Removing physical volumes"
                removePhysicalVolumes
            end_section 1
        fi

# delete partion(s)

        start_section 1 "Deleting partition on multipath devices"
            createDeviceList
            deletePartitions
        end_section 1

        start_section 1 "Flush all multipath devices"
            dmsetup remove_all
            assert_exec 0 sleep 1
            multipath -F
        end_section 1

        start_section 1 "Stop multipath daemon"
            which systemctl 2>/dev/null
            if [ $? -eq 0 ]; then
                systemctl is-active multipathd.service
                if [ $? -eq 0 ]; then
                    if (isUbuntu); then
                        assert_exec 0 "systemctl stop multipath-tools.service"
                    else
                        assert_exec 0 "systemctl stop multipathd.service"
                    fi
                fi
            else
                service multipathd status
                RC=$?
                if [ ${RC} -eq 0 ]; then
                    assert_exec 0 "service multipathd stop"
                fi
            fi
        end_section 1

        start_section 1 "Removing SCSI LUNs from test system"
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
        end_section 1
    else

        assert_warn 0 0 "Cleanup skipped by user"

    fi

end_section 0
