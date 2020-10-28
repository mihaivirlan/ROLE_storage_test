#!/bin/bash
# Script-Name: 40_Start_FIO.sh
# Owner: Thorsten Diehl
# Date: 16.01.2017
# Description:  Start FIO on each file system
#
# 23.01.2020 Thomas Lambart fio via upm
# 01.04.2020 TDI: fio availabitily detection modified
#                 upm install of libaio-devel added
#                 createFIOLists executed unconditionally
#
#
DEBUG=yes
# Load testlib
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"

source ${TESTLIBDIR}lib/common/environment.sh || exit 1
source ${TESTLIBDIR}lib/common/results.sh || exit 1
source ${TESTLIBDIR}lib/common/remote.sh || exit 1
# source ${TESTLIBDIR}00_config-file || exit 1
source ${TESTLIBDIR}functions.sh || exit 1
source ${TESTLIBDIR}variables.sh || exit 1
[[ -r ${TESTLIBDIR}00_config-file ]] && source ${TESTLIBDIR}00_config-file

start_section 0 "Starting FIO against mounted filesystems"

  start_section 1 "Install fio, if it does not exist"
    if [ ! $(which fio) ]; then
      "${TESTLIBDIR}"lib/upm/upm.sh -y install libaio-devel
      assert_warn $? 0 "Install libaio-devel package"
      "${TESTLIBDIR}"lib/upm/upm.sh -y install fio
      assert_warn $? 0 "Install fio package"
    fi

    which fio
    assert_fail $? 0 "0 = executable fio exists!"
  end_section 1

  start_section 1 "Creating fio files for each mountpoint"
    if [ ! -z "$1" ]; then
        NUMJOBS=$1
    fi
    createFIOLists $NUMJOBS
  end_section 1

  start_section 1 "Starting FIO"
    startFIO
  end_section 1

end_section 0
