#!/bin/bash
# Script-Name: 15_LUN_Setup.sh
# Owner: Thorsten Diehl
# Date: 03.02.2021
# Description:  Setting up the SCSI LUNs
#
# Load testlib
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"
MPATH_CONF_REPLACE=TRUE

source ${TESTLIBDIR}lib/common/environment.sh || exit 1
source ${TESTLIBDIR}lib/common/results.sh || exit 1
source ${TESTLIBDIR}lib/common/remote.sh || exit 1
source ${TESTLIBDIR}lib/toybox/common/libcommon.sh || exit 1
source ${TESTLIBDIR}lib/toybox/storage/libscsi.sh || exit 1
source ${TESTLIBDIR}00_config-file || exit 1
source ${TESTLIBDIR}functions.sh || exit 1
source ${TESTLIBDIR}variables.sh || exit 1


start_section 0 "Preparing Testsystem"

    start_section 1 "Check for multipath devices that are already in use"

        echo "Determine initial number of already avilable multipath devices"
        INITIALMULTIPATHDEVICES=$(multipathd show topo | grep IBM | wc -l)
        assert_warn 0 0 "initial number of already available multipath devices is $INITIALMULTIPATHDEVICES"

        while [ $# -ne 0 ]; do
          case "$1" in
            -preserve_multipath.conf )
               MPATH_CONF_REPLACE=FALSE
               ;;
          esac
          shift
        done
        if [ "${MPATH_CONF_REPLACE}" == "TRUE" ]; then
          echo "Replace /etc/multipath.conf"
          assert_exec 0 "cp -p /usr/local/storage-test/multipath.conf /etc"
        fi


    end_section 1

    start_section 1 "Verifying if FCP ADAPTORs are available"

        for ADAPTOR in ${ZFCPADAPTOR[@]}; do
            echo ".... verifying ADAPTOR ${ADAPTOR}"
            echo
            lszfcp | grep ${ADAPTOR}
            RC=$?
            if [ ${RC} -ne 0 ]; then
                echo "Adaptor ${ADAPTOR} not found, trying to unblacklist!"
                echo free ${ADAPTOR} > /proc/cio_ignore   # cio_ignore handling
                echo 1 > /proc/cio_settle                 # cio_ignore handling

                if (isVM) ; then
                    VM_ADAPTOR=`echo ${ADAPTOR} | sed 's/^[[:digit:]]\.[[:digit:]]\.//g'`
                    echo "Attaching Adaptor ${ADAPTOR}..."
                    vmcp att ${VM_ADAPTOR} '*'
                fi
                sleep 2
            else
                echo "Adaptor ${ADAPTOR} found on system."
            fi
            echo "Setting Adaptor ${ADAPTOR} online..."
            if (isRhel7); then
              chccwdev -e ${ADAPTOR}
            else
              chzdev zfcp-host -e -a ${ADAPTOR}
            fi
            assert_fail $? 0 "PASSED if ADAPTOR ${ADAPTOR} could be set online"
        done
    udevadm settle
    sleep 1

    end_section 1

    start_section 1 "Setting SCSI LUNs online"

        if [ $STORAGETYPE == "V7K" ]; then
# This is to handle V7K LUN attachments in that way, that WWPNs are matched to zfcp devices alternately
            for n in `seq 0 $((${#ZFCPADAPTOR[@]}-1))`; do
                for m in `seq $n ${#ZFCPADAPTOR[@]} $((${#STORAGEPORTS[@]}-1))`; do
                    ADAPTOR=${ZFCPADAPTOR[$n]}
                    WWPN=${STORAGEPORTS[$m]}
                    echo $ADAPTOR $WWPN
                    for LUN in ${SCSILUNS[@]}; do
                        add_lun ${ADAPTOR} ${WWPN} ${LUN}
                    done
                done
            done
        else
            for ADAPTOR in ${ZFCPADAPTOR[@]}; do
                for WWPN in ${STORAGEPORTS[@]}; do
                    for LUN in ${SCSILUNS[@]}; do
                        add_lun ${ADAPTOR} ${WWPN} ${LUN}
                    done
                done
            done
        fi

    end_section 1

    start_section 1 "Start multipath daemon if neccessary"
        vgchange -an
        echo "flushing multipath table for devices not in use..."
        multipath -F
        which systemctl >/dev/null
        if [ $? -eq 0 ]; then
            if (isUbuntu); then
                systemctl is-active multipath-tools.service
                if [ $? -ne 0 ]; then
                    assert_exec 0 "systemctl start multipath-tools.service"
                else
                    assert_warn 0 0 "multipath-tools.service was already running"
                fi
            else
                systemctl is-active multipathd.service
                if [ $? -ne 0 ]; then
                    assert_exec 0 "systemctl start multipathd.service"
                else
                    assert_warn 0 0 "multipathd.service was already running"
                fi
            fi
        else
            service multipathd status
            RC=$?
            if [ ${RC} -ne 0 ]; then
                assert_exec 0 "service multipathd start"
           else
                assert_warn 0 0 "multipathd was already running"
           fi
        fi
    end_section 1

    start_section 1 "Create multipath devices"

        assert_exec 0 "multipath"
        for i in {1..60}
        do
            MULTIPATHDEVICES=$(multipathd show topo | grep IBM | wc -l)
            LUNS=$(( ${#SCSILUNS[@]} + $INITIALMULTIPATHDEVICES ))
            if [ ${MULTIPATHDEVICES} -eq ${LUNS} ]; then
                echo "All multipath devices were created"
                echo
                break
            fi
            echo -n "."
            sleep 1
        done
        assert_exec 0 "multipathd show topo"
        echo
    end_section 1

    start_section 1 "Create device list"
        rm -f ${DEVICE_LIST}
        createDeviceList

    end_section 1

show_test_results
end_section 0
