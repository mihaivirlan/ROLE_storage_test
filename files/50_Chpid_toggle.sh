#!/bin/bash

### Configure path/CHPID/ADAPTER off on (e.g. while blast is running on multipath devices)
# This script handles the following scenarios (sequentially)
# 1. LPAR & VM: CHPID vary off/on via chchp -v
# 2. LPAR & VM: Adapter offline/online via chccwdev
# 3. z/VM only: Adapter detach/re-attach via vmcp
# 4. LPAR only: CHPID configure off/on via chchp -c

# Load testlib
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/lib}"

source ${TESTLIBDIR}/common/results.sh || exit 1
source ${TESTLIBDIR}/common/remote.sh || exit 1
source ${TESTLIBDIR}/common/environment.sh || exit 1

CYCLES=$1
TIME_OFF=$2
TIME_ON=$3
n=1
RANDOM_ON=0
RANDOM_OFF=0

function random()
  {
    local MIN=$1
    local MAX=$2
    local number=0

    while [ $number -lt $MIN ]; do
      number=$RANDOM
      let "number %= $MAX"
    done

    echo $number
  }

start_section 0 "Now switching paths off and on for $CYCLES times"
init_tests

# main

while [ $n -le $CYCLES ] ; do
# determine, whether intervalls have to be randomized for each cycle
  if [ $TIME_ON == "random" ] ; then
    RANDOM_ON=1
  fi
  if [ $TIME_OFF == "random" ] ; then
    RANDOM_OFF=1
  fi
# randomize intervalls, if required
  if [ $RANDOM_ON -eq 1 ] ; then
    TIME_ON=$(random 20 120)
  fi
  if [ $RANDOM_ON -eq 1 ] ; then
    TIME_OFF=$(random 20 120)
  fi

  logger Cycle $n

  echo "CHPID/Adapter toggle loop: $n of $CYCLES"

###  # check multipath
  multipathd show topo |grep 'failed'
  rc=$?
  if [ $rc -eq 0 ]; then  # add 25 seconds grace time
      echo "Path check failed; retrying path check after 25 seconds..."
      sleep 25
      multipathd show topo |grep 'failed'
      rc=$?
  fi
  assert_fail $rc 1 "All paths are available"

# Scenario 1: LPAR & VM: CHPID vary off/on via chchp -v
start_section 1 "Scenario 1: LPAR & VM: CHPID vary off/on"
    for chpid in $(lscss | grep 1732/03 | grep yes | awk '{print $9}' | uniq | cut -b 1-2 | tr '[:upper:]' '[:lower:]') ; do
      echo  "varying CHPID $chpid off for $TIME_OFF sec"
      logger "$(date +"%Y-%m-%d %H:%M:%S.%N") ### varying CHPID $chpid off for $TIME_OFF sec ###"
      chchp -v 0 $chpid
      assert_fail $? 0 "CHPID $chpid varied off for $TIME_OFF sec via chchp -v 0"
      sleep $TIME_OFF
      echo  "varying CHPID $chpid on for $TIME_ON sec"
      logger "$(date +"%Y-%m-%d %H:%M:%S.%N") ### varying CHPID $chpid on for $TIME_ON sec ###"
      chchp -v 1 $chpid
      assert_fail $? 0 "CHPID $chpid varied on for $TIME_ON sec via chchp -v 1"
      sleep $TIME_ON
    done
    multipathd show topo |grep 'failed'
    rc=$?
    if [ $rc -eq 0 ]; then  # add 25 seconds grace time
        echo "Path check failed; retrying path check after 25 seconds..."
        sleep 25
        multipathd show topo |grep 'failed'
        rc=$?
    fi
    assert_fail $rc 1 "All paths are still available"
end_section 1

# Scenario 2: LPAR & VM: Adapter offline/online via chccwdev
start_section 1 "Scenario 2: LPAR & VM: Adapter offline/online"
    for zfcpdev in $(lscss | grep 1732/03 | grep yes | awk '{print $1}') ; do
      echo  "offline zfcp device $zfcpdev for $TIME_OFF sec"
      logger "$(date +"%Y-%m-%d %H:%M:%S.%N") ### offline zfcp device $zfcpdev for $TIME_OFF sec ###"
      chccwdev -d $zfcpdev
      assert_fail $? 0 "zfcp device $zfcpdev offline for $TIME_OFF sec"
      sleep $TIME_OFF
      echo  "online zfcp device $zfcpdev for $TIME_ON sec"
      logger "$(date +"%Y-%m-%d %H:%M:%S.%N") ### online zfcp device $zfcpdev for $TIME_ON sec ###"
      chccwdev -e $zfcpdev
      assert_fail $? 0 "zfcp device $zfcpdev online for $TIME_ON sec"
      sleep $TIME_ON
    done
    multipathd show topo |grep 'failed'
    rc=$?
    if [ $rc -eq 0 ]; then  # add 25 seconds grace time
        echo "Path check failed; retrying path check after 25 seconds..."
        sleep 25
        multipathd show topo |grep 'failed'
        rc=$?
    fi
    assert_fail $rc 1 "All paths are still available"
end_section 1

  if (isVM) ; then
# Scenario 3: z/VM only: detach/re-attach via vmcp
start_section 1 "Scenario 3: z/VM only: detach/attach"
    for zfcpdev in $(lscss | grep 1732/03 | grep yes | awk '{print $1}' | cut -b 5-8) ; do
      echo  "detaching zfcp device $zfcpdev for $TIME_OFF sec"
      logger "$(date +"%Y-%m-%d %H:%M:%S.%N") ### detaching zfcp device $zfcpdev for $TIME_OFF sec ###"
      vmcp det $zfcpdev
      assert_fail $? 0 "zfcp device $zfcpdev detached for $TIME_OFF sec"
      sleep $TIME_OFF
      echo  "re-attaching zfcp device $zfcpdev for $TIME_ON sec"
      logger "$(date +"%Y-%m-%d %H:%M:%S.%N") ### re-attaching zfcp device $zfcpdev for $TIME_ON sec ###"
      vmcp att $zfcpdev '*'
      assert_fail $? 0 "zfcp device $zfcpdev re-attached for $TIME_ON sec"
      sleep $TIME_ON
    done
    multipathd show topo |grep 'failed'
    rc=$?
    if [ $rc -eq 0 ]; then  # add 25 seconds grace time
        echo "Path check failed; retrying path check after 25 seconds..."
        sleep 25
        multipathd show topo |grep 'failed'
        rc=$?
    fi
    assert_fail $rc 1 "All paths are still available"
end_section 1
  else
# Scenario 4: LPAR only: configure off/on via chchp -c
start_section 1 "Scenario 3: LPAR only: configure off/on"
    for chpid in $(lscss | grep 1732/03 | grep yes | awk '{print $9}' | uniq | cut -b 1-2 | tr '[:upper:]' '[:lower:]') ; do
      echo  "configuring CHPID $chpid off for $TIME_OFF sec"
      logger "$(date +"%Y-%m-%d %H:%M:%S.%N") ### configuring CHPID $chpid off for $TIME_OFF sec ###"
      chchp -c 0 $chpid
      assert_fail $? 0 "CHPID $chpid configured off for $TIME_OFF sec via chchp -c 0"
      sleep $TIME_OFF
      echo  "configuring CHPID $chpid on for $TIME_ON sec"
      logger "$(date +"%Y-%m-%d %H:%M:%S.%N") ### configuring CHPID $chpid on for $TIME_ON sec ###"
      chchp -c 1 $chpid
      assert_fail $? 0 "CHPID $chpid configured on for $TIME_ON sec via chchp -c 1"
      sleep $TIME_ON
    done
    multipathd show topo |grep 'failed'
    rc=$?
    if [ $rc -eq 0 ]; then  # add 25 seconds grace time
        echo "Path check failed; retrying path check after 25 seconds..."
        sleep 25
        multipathd show topo |grep 'failed'
        rc=$?
    fi
    assert_fail $rc 1 "All paths are still available"
end_section 1
  fi
  n=$[n+1]
done

show_test_results
end_section 0
