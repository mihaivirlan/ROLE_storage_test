#!/bin/bash
# Script-Name: 50_Collect_Ziomon_Data.sh
# Owner: Thorsten Diehl
# Date: 13.12.2016
# Description:  Collect ziomon data
#
# 07. May 21: TL changes for $RUN   "... elif...else... fi"
# 31. Mar 22: TD change to exclude system volumes from ziomon
#
# Load testlib
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"
source ${TESTLIBDIR}lib/common/environment.sh || exit 1
source ${TESTLIBDIR}lib/common/results.sh || exit 1
source ${TESTLIBDIR}lib/common/remote.sh || exit 1

start_section 0 "Collect ziomon data for all multipath devices"
    while getopts d:i:l:o:r: opt
        do
        case "$opt" in
            d) DURATION="$OPTARG";;
            i) INTERVALL_LENGTH="$OPTARG";;
            l) LIMIT="$OPTARG";;
            o) DATAFILE="$OPTARG";;
            r) RUN="$OPTARG";;
        esac
    done
    shift $(expr $OPTIND - 1)

    echo ""
    echo "ziomon command options:"
    echo "-d: Overall monitoring duration in minutes = ${DURATION}"
    echo "-i: Time to elapse between recording data in seconds = ${INTERVALL_LENGTH}"
    echo "-l: Upper limit of the output files = ${LIMIT}"
    echo "-o: Basename for output files = ${DATAFILE}"
    echo "-r: Run script YES/No = ${RUN}"
    echo ""

    RUN=$(echo ${RUN} | tr [a-z] [A-Z])
    if [ "${RUN}" == "YES" ]; then

        start_section 1 "mount debugfs"
            umount /sys/kernel/debug > /dev/null 2>&1
            ls /sys/kernel/debug >> /dev/null 2>&1
            assert_fail $? 0 "check whether sysfs entry for debugfs is created or not"
            sleep 1
            mount none -t debugfs /sys/kernel/debug >> /dev/null 2>&1
            mount | grep debugfs >> /dev/null 2>&1
        end_section 1

#        DEVICELIST=$(ls /dev/mapper/ | grep mpath | grep -v "[1-9]$\|p[1-9]\|-p[1-9]\|-part[1-9]\|_part[1-9]" | sed s'/mpath/\/dev\/mapper\/mpath/'g)  # including all multipath volumes
        DEVICELIST=$(cat ./deviceList.txt | awk '{print $1}' | sed s%/dev/disk/by-id/dm-name-mpath%/dev/mapper/mpath%g)    # using only the multipath volumes under test, as listed in deviceList.txt

        echo "ziomon -d ${DURATION} -i ${INTERVALL_LENGTH} -l ${LIMIT} -o ${DATAFILE}  ${DEVICELIST}"
        ziomon -d ${DURATION} -i ${INTERVALL_LENGTH} -l ${LIMIT} -o ${DATAFILE}  ${DEVICELIST}
        assert_fail $? 0 "PASSED if ziomon could collect data"

    elif [ "${RUN}" == "NO" ]; then
        assert_warn 0 0 "ZIOMON disabled by user - option \"-r\" set to \"No\""

    else
        assert_fail 1 0 "ZIOMON stopped, no valid value for \"-r\" option"
    fi
end_section 0
