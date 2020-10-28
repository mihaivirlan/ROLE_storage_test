#!/bin/bash
# Script-Name: 20_Setup.sh
# Owner: Thorsten Diehl
# Date: 17.08.2020
# Description: Setting up the partitions or the LVM, create filesystems
# If parameter -reuse_lvs is given, the Logical Volumes are being reused.
#   The LVM must be functional. This can not be achieved after a cleanup!
# It is recommended to specify the file systems to be tested here. If not,
#   only ext3 is being used.
#
#
#
REUSELVS=FALSE
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"
source ${TESTLIBDIR}lib/common/environment.sh || exit 1
source ${TESTLIBDIR}lib/common/results.sh || exit 1
source ${TESTLIBDIR}lib/common/remote.sh || exit 1
source ${TESTLIBDIR}lib/toybox/common/libcommon.sh || exit 1
source ${TESTLIBDIR}00_config-file || exit 1
source ${TESTLIBDIR}functions.sh || exit 1
source ${TESTLIBDIR}variables.sh || exit 1


start_section 0 "Setting up test system"

    FSTYPE=()
    while [ $# -ne 0 ]
    do
        case "$1" in
            --reuse_lvs )
                REUSELVS=TRUE
                ;;
            -reuse_lvs )
                REUSELVS=TRUE
                ;;
            ext2 )
                FSTYPE=("${FSTYPE[@]}" "mkfs.ext2 -q -F")
                ;;
            ext3 )
                FSTYPE=("${FSTYPE[@]}" "mkfs.ext3 -q -F")
                ;;
            ext4 )
                FSTYPE=("${FSTYPE[@]}" "mkfs.ext4 -q -F")
                ;;
            xfs )
                FSTYPE=("${FSTYPE[@]}" "mkfs.xfs -q -f")
                ;;
            btrfs )
                FSTYPE=("${FSTYPE[@]}" "mkfs.btrfs -f")
                ;;
            reiserfs )
                FSTYPE=("${FSTYPE[@]}" "mkfs.reiserfs -q -f")
                ;;
         esac
       shift
    done
    if [ "${#FSTYPE[@]}" -eq 0 ]; then
       FSTYPE=('mkfs.ext3 -q -F')
    fi

    if [ "${REUSELVS}" == "FALSE" ]; then
	    if (isRhel7 || isRhel8); then   
            dmsetup remove_all
            multipath -F
            sleep 1
            multipath
            sleep 3
            multipathd show topo
            sleep 1
        fi

        start_section 1 "Creating a device list for all attached multipath devices"
            createDeviceList
        end_section 1
        start_section 1 "Deleting all Logical Volumes, Volume Groups and Physical Volumes"
            removeLogicalVolumes
            removeVolumegroups
	    removePhysicalVolumes
	    pvscan --cache
        end_section 1

        start_section 1 "Creating one or more partitions"
            createPartition
        end_section 1
        if  [ "${LVM}" == "TRUE" ]; then
            start_section 1 "Modify LVM filter settings"
#                removeLVMfilter
                rm -f /etc/lvm/archive/*
                rm -f /etc/lvm/backup/*
                rm -f /etc/lvm/cache/*
            end_section 1

            sleep 2

            start_section 1 "Creating Physical Volumes"
                createPhysicalVolumes
            end_section 1
        
            start_section 1 "Creating Volume Group"
                createVolumegroups
            end_section 1
            
            start_section 1 "Creating logical volumes"

                start_section 2 "Creates a striped logical volume (LogicalVolume1)"
                    createLogicalVolume1
                end_section  2

                start_section 2 "Creates a mirror logical volume (LogivalVolume2)."
                    createLogicalVolume2
                end_section  2

                start_section 2 "Creates a mirror logical volume (LogicalVolume3)."
                    createLogicalVolume3
                end_section  2

                start_section 2 "Creates a linear logical volume (LogicalVolume4)"
                    createLogicalVolume4
                end_section  2

                start_section 2 "Creates a 2GiB RAID5 logical volume (LogicalVolume5)."
                    createLogicalVolume5
                end_section  2



                start_section 2 "List all created logical volumes"
                    assert_exec 0 "lvs"
                end_section  2
                
            end_section 1
        fi
    else
        assert_warn 0 0 "Reusing existing LVM..."
    fi

# execute this in any case

    if  [ "${LVM}" == "TRUE" ]; then        
            start_section 1 "Creating different filesystems on logical volumes"
                vgchange -an
                sleep 1
                udevadm settle 
		multipath -r
                udevadm settle 
                assert_exec 0 "vgchange -ay"
                sleep 1
                udevadm settle 
                createFilesystemOnLV
            end_section 1

    else
    
            start_section 1 "Creating different filesystems on partitions"
                createFilesystemOnPartition
            end_section 1    

    fi

show_test_results
end_section 0
