#!/bin/bash
# Script-Name: 60_Stop_FIO.sh
# Owner: Thorsten Diehl
# Date: 20.12.2016
# Description:  Stop FIO filesystem I/O
#
#
#
DEBUG=yes
# Load testlib
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"

source ${TESTLIBDIR}lib/common/environment.sh || exit 1
source ${TESTLIBDIR}lib/common/results.sh || exit 1
source ${TESTLIBDIR}lib/common/remote.sh || exit 1
#source ${TESTLIBDIR}00_config-file || exit 1
[[ -r ${TESTLIBDIR}00_config-file ]] && source ${TESTLIBDIR}00_config-file
source ${TESTLIBDIR}functions.sh || exit 1
source ${TESTLIBDIR}variables.sh || exit 1

start_section 0 "Stopping FIO"
    stopFIO
end_section 0
