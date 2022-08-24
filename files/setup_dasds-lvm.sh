#!/bin/bash
# set -x
#-----------------------------------------------------------------------------
# # Script-Name: setup_dasds_lvm.sh
# Owner: Thomas Lambart
# Date: 04.07.2022
# Description:
#  This script
#  - enables the given DASDs,FBAs and MINIDISKs
#  - enables the given DASD for LVM
#  - enables the given DASD-aliasse
#  - creates one or two (if the cylinder count >65520, EAV) partitions on the DASDs
#  - make the LMG set up PVs, VGs, LVs
#  - make the given file system on the partitions (ext2-4, xfs)
#
#        $DEVICE_LIST, $MOUNT_DIR and $FIO_LOG_DIR should now set in the ansible playbook.
#        e.g. in the host part:
#             |- hosts: DASD_basic_fio_v2
#             |  roles:
#             |    - DASD_basic_fio_v2
#             |  environment:
#             |     DEVICE_LIST: "dasd-deviceList.txt"
#             |    MOUNT_DIR: "/mnt2"
#             |    FIO_LOG_DIR: "/root/DASD_LVM_fio/log"
#
#
# parameter:
#    e.g.: setup_dasds.sh -a "c6e0-c6e3" -d "c667:ext3,c6a7:ext4,c6c7:xfs" -c "38,39" -m /mnt2
#    -a [aliasse]
#    -md [username:virt_addr1,username:virt_addr2,...,username:virt_addrn]
#    -d [Bus-ID1:FS_type,Bus-ID2:FS_type,....,Bus-IDn:FS_type]
#    -c for the CHPIDs is optional
#    -m MOUNT_DIR is optional, could also be a global variable "$MOUNT_DIR"
#    -lvm DASDs for LVM usage e.g. "c800-c80f"
#    --reuse_lvs use the existing LVs on the DASDs
#
#
#
#
#
#-----------------------------------------------------------------------------
# Load testlib
REUSELVS=FALSE
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"
. "${TESTLIBDIR}lib/common/results.sh" || exit 1
. "${TESTLIBDIR}lib/common/environment.sh" || exit 1
. "${TESTLIBDIR}functions.sh" || exit 1
. "${TESTLIBDIR}lib/toybox/storage/libstorage.sh" || exit 1
. "${TESTLIBDIR}lib/toybox/storage/libdasd.sh" || exit 1
. "${TESTLIBDIR}00_config-file" || exit 1



DEVICE_LIST=${TESTLIBDIR}dasd-deviceList.txt

#-----------------------------------------------------------------------------
usage () {
  echo "usage: $0 -lvm  \"[DASDs for lvm-usage\"] "
  echo "           e.g. -lvm \"c800-c80f\"  "
  echo " [-a \"aliasse\"]"
  echo "           e.g. \"c6e0-c6e3\""
  echo " [-md \"[MDISKOWNER:virt_addr1,MDISKOWNER:virt_addr2,...,MDISKOWNER:virt_addrn]\" ]"
  echo "           e.g  \"linmdisk:0201,linmdisk:0202,linmdisk:0203\" "
  echo " [-c  \"[CHPID1,CHPID2]\"] "
  echo "           e.g. -c \"38,39\" or -c \"3a,3b\" "
  echo " [-m  \"[MOUNT_DIR\"] "
  echo "           e.g. -m /mnt2"
  echo " [-fs  \"[filesystem for lv\"] "
  echo "           e.g. -fs \"xfs ext4 ext3\" "
  echo " [-reuse_lvs] "
  echo ""
  echo "e.g.: $0 -reuse_lvs -fs \"xfs ext4 ext3\" -lvm \"c800-c80f\"  -c \"38,39\" -m /mnt2 -reuse_lvs"
  echo "      -c for the CHPIDs is optional"
  echo "      -m MOUNT_DIR is optional, must be set at least as a global variable \"\$MOUNT_DIR\""
  echo ""

}
#-----------------------------------------------------------------------------

start_section 0 "Start of setup_dasds.sh"

start_section 1 "Start of the parameter parsing"

    while [ $# -gt 0 ]; do
            case "$1" in
					"-reuse_lvs"|"--reuse_lvs" ) REUSELVS="TRUE" ;;
					"-a"|"--aliasse")         DASD_ali="$2"; shift; ;;
                    "-c"|"--chpid")           CHPIDs="$2"; shift; ;;
                    "-md"|"--minidisk")       MINIDISK="$2"; shift; ;;
                    "-m"|"--mountdir")        MOUNT_DIR="$2"; shift; ;;
                    "-lvm"| "--LVM_DASDs" )	  LVM_DASDs="$2"; shift; ;;
                    "-fs"| "--FILESYSTEMS" )	  FS="$2"; shift; ;;
                    *)
                            echo "Unknown parameter: $1"; ;;
            esac
            shift;
    done

    #-----------------------------------------------------------------------------
    # parameter check

    echo ""
    echo "Script settings:"
    echo "-reuse_lvs                    = ${REUSELVS}"
    echo "-a    aliasse                 = ${DASD_ali}"
    echo "-c    chpid                   = ${CHPIDs}"
    echo "-md   minidisk                = ${MINIDISK}"
    echo "-m    MOUNT_DIR               =  $MOUNT_DIR"
    echo "-lvm  LVM_DASDs               =  $LVM_DASDs"
    echo "-fs   Files system for lvs    =  $FS"
    echo ""

    ## ${CHPIDs} is optional
    if [[ -z ${LVM_DASDs} ]] || [[ -z ${MOUNT_DIR} ]] ; then
      usage
      end_section 1 "End of the parameter parsing"
      exit 1
    fi

end_section 1 "End of the parameter parsing"


#------------------------------------------------------------------------------#
start_section 1 "delete \"\${DEVICE_LIST}\" ${DEVICE_LIST}"
    echo "rm -f ${DEVICE_LIST}"
    rm -f ${DEVICE_LIST}
end_section 1
#------------------------------------------------------------------------------#
start_section 1 "create the config file"
  # is needed for post scripts
  echo "# `date` " > ${TESTLIBDIR}DASD.conf
  assert_exec 0 "ls -l ${TESTLIBDIR}DASD.conf"
end_section 1

#------------------------------------------------------------------------------#
# check/configure if chp-id are configured
start_section 1 "check/configure if chp-id are configured"
  if [[ -n ${CHPIDs} ]]; then
      for I in ${CHPIDs//,/ };do
        Cfg=`lschp |grep ^0.${I} |awk ' {print $3}'`
        if [[ ${Cfg} -eq 0 ]]; then
          chchp -c 1 ${I}
        fi
      done
  else
      echo "no CHPIDs for check"
  fi
end_section 1

#------------------------------------------------------------------------------#

# enable DASD aliasse
start_section 1 "enable DASD aliasse"
  if [[ -n ${DASD_ali} ]]; then
      dasd::enable ${DASD_ali}
      echo "DASD_ali=${DASD_ali}" >> ${TESTLIBDIR}/DASD.conf
  fi
end_section 1
#------------------------------------------------------------------------------#
# enable DASD for LVM
if [[ -n ${LVM_DASDs} ]]; then
	start_section 1 "enable DASD for lvm"
	      dasd::enable ${LVM_DASDs}
	      echo "LVM_DASDs=${LVM_DASDs}" >> ${TESTLIBDIR}/DASD.conf
	end_section 1
	#------------------------------------------------------------------------------#

	start_section 1 "make the partitions"
	for DASD in $(zdev::generateDeviceIds ${LVM_DASDs}); do
		dev_name=`lsdasd -s ${DASD} |grep ${DASD} | awk ' { print $3 }'`
		dasd_type=`lsdasd -s ${DASD} |grep ${DASD} | awk ' { print $5 }'`
		# check DASD-format and type
		if [[ $(storage::getDASDFormatLayout /dev/${dev_name}) == "NOT" && $dasd_type == "ECKD" ]]; then
			echo "unformatted DASD ${DASD} (/dev/${dev_name}) will now be formatted)"
			storage::DASDFormat -d /dev/${dev_name}
			# make a default partition:
	        sleep 1 #waitng for dasd-format
			fdasd -a /dev/${dev_name}
	        sleep 1 #waitng for dasd-format
		fi

		# add to ${DEVICE_LIST}
		if [[ -e "/dev/${dev_name}1" ]];then
			echo "/dev/${dev_name}" >> ${DEVICE_LIST}
		else
			assert_fail 1 0 "partition /dev/${dev_name}1 not found!"
		fi
	done

	end_section 1
fi

#------------------------------------------------------------------------------#
start_section 0 "Setting up test system"

FSTYPE=()
for I in $FS
do
	case "$I" in
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
	 esac
   shift
done

if [ "${#FSTYPE[@]}" -eq 0 ]; then
   FSTYPE=('mkfs.ext3 -q -F')
fi

if [ "${REUSELVS}" == "FALSE" ]; then
	if (isRhel7 || isRhel8); then
		dmsetup remove_all
	fi
fi

start_section 1 "make the LVM and file systems"


if [ "${REUSELVS}" == "FALSE" ]; then
	start_section 1 "Deleting all Logical Volumes, Volume Groups and Physical Volumes"
	        removeLogicalVolumes
	        removeVolumegroups
		    removePhysicalVolumes
		    pvscan --cache
	end_section 1

	if  [ "${LVM}" == "TRUE" ]; then
		start_section 1 "Modify LVM filter settings"
		#removeLVMfilter
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
    vgchange -an
    sleep 1
    udevadm settle
    # multipath -r
    udevadm settle
    assert_exec 0 "vgchange -ay"
    sleep 1
    udevadm settle
    end_section 1

fi
end_section 1

#------------------------------------------------------------------------------#
# execute this in any case

if  [ "${LVM}" == "TRUE" ]; then
    start_section 1 "Creating different filesystems on logical volumes"
        if [ $(lvs |wc -l) -eq 0 ]; then
            assert_fail 0 1 "no logical volumes found"
        fi
        createFilesystemOnLV
    end_section 1
else
    start_section 1 "Creating different filesystems on partitions"
        createFilesystemOnPartition
    end_section 1
fi

show_test_results
end_section 0

#------------------------------------------------------------------------------#

#------------------------------------------------------------------------------#


#####
