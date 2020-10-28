#!/bin/bash
###############################################################################
# script: pol_port_create.sh
# function: create the cross connection of the given ports
# Parameter: -h host     -> Polatisswitch
#            -u user     -> Polatisuser
#            -p passwd   -> userpassword Polatisuser
#            -i inports  -> Port for in
#            -o outports -> Port for out 
#
###############################################################################
_DIR=`dirname $0`
WDIR="${_DIR}/polatis"
# echo "WDIR:   $WDIR"




USAGE () {
echo -e "\nusage: $0  -h SWITCH_IP -u USERNAME -p PASSWORD -i Port -o Port"
exit 1
}
#------------------------------------------------------------------------------

[[ $# -eq 0 ]] && USAGE
while getopts ':h:u:p:i:o:' opts
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
    i ) IPORT=$OPTARG
        if [[ ${OPTARG//[A-Z]} = '-' ]] || [[ ${OPTARG//[a-z]} = '-' ]]
        then
            echo -e "\"-${opts}\"  required a value "
            USAGE
        fi
       ;;
   o ) OPORT=$OPTARG
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


# echo "python ${WDIR}/create_move_conns.py --host $SWITCH --username $_USER --password $PW --inports ${IPORT} --outports $OPORT"
python2 ${WDIR}/create_move_conns.py --host $SWITCH --username $_USER --password $PW --inports ${IPORT} --outports $OPORT
