#!/bin/bash
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"
source ${TESTLIBDIR}lib/common/environment.sh || exit 1
source ${TESTLIBDIR}00_config-file || exit 1
source ${TESTLIBDIR}lib/common/results.sh || exit 1

usage(){

    echo "usage : ./ValidateKernalParm.sh -o <dif|dix> "
    exit 0
}

while getopts o: opt
    do
    case "$opt" in
        o) dc="$OPTARG";;
    esac
done
shift $(expr $OPTIND - 1)


if [ ! -z "$dc"  ]; then
    for Adaptor in ${ZFCPADAPTOR[@]}; do
        zhost=`lszfcp | grep $Adaptor | cut -d " " -f 2`
        if [ -z $zhost ]; then
            assert_fail 1 0 "ZFCP adapter not configured"
	fi
        pc=`cat /sys/bus/ccw/devices/$Adaptor/$zhost/scsi_host/$zhost/prot_capabilities`
        pg=`cat /sys/bus/ccw/devices/$Adaptor/$zhost/scsi_host/$zhost/prot_guard_type`
        dif=`cat /sys/module/zfcp/parameters/dif`
        dix=`cat /sys/module/zfcp/parameters/dix`
        if [ $dc == "dif" ]; then
            cat /proc/cmdline | grep 'zfcp.dif=1'
                rc=$?
                if [ $rc -eq 0 -a $pc -eq 1 -a $pg -eq 0 -a $dif == 'Y' ]; then
                    assert_fail 0 0 "DIF is Enabled on System"
                else
                    assert_fail 1 0 "DIF is not enabled on System"
                fi
        elif [ $dc == "dix" ]; then
                cat /proc/cmdline | grep 'zfcp.dix=1'
                rc=$?
                if [ $rc -eq 0 -a $pc -eq 17 -a $dix == 'Y' ] && [ $pg -eq 1 -o $pg -eq 2 ]; then
                    assert_fail 0 0 "DIX is Enabled on System"
                else
                    assert_fail 1 0 "DIX is not enabled on System"
                fi
        else
                echo "Not a valid parameter passed"
                assert_warn 0 0 "Invalid paramert passed to ValidateKernelParm.sh"
        fi
    done
    show_test_results
else
    usage
fi



