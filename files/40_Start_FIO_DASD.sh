#!/bin/bash
# set -x
#-----------------------------------------------------------------------------
#
#
# parameter:
#             CHPIDs="38,39"       "3a,3b"     #-->  optional
#             DASD_fs="c667:ext3,c6a7:ext4,c6c7:xfs"
#             #         DASDs="c667,c6a7,c6c7"
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
# . "${TESTLIBDIR}variables.sh" || exit 1
# . "${TESTLIBDIR}dasd_functions.sh" || exit 1
. "${TESTLIBDIR}lib/toybox/storage/libstorage.sh" || exit 1
. "${TESTLIBDIR}lib/toybox/storage/libdasd.sh" || exit 1

#-----------------------------------------------------------------------------



function make_job_file # build the jobfile.fio
{

  local fio_mountpoints=$1
  > jobfile.fio
  cat ${fio_mountpoints} |
  while read MOUNT_POINT; do
    if [[ `echo ${MOUNT_POINT}` != "" ]]; then
      if grep ${MOUNT_POINT} /proc/mounts > /dev/null 2>&1; then
        fstype=$(stat -f -c %T ${MOUNT_DIR}/${MOUNT_POINT})
        if [ ! -z "$NUMJOBS" ]; then # passed as parameter
          workers=$NUMJOBS
        else # get it from template
          workers=$(cat fio.template | grep "numjobs" | sed -e s/numjobs=//g)
        fi
        fsfree=$(df -k ${MOUNT_DIR}/${MOUNT_POINT} | grep ${MOUNT_DIR}/${MOUNT_POINT} | awk '{print $4}')
        if [ "$fstype" == "btrfs" ]; then
          size=$((${fsfree}/${workers}*40/100))
            else
          size=$((${fsfree}/${workers}*90/100))
        fi
        echo "[${MOUNT_POINT}]"                       > ${MOUNT_POINT}.fio
        cat fio.template                             >> ${MOUNT_POINT}.fio
        echo "size=${size}k"                         >> ${MOUNT_POINT}.fio
        echo "directory=${MOUNT_DIR}/${MOUNT_POINT}" >> ${MOUNT_POINT}.fio
        assert_warn 0 0 "${MOUNT_POINT}.fio created, now merging the lists"
        cat ${MOUNT_POINT}.fio >> jobfile.fio
        echo " "               >> jobfile.fio
      else
        assert_warn 1 0 "${MOUNT_DIR}/${MOUNT_POINT} not mounted"
      fi
      echo
    fi
  done


 if [ ! -z "$NUMJOBS" ]; then
   sed -i "s/numjobs=.*/numjobs=$NUMJOBS/g" jobfile.fio
   echo "jobfile.fio adjusted to numjobs=$NUMJOBS"
 fi


  if [ ! -z "$RUNTIME" ]; then
    sed -i "s/runtime=.*/runtime=$RUNTIME/g" jobfile.fio
    echo "jobfile.fio adjusted to runtime=$RUNTIME"
  fi

}

#-----------------------------------------------------------------------------

while [ $# -gt 0 ]; do
        case "$1" in
                "-m"|"--mountdir")        MOUNT_DIR="$2"; shift; ;;
                "-n"|"--numjobs")         NUMJOBS="$2"; shift; ;;
                "-t"|"--runtime")         RUNTIME="$2"; shift; ;;
                *)
                        echo "Unknown parameter: $1";
                        return 1;
                        ;;
        esac
        shift;
done;

#-----------------------------------------------------------------------------
start_section 1 "check the \"$MOUNT_DIR\" environment variable"
if [[ -z $MOUNT_DIR ]]; then
  echo "\"MOUNT_DIR\" not set !"
  echo "usage $0 -m {MOUNT_DIR}"
  echo "      or, export it as a global variable"
  echo " "
  exit 1
fi


echo "$0 is running with"
echo "RUNTIME    = $RUNTIME"
echo "NUMJOBS    = $NUMJOBS"
echo "MOUNT_DIR  = $MOUNT_DIR"
echo " "


end_section 1

#-----------------------------------------------------------------------------
start_section 1 "make FIO job_file"
make_job_file ${TESTLIBDIR}/fio.mountpoints
end_section 1
#-----------------------------------------------------------------------------
start_section 1 "Install fio, if it does not exist"
FIO_BIN=$(which fio)
if [[ ! $FIO_BIN ]] && [[ ! -x $FIO_BIN ]]; then
    upm -y install fio
    assert_warn $? 0 "Install fio package"
fi

test -x $(which fio)
assert_fail $? 0 "0 = executable fio exists!"
end_section 1


#-----------------------------------------------------------------------------
start_section 1 "Start of device workload via startFIO"
startFIO
assert_fail $? 0 "run fio workload via startFIO"
end_section 1
#-----------------------------------------------------------------------------
