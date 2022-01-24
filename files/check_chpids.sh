#!/bin/bash

# Load testlib
TESTLIBDIR="${TESTLIBDIR:-$(dirname $(readlink -f "$0"))}"
source ${TESTLIBDIR}/lib/common/results.sh || exit 1

checkCHPIDs () {

DASD_PATH='/root/DASD_cablepull_fio'
SCSI_PATH='/root/SCSI_cablepull_fio'
CHECK_PATH=$1

if [[ "$CHECK_PATH" == "$DASD_PATH" ]]; then
      lsdasd -l |grep paths_in_use |cut -f 2 -d: |while read CHPIDs
    do
      CHPIDs_count=$(echo $CHPIDs |wc -w)
      if [[ $CHPIDs_count -lt 4 ]]; then
         assert_fail 1 0 "Not all channel paths are online! Please, firstly make sure that all chpids are online!"
         echo "If you read this line, it's not ok, it means that your checkCHPIDs function doesn't work as expected!"
      else
        # RC=$?
        # echo " \$RC   $RC"
         [[ $CHPIDs_count -ge 4 ]] && assert_warn $? 0 0 "All channel paths id's are online!"
      fi
    done
fi

}

#echo $_dir
#echo -e "PWD  $(dirname $0)"
#echo -e "PWD = $PWD"
checkCHPIDs /root/DASD_cablepull_fio
#checkCHPIDs $_dir