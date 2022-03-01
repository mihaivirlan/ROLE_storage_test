#!/bin/bash

########################
# This script handles an automated switch port toggling (Brocade)
# or an automated cable pull (Polatis) and determines, which
# mechanism has to be used.
#
# Brocade:
# The script executes cablepulling via brocade switch port toggling
# All required files reside in ./cablepull
#
# Polatis:
# The script executes cablepulling via polatis switch port diconnecting
# All required files reside in ./cablepull
#
# Thorsten Diehl, 17.08.2015
# update 14.03.2017
# update TDI 19.09.2018 Brocade.sh moved from lnxtp4a to bistro due to ssh key restrictions
# update TDI 28.03.2019 for new SAN switches
# update TDI 12.09.2019 for new SAN switches
# update Thomas Lambart 12. Feb 2020 for polatis switch
# update TDI 30.03.2020 supported ficon switches added
# big redesign TDI 04.06.2020 to run script locally for more bullet-proof execution
# update TDI 08.02.2021 directory for logfiles now in $(pwd)/log instead of hardcoded /root/log


# Load testlib
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)}"

source ${TESTLIBDIR}/lib/common/results.sh || exit 1
source ${TESTLIBDIR}/lib/common/remote.sh || exit 1
source ${TESTLIBDIR}/lib/common/environment.sh || exit 1
source ${TESTLIBDIR}/lib/toybox/common/libconcurrent.sh || exit 1
source ${TESTLIBDIR}/functions.sh || exit 1 
[[ -r ${TESTLIBDIR}/DASD.conf ]] && source ${TESTLIBDIR}/DASD.conf
CONCURRENT_SSH_OPTIONS="${CONCURRENT_SSH_OPTIONS} -i /root/.ssh/id_rsa.autotest -q"

# some functions for polatis section

#IS_BLOCK() {
#    PORT=$1
#    [[ ${PORT} == [1,2] ]] || [[ ${PORT} == 1[7,8] ]] && BLOCK=B1
#    [[ ${PORT} == [3,4] ]] || [[ ${PORT} == 19 ]] || [[ ${PORT} == 20 ]]  && BLOCK=B2
#    [[ ${PORT} == [5,6] ]] || [[ ${PORT} == 2[1,2] ]] && BLOCK=B3
#    [[ ${PORT} == [7,8] ]] || [[ ${PORT} == 2[3,4] ]] && BLOCK=B4
#    [[ ${PORT} == 9 ]] || [[ ${PORT} == 10 ]] || [[ ${PORT} == 2[5,6] ]]&& BLOCK=B5
#    [[ ${PORT} == 1[1,2] ]] || [[ ${PORT} == 2[7,8] ]] && BLOCK=B6
#    [[ ${PORT} == 1[3,4] ]] || [[ ${PORT} == 29 ]] || [[ ${PORT} == 30 ]] && BLOCK=B7
#    [[ ${PORT} == 1[5,6] ]] || [[ ${PORT} == 3[1,2] ]] && BLOCK=B8
#    echo $BLOCK
#}

keepFiles () {
    filename=$1
    files_wanted=$2
    files_counted=$(ls -1 ${filename}|wc -l)
    if [[ ${files_counted} -gt ${files_wanted} ]]
        then
        (( delta = $files_counted - $files_wanted ))
        file_to_remove=$(ls -t1 ${filename:-LEER} | tail -${delta})
        for f in ${file_to_remove}; do
            echo "rm ${f:-LEER}"
            rm ${f:-LEER}
        done
    fi
}

# end of function section


usage()
{
  echo "usage: $0 -sw hostname of Brocade switch or IP address of Polatis switch"
  echo " -ui   userid on the switch"
  echo " -pw   password for that userid"
  echo " -p    list of Brocade/Polatis ports to be switched (in double quotes; delimiting commas will be removed)"
  echo " -n    number of port off/on cycles"
  echo " -toff time for port off in sec or random (between 10 and 120 sec)"
  echo " -ton  time for port on in sec or random (between 30 and 120 sec)"
}

while [[ $# > 1 ]]
do
opt=$1
    case $opt in
        -sw)   SWITCH="$2";;
        -ui)   USERID="$2";;
        -pw)   PASSWD="$2";;
        -p)    PORTS="$2";;
        -n)    CYCLES="$2";;
        -toff) TIME_OFF="$2";;
        -ton)  TIME_ON="$2";;
        -h)    usage
               exit
               ;;
    esac
shift
done


start_section 0 "Starting Switch Port Toggle / cable pull scenario"
    echo ""
    echo "Script settings:"
    echo " -sw   hostname/IP of the switch    = $SWITCH"
    echo " -ui   userid on the switch         = $USERID"
    echo " -pw   password for that userid     = $PASSWD"
    echo " -p    ports to be switched         = $PORTS"
    echo " -n    number of port off/on cycles = $CYCLES"
    echo " -toff time for port off in sec     = $TIME_OFF"
    echo " -ton  time for port on in sec      = $TIME_ON"
    echo ""


    if [[ -z $SWITCH ]] || [[ -z $USERID ]] || [[ -z $PASSWD ]] || [[ -z $PORTS ]] || [[ -z $CYCLES ]] || [[ -z $TIME_OFF ]] || [[ -z $TIME_ON ]]; then
        usage
        exit 1
    fi
    sleep 2

    switch=`echo ${SWITCH}|awk '{print tolower($0)}'`
    case $switch in
        fcsw32_ficon|fcsw42_fcp|fcsw39_ficon|fcsw49_fcp) switch_type="brocade";;
        10.30.222.13[6,7,8,9])                             switch_type="polatis";;
        *)                           echo "Unsupported switch!"
                                     echo "Supperted switches are:"
                                     echo "fcsw32_ficon, fcsw42_fcp, fcsw39_ficon, fcsw49_fcp,"
                                     echo "polatis (10.30.222.137, 10.30.222.136, 10.30.222.138, 10.30.222.139)"
                                     exit 1;;
    esac
    #call checkCHPIDS function to check if one of chpids is crashed or not before start of execution checkDASDpath
	if [[ -n $DASDs ]]; then
	    for DASD in $DASDs
			do
			    echo "checkDASDpath $DASD"
			    checkDASDpath $DASD
			    if [[ $? -eq 1 ]]; then
				    assert_fail 1 0 "Not all CHPIDs for \"$DASD\" are online! Please, firstly make sure that all CHPIDs are online!"
			    fi
			done
	else
		assert_fail 1 0 "variable \"DASDs\" is not defined"
	fi

    # computing maximum expected runtime, which is required as value
    # for concurrent:createLock expiration time (in seconds), just in
    # case something breaks and the script does not release the lock
    etime=$(( $(echo $PORTS |awk -F "," '{print NF}')*$(( $(($TIME_OFF>0?$TIME_OFF:120)) + $(($TIME_ON>0?$TIME_ON:120)) +20 ))*$CYCLES ))

    # section for brocade switch
    if [ "$switch_type" = "brocade" ]; then
        lockdir=brocade.${SWITCH}.lock
        logfile=BROCADE-`date +%Y-%m-%d_%H.%M.%S`-`hostname`.log
        touch $logfile
        exec > >(tee $logfile) 2>&1
        if ( concurrent::createLock -r autotest@bistro -e $etime /tmp/$lockdir ); then
            echo "Lock created; running Brocade switch port toggling only once at a time"
            echo ""
            switch=$(echo ${SWITCH}|awk '{print tolower($0)}')
            allowed_ports=$(cat ./cablepull/allowed_ports_$switch.lst | awk {'print $1'})
            PORTS=$(echo $PORTS|tr ',' ' ')  # removing the delimiting commas
            for PORT in $PORTS; do
                port_check=0
                for i in $allowed_ports; do
                    if [ "$PORT" == "$i" ]; then
                        echo "Port $PORT is allowed to be used for cable pull"
                        echo "Enabling port, just to be sure..."
                        ./cablepull/port_on.exp $switch $USERID $PASSWD $PORT
                        if [ $? -gt 0 ]; then
                            echo "Warning! Port $PORT on $switch could not be switched on!"
                            concurrent::releaseLock -r autotest@bistro /tmp/$lockdir
                            exit 1
                        fi
                        echo ""
                        port_check=1
                    fi
                done
                if [ $port_check -eq 0 ]; then
                    echo "++++++++++++++++++++++++++++++++++++++++++++++++"
                    echo "PORT $PORT CANNOT BE USED FOR THIS KIND OF TEST!"
                    echo "PLEASE SELECT ANOTHER PORT!                     "
                    echo "++++++++++++++++++++++++++++++++++++++++++++++++"
                    echo ""
                    concurrent::releaseLock -r autotest@bistro /tmp/$lockdir
                    exit 1
                fi
            done

            Z=0
            while [ $Z -lt $CYCLES ]; do
                Z=$[Z+1]
                echo "++++ Cycle $Z @ $(date) ++++"
                for PORT in ${PORTS[*]}; do
                    echo ""
                    # if test is being run with SCSI LUNs, check status before cable pulls
                    if [ -e ${TESTLIBDIR}/00_config-file ]; then
                        source ${TESTLIBDIR}/00_config-file
                        checkZfcpStatus
                    fi
                    # switching selected port off
                    if [ "$TIME_OFF" == "random" ]; then
                        toff=$(($RANDOM %110 + 10 ))
                    else
                        toff=$TIME_OFF
                    fi
                    ./cablepull/port_off.exp $switch $USERID $PASSWD $PORT
                    rc=$?
                    if [ $rc -gt 0 ]; then
                        echo "Warning! Port $PORT on $switch could not be switched off!"
                        concurrent::releaseLock -r autotest@bistro /tmp/$lockdir
                        assert_fail $rc 0 "Exiting here..."
                    fi
                    echo "sleeping for $toff sec..."
                    sleep $toff

                    # switching selected port on
                    if [ "$TIME_ON" == "random" ]; then
                        ton=$(($RANDOM %90 + 30 ))
                    else
                        ton=$TIME_ON
                    fi
                    ./cablepull/port_on.exp $switch $USERID $PASSWD $PORT
                    rc=$?
                    if [ $rc -gt 0 ]; then
                        echo "Warning! Port $PORT on $switch could not be switched on!"
                        concurrent::releaseLock -r autotest@bistro /tmp/$lockdir
                        assert_fail $rc 0 "Exiting here..."
                    fi
                    echo "sleeping for $ton sec..."
                    sleep $ton
                    # call checkDASDpath function to check if one of chpids crashed or not during execution - check it after each cycle!
                    if [[ -n $DASDs ]]; then
                        for DASD in $DASDs
                            do
                                echo "checkDASDpath $DASD"
                                checkDASDpath $DASD
                                if [[ $? -eq 1 ]]; then
                                    assert_fail 1 0 "Not all CHPIDs for \"$DASD\" are online! Please, firstly make sure that all CHPIDs are online!"
                                fi
                            done
                    else
                        assert_fail 1 0 "variable \"DASDs\" is not defined"
                    fi
                done
                echo ""
            done
            echo "Ports $PORTS on switch $switch had been switched off/on for $Z times!"
            concurrent::releaseLock -r autotest@bistro /tmp/$lockdir
        else  # Brocade switch port toggling is already running
            assert_warn 0 0 "Lock found, waiting for cable pull action on another system to complete..."
            concurrent::waitForUnlock -r autotest@bistro /tmp/$lockdir --retry-count 11111111 # more than 12 days
        fi
        echo -e "\n++++ end Cycle $Z @ $(date) ++++\n"
        assert_warn $? 0 "End of brocade cablepull test!"
    fi

    # section for polatis switch
    if [ "$switch_type" = "polatis" ]; then
        # computing maximum expected runtime, which is required as value
        # for concurrent:createLock expiration time (in seconds), just in
        # case something breaks and the script does not release the lock
        # for short times we need more time for of set 
        if  [[ $TIME_OFF -eq random || $TIME_ON -eq random ]]; then
            etime=$(( $(echo $PORTS |awk -F "," '{print NF}')*$(( $(($TIME_OFF>0?$TIME_OFF:120)) + $(($TIME_ON>0?$TIME_ON:120)) +20 ))*$CYCLES ))
        else
            etime=$(( $(echo $PORTS |awk -F "," '{print NF}')*$(( $(($TIME_OFF>0?$TIME_OFF:120)) + $(($TIME_ON>0?$TIME_ON:120)) +50 ))*$CYCLES ))
        fi

        WDIR="./cablepull"
        PORTSTAT=${WDIR}/connections/portStates_$$.out
        NOT_ALLOW=${WDIR}/connections/not_allow.out
        lockdir=polatis.${SWITCH}-${PORTS}.lock
        logfile=POLATIS-`date +%Y-%m-%d_%H.%M.%S`-`hostname`.log

        touch $logfile
        exec > >(tee $logfile) 2>&1

        if ( concurrent::createLock -r autotest@bistro -e $etime /tmp/$lockdir ); then
            echo running Polatis cable pull on $SWITCH ports $PORTS only once at a time
            # check and establish connection to polatis switch 10.30.x.x
            if (! ping -c3 -i 0.2 $SWITCH > /dev/null) ; then  # switch does not ping, tunnel it
                # check whether port 3082 on localhost is aleady open
                if (! echo " " > /dev/tcp/localhost/3082) 2> /dev/null; then
                    # open a forked ssh session for tunneling port 3082 as master with control socket
                    ssh -M -fN -S /tmp/.ssh-${SWITCH}-tunnel -L 3082:${SWITCH}:3082 ${CONCURRENT_SSH_OPTIONS} autotest@bistro
                    if [ "$?" -gt "0" ]; then
                        assert_fail $? 0 "ssh tunnel could not be opened, terminating here"
                    fi
                fi
                IP=127.0.0.1
            else
                IP=$SWITCH  # use the original address
            fi

            # save the switch config
            mkdir -p ${WDIR}/connections
            DATE=$(date +%Y%m%d_%H%M%S)
            ${WDIR}/polatis_tl1.sh -h ${IP} -u ${USERID} -pw ${PASSWD} -c "rtrv-patch:::123:;" > ${WDIR}/connections/all_connections_${SWITCH}_${DATE}
            ${WDIR}/polatis_tl1.sh -h ${IP} -u ${USERID} -pw ${PASSWD} -c "rtrv-patch::${PORTS//,/&}:123:;" > ${WDIR}/connections/portStates_${PORTS//,/_}_${SWITCH}_${DATE}.out
            ${WDIR}/polatis_tl1.sh -h ${IP} -u ${USERID} -pw ${PASSWD} -c "rtrv-patch::${PORTS//,/&}:123:;" |grep "\"" > ${PORTSTAT}

            # now do the cable pulls
            PORTS=$(echo $PORTS|tr ',' ' ')  # removing the delimiting commas
            Z=0
            while [ $Z -lt $CYCLES ]; do
                Z=$[Z+1]
                echo "++++ Cycle $Z @ $(date) ++++"
                for PORT in ${PORTS[*]}; do
                    echo ""
                    # if test is being run with SCSI LUNs, check status before cable pulls
                    if [ -e ${TESTLIBDIR}/00_config-file ]; then
                        source ${TESTLIBDIR}/00_config-file
                        checkZfcpStatus
                    fi
                    # switching selected port off
                    if [ "$TIME_OFF" == "random" ]; then
                        toff=$(($RANDOM %110 + 10 ))
                    else
                        toff=$TIME_OFF
                    fi
                    echo "++++ disconnect port ${PORT} ++++ "
                    echo "${WDIR}/polatis_tl1.sh -h ${IP} -u ${USERID} -pw ${PASSWD} -c \"DLT-PATCH::${PORT}:123:;\""
                   ${WDIR}/polatis_tl1.sh -h ${IP} -u ${USERID} -pw ${PASSWD} -c "DLT-PATCH::${PORT}:123:;"
                    rc=$?
                    if [ $rc -gt 0 ]; then
                        echo "Warning! Port $PORT on $IP could not be switched off!"
                        concurrent::releaseLock -r autotest@bistro /tmp/$lockdir
                        assert_fail $rc 0 "Exiting here..."
                    fi
                    echo -e "sleeping for $toff sec...\n"
                    sleep $toff

                    # switching selected port on
                    if [ "$TIME_ON" == "random" ]; then
                        ton=$(($RANDOM %90 + 30 ))
                    else
                        ton=$TIME_ON
                    fi

                    # get the port pair
                    IPORT=`grep  -w ${PORT} ${PORTSTAT} |tr  -d '"' |tr -d ' ' |cut -f1 -d, `
                    OPORT=`grep  -w ${PORT} ${PORTSTAT} |tr  -d '"' |tr -d ' ' |cut -f2 -d, `
                    echo -e "\n++++  re-establish cross connection for ports: ${IPORT},${OPORT} ++++\n"
                    echo " ${WDIR}/polatis_tl1.sh -h ${IP} -u ${USERID} -pw ${PASSWD} -c \"ENT-PATCH::${IPORT},${OPORT}:123:;\""
                    ${WDIR}/polatis_tl1.sh -h ${IP} -u ${USERID} -pw ${PASSWD} -c "ENT-PATCH::${IPORT},${OPORT}:123:;"
                    rc=$?
                    if [ $rc -gt 0 ]; then
                        echo "Warning! Ports $IPORT and $OPORT on $IP could not be reconnected!"
                        concurrent::releaseLock -r autotest@bistro /tmp/$lockdir
                        rm ${PORTSTAT}
                        assert_fail $rc 0 "Exiting here..."
                    fi
                    echo "done: cross connection to: "
                    ${WDIR}/polatis_tl1.sh -h ${IP} -u ${USERID} -pw ${PASSWD} -c "RTRV-PATCH::${IPORT}:123:;" |grep '\"'
                    echo "sleeping for $ton sec..."
                    sleep $ton
                    # call checkDASDpath function to check if one of chpids crashed or not during execution - check it after each cycle!
                    if [[ -n $DASDs ]]; then
                        for DASD in $DASDs
                            do
                                echo "checkDASDpath $DASD"
                                checkDASDpath $DASD
                                if [[ $? -eq 1 ]]; then
                                    assert_fail 1 0 "Not all CHPIDs for \"$DASD\" are online! Please, firstly make sure that all CHPIDs are online!"
                                fi
                            done
                    else
                        assert_fail 1 0 "variable \"DASDs\" is not defined"
                    fi
                done
                echo ""
            done
            echo "Ports $PORTS on switch $SWITCH had been switched off/on for $Z times!"
            echo -e "\n++++ end Cycle $Z @ $(date) ++++\n"
            ssh -S /tmp/.ssh-${SWITCH}-tunnel -O exit ${CONCURRENT_SSH_OPTIONS} autotest@bistro # remove ssh tunnel connection
            concurrent::releaseLock -r autotest@bistro /tmp/$lockdir
        else  # Polatis cable pull action is already running
            assert_warn 0 0 "Lock found, waiting for cable pull action to complete..."
            concurrent::waitForUnlock -r autotest@bistro /tmp/$lockdir --retry-count 11111111 # more than 12 days
        fi

        assert_warn $? 0 "End of polatis cablepull test!"

        # clean up some files
        rm ${PORTSTAT}
        keepFiles "${WDIR}/connections/all_connections_${SWITCH}_*"  10
        keepFiles "${WDIR}/connections/portStates_*_${SWITCH}_*"  10

    fi

    cp -p $logfile $(pwd)/log
    echo ""
    echo "Kernel messages from dmesg:"
    dmesg -c | egrep -C1000 -i "$REGEX_KERNEL_PROBLEMS"
end_section 0