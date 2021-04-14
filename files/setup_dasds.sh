#!/bin/bash
# set -x
#-----------------------------------------------------------------------------
# # Script-Name: setup_dasds.sh
# Owner: Thomas Lambart
# Date: 14. Jan. 2021
# Description:
#  This script
#  - enables the given DASDs,
#  - enables the given DASD-aliasse
#  - creates one or two (if the cylinder count >65520, EAV) partitions on the DASDs
#  - make the given file system on the partitions (ext2-4, xfs)
#  - mount the filesystems at $MOUNT_DIR which an environment variable is, or
#    the parameter -m (optional).
#
#        $MOUNT_DIR and $FIO_LOG_DIR should now set in the ansible playbook.
#        e.g. in the host part:
#             |- hosts: DASD_basic_fio_v2
#             |  roles:
#             |    - DASD_basic_fio_v2
#             |  environment:
#             |    MOUNT_DIR: "/mnt2"
#             |    FIO_LOG_DIR: "/root/DASD_basic_fio_v2/log"
#
#
# parameter:
#    e.g.: setup_dasds.sh -a "c6e0-c6e3" -d "c667:ext3,c6a7:ext4,c6c7:xfs" -c "38,39" -m /mnt2
#    -a [aliasse]
#    -d [Bus-ID1:FS_type,Bus-ID2:FS_type,....,Bus-IDn:FS_type]
#    -c for the CHPIDs is optional
#    -m MOUNT_DIR is optional, could also be a global variable "$MOUNT_DIR"
#
#
#
#
#
#
#-----------------------------------------------------------------------------
# Load testlib
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"
. "${TESTLIBDIR}lib/common/results.sh" || exit 1
. "${TESTLIBDIR}lib/common/environment.sh" || exit 1
. "${TESTLIBDIR}functions.sh" || exit 1
. "${TESTLIBDIR}lib/toybox/storage/libstorage.sh" || exit 1
. "${TESTLIBDIR}lib/toybox/storage/libdasd.sh" || exit 1

#-----------------------------------------------------------------------------
usage () {
  echo "usage: $0 -d \"[Bus-ID1:FS_type,Bus-ID2:FS_type,....,Bus-IDn:FS_type]\"  "
  echo "           e.g. \"c667:ext3,c6a7:ext4,c6c7:xfs\" "
  echo " [-a \"aliasse\"]"
  echo "           e.g. \"c6e0-c6e3\""
  echo " [-c  \"[CHPID1,CHPID2]\"] "
  echo "           e.g. -c \"38,39\" or -c \"3a,3b\" "
  echo " [-m  \"[MOUNT_DIR\"] "
  echo "           e.g. -m /mnt2"
  echo ""
  echo "e.g.: $0 -d \"c667:ext3,c6a7:ext4,c6c7:xfs\" -c \"38,39\" "
  echo "      -c for the CHPIDs is optional"
  echo "      -m MOUNT_DIR is optional, must be set at least as a global variable \"\$MOUNT_DIR\""
  echo ""

}
#-----------------------------------------------------------------------------

start_section 0 "Start of setup_dasds.sh"

start_section 1 "Start of the parameter parsing"

    while [ $# -gt 0 ]; do
            case "$1" in
                    "-a"|"--aliasse")        DASD_ali="$2"; shift; ;;
                    "-d"|"--devices")        DASD_fs="$2"; shift; ;;
                    "-c"|"--chpid")          CHPIDs="$2"; shift; ;;
                    "-m"|"--mountdir")        MOUNT_DIR="$2"; shift; ;;
                    *)
                            echo "Unknown parameter: $1"; ;;
            esac
            shift;
    done
    #-----------------------------------------------------------------------------
    # parameter check
    DASDs=""
    for I in ${DASD_fs//,/ };do
      DASDs="${DASDs} ${I%:*}"
    done
    echo ""
    echo "Script settings:"
    echo "-a    aliasse                 = ${DASD_ali}"
    echo "-c    chpid                   = ${CHPIDs}"
    echo "-d    dasd devices(FS-type)   = ${DASD_fs}"
    echo "-m    MOUNT_DIR               =  $MOUNT_DIR"
    echo ""

    ## ${CHPIDs} is optional
    ## if [[ -z ${CHPIDs} ]] || [[ -z ${DASD_fs} ]] ; then
    if [[ -z ${DASD_fs} ]] || [[ -z ${MOUNT_DIR} ]] ; then
      usage
      end_section 1 "End of the parameter parsing"
      exit 1
    fi

end_section 1 "End of the parameter parsing"
#------------------------------------------------------------------------------#
start_section 1 "create the config file"
  echo "# `date` " > ${TESTLIBDIR}/DASD.conf
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
  fi
end_section 1

#------------------------------------------------------------------------------#
#enable the dasd
start_section 1 "enable the dasd"
  # for I in ${DASD_fs//,/ };do               # c667:ext3
  for DASD in ${DASDs};do
    dasd::enable 0.0.${DASD}
    # check the dasd
    lsdasd -c ${DASD} > /dev/null
    if [[ $? -ne 0 ]] ;then
       echo "error while enabling DASD ${DASD}"
       end_section 1
      exit 1
    fi
  done
  if [[ -n ${DASDs} ]]; then
    echo "DASDs=\"${DASDs}\"" >> ${TESTLIBDIR}/DASD.conf
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
start_section 1 "make the partitions and file systems"
for I in ${DASD_fs//,/ }; do
  DASD=${I%:*}
  FS_t=${I##*:}
  dev_name=`lsdasd -s ${DASD} |grep ${DASD} | awk ' { print $3 }'`
  dasd_type=`lsdasd -s ${DASD} |grep ${DASD} | awk ' { print $5 }'`
  # check DASD-format and type
  if [[ $(storage::getDASDFormatLayout /dev/${dev_name}) == "NOT" && $dasd_type == "ECKD" ]]; then
    echo "unformatted DASD ${DASD} (/dev/${dev_name}) will now be formatted)"
    storage::DASDFormat -d /dev/${dev_name}
  fi

#------------------------------------------------------------------------------#
# create partitions; overwrite everything
  case "$(storage::getDASDFormatLayout /dev/${dev_name})" in
      CDL)
          # get number of cylinders
          CYLINDERS=`parted -s /dev/${dev_name} -- unit cyl print |grep /dev/${dev_name} |cut -f2 -d':'`;
          if [[ ${CYLINDERS%cyl} -gt 524122 ]]; then
            ## if more then 524122 cyl then we have an "EAV DASD" and will create two partitions
            echo "storage::mkpart \"/dev/${dev_name}:dasd:ext3 0% 75%,ext3 75% 100%\"";
            storage::mkpart "/dev/${dev_name}:dasd:ext3 0% 75%,ext3 75% 100%" 2>&1;
          else 
            ## normal DASD; one partition only
            echo "storage::mkpart \"/dev/${dev_name}:dasd:ext3 0% 100%\"";
            storage::mkpart "/dev/${dev_name}:dasd:ext3 0% 100%"  2>&1;
          fi
          ;;
      LDL)
          echo "storage::mkpart \"/dev/${dev_name}:gpt:ext3 0% 100%\"";
          storage::mkpart "/dev/${dev_name}:gpt:ext3 0% 100%"  2>&1;
          ;;
      *)
          echo "unexpected error; DASD format type unknown";
          return 1;
          ;;
  esac;

  echo "make the file systems, wait 3 sec.for the partitions"
  sleep 3
  for DEVs in `ls -1 /dev/${dev_name}[1-9]`; do
    if [[ ${FS_t} = ext[2-4] ]]; then
        echo "mkfs.${FS_t} ${DEVs}"
        yes | mkfs.${FS_t} ${DEVs}
    fi

    if [[ ${FS_t} = xfs ]]; then
        echo "mkfs.${FS_t} ${DEVs}"
        mkfs.${FS_t} -f ${DEVs}
    fi
  done

done
end_section 1
#------------------------------------------------------------------------------#
# mount the partitions/file systems
start_section 1 "mount the file systems"
mkdir -p ${MOUNT_DIR}

for I in ${DASDs//,/ };do
  dev_name=`lsdasd -s ${I} |grep ${I} | awk ' { print $3}'`
  for m_dev in `ls  -1 /dev/${dev_name}[1-9]`;do
    m_point=`echo ${m_dev^^} |cut -f3 -d '/'`
    mkdir -p ${MOUNT_DIR}/${m_point}
    assert_exec 0 "mount ${m_dev} ${MOUNT_DIR}/${m_point}"
    # create the mountpoini-list for make_job_file
    echo "${m_point}" >> ${TESTLIBDIR}/fio.mountpoints
  done
done
end_section 1
#------------------------------------------------------------------------------#

end_section 0
#####
