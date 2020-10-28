#!/bin/bash

#set -x

# Load testlib
TESTLIBDIR="/usr/local/tp4/default/lib"
source ${TESTLIBDIR}/common/results.sh || exit 1
source ${TESTLIBDIR}/common/environment.sh || exit 1
source ${TESTLIBDIR}/common/remote.sh || exit 1

### Perform SCSI inquiry for all SCSI LUNs to determine availabilty after error injection

start_section 0 "Verify if all pathes are still available"

multipath -ll
multipath -ll |grep 'failed'
assert_warn $? 1 "All pathes are still available"

end_section 0
