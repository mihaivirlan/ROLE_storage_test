#!/bin/bash
###############################################################################
# script: pol_port_delete.sh
# function: put the given port to offline
# Parameter: host -> Polatisswitch
#            user -> Polatisuser
#            passwd -> userpassword Polatisuser
#            ports -> 1 or 1,2 or 1,2,n,m,
#
###############################################################################
_DIR=`dirname $0`
WDIR="${_DIR}/polatis"
# echo "WDIR:   $WDIR"




USAGE () {
echo -e "\nusage: $0  -h SWITCH_IP -u USERNAME -p PASSWORD -P [Port1 [Port1,Port2,...,Port32]]\n"
exit 1
}
#------------------------------------------------------------------------------

[[ $# -eq 0 ]] && USAGE
while getopts ':h:u:p:P:' opts
do
  case $opts in
    h ) SWITCH=$OPTARG
        if [[ ${OPTARG//[A-Z]} = '-' ]] || [[ ${OPTARG//[a-z]} = '-' ]]
        then
            echo -e "\"-${opts}\"  required a value "
            USAGE
        fi
        ;;
    u ) _USER=$OPTARG
        if [[ ${OPTARG//[A-Z]} = '-' ]] || [[ ${OPTARG//[a-z]} = '-' ]]
        then
          echo -e "\"-${opts}\"  required a value "
          USAGE
        fi
        ;;
    p ) PW=$OPTARG
        if [[ ${OPTARG//[A-Z]} = '-' ]] || [[ ${OPTARG//[a-z]} = '-' ]]
        then
            echo -e "\"-${opts}\"  required a value "
            USAGE
        fi
        ;;
    P ) PORTS=$OPTARG
        if [[ ${OPTARG//[A-Z]} = '-' ]] || [[ ${OPTARG//[a-z]} = '-' ]]
        then
            echo -e "\"-${opts}\"  required a value "
            USAGE
        fi
       ;;
    :) echo -e "\"-${opts}\"  required a value "
        USAGE
        ;;
    ? ) USAGE
       ;;

  esac
done
shift $((OPTIND -1))


python2 ${WDIR}/delete_connections.py --host $SWITCH --username $_USER --password $PW --ports $PORTS 2>&1
