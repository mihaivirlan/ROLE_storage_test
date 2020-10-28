#!/bin/bash  
# Script-Name: 70_LUN_Status.sh
# Owner: Thorsten Diehl
# Date: 29.05.2020
# Description:  Checking port and LUN Status after test and also multipath status
#
#
#
#
DEBUG=yes
# Load testlib 
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"

source ${TESTLIBDIR}lib/common/environment.sh || exit 1
source ${TESTLIBDIR}lib/common/results.sh || exit 1
source ${TESTLIBDIR}lib/common/remote.sh || exit 1
source ${TESTLIBDIR}00_config-file || exit 1
source ${TESTLIBDIR}functions.sh || exit 1
source ${TESTLIBDIR}variables.sh || exit 1


start_section 0 "Verifying SCSI LUN status at test end"

    checkZfcpStatus
    
end_section 0

start_section 0 "Verifying multipath status at test end"

    multipathd show topo
    n=`multipathd show topo |grep "0:" |grep "failed\|faulty\|offline" |wc -l`
    if [ $n -eq 0 ]; then
      assert_warn 0 0 "All multipaths are ok after test"
    else
      assert_warn $n 0 "$n multipaths are in a bad condition; please check"
    fi

end_section 0
