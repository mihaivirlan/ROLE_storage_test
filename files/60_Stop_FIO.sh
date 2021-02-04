#!/bin/bash
# Script-Name: 60_Stop_FIO.sh
# Owner: Thorsten Diehl
# Date: 04.02.2021
# Description:  Stop FIO filesystem I/O
#
# 29.01.2021 TL removed variables.sh
#                $MOUNT_DIR and $FIO_LOG_DIR should now in the ansible *yml file
#                set.
#                e.g. in the host part:
#                     |- hosts: DASD_fio_basic
#                     |  roles:
#                     |    - DASD_fio_basic
#                     |  environment:
#                     |    MOUNT_DIR: "/mnt2"
#                     |    FIO_LOG_DIR: "/root/DASD_fio_basic/log"
#
#
#
DEBUG=yes
# Load testlib
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"

source ${TESTLIBDIR}lib/common/environment.sh || exit 1
source ${TESTLIBDIR}lib/common/results.sh || exit 1
source ${TESTLIBDIR}lib/common/remote.sh || exit 1
source ${TESTLIBDIR}functions.sh || exit 1
[[ -r ${TESTLIBDIR}00_config-file ]] && source ${TESTLIBDIR}00_config-file

start_section 0 "Stopping FIO"
    stopFIO
end_section 0
