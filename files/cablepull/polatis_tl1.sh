#!/bin/bash
# set -x
#-----------------------------------------------------------------------------
# # Script-Name: polatis_tl1.sh
# Owner: Thomas Lambart
# Date: 14. Feb. 2021
# Description: runs the TL1 - command at the POLATIS switch
# Parameter:
#            --host
#            --port
#            --user
#            --password
#            --cmd
#
#_----------------------------------------------------
# ----------------------------------------------------
#++          available TL1 - commands (CMD)
#++         ===============================
#++
#++   Ports:
#++   RTRV-PORT-SHUTTER::[Ports]:123:;
#++        retrieves the ports status
#++
#++   RLS-PORT-SHUTTER::[Ports]:123:;
#++        enables the ports
#++
#++   OPR-PORT-SHUTTER::[Ports]:123:;
#++        disables the ports
#++
#++
#++   Label:
#++   RTRV-PORT-LABEL::[Ports]:123:;
#++         retrieves the port labels
#++
#++  ED-PORT-LABEL::[Ports]:123:::LABEL=<labels>;
#++         sets labels for the ports
#++         e.g.: ED-PORT-LABEL::2:123:::LABEL="FCSW49/2/3 in";
#++
#++
#++   cross connections:
#++   RTRV-PATCH:::123:;
#++         retrieves the current state of the all connections
#++                   cross connections:                         RTRV-PATCH:::123:;
#++
#++   RTRV-PATCH::[Ports]:123:;
#++         retrieves the current state of the ports connections
#++                    cross connections:                       RTRV-PATCH::[Ports]:123:;
#++                    e.g.: RTRV-PATCH::11&4&10:123:;
#++
#++   ENT-PATCH::[Ports]:123:;
#++         configure cross-connections between input and output ports
#++                     e.g.: ENT-PATCH::11,28:123:;
#++
#++   DLT-PATCH::[Ports]:123:;
#++         disconnects connections between input and output ports
#++                    e.g.: DLT-PATCH::11:123:;
#++
#++
#++   Shutter:
#++   RTRV-PORT-FLAP::[Ports]:123:;
#++         retrieves the shutter settings for the ports :    RTRV-PORT-FLAP::[Ports]:123:;
#++                    [Ports]=''  for all  RTRV-PORT-FLAP:::123:;
#++                    e.g.: RTRV-PORT-FLAP::10:123:; or RTRV-PORT-FLAP::10&&17:123:;
#++
#++   ENT-PORT-FLAP::[Ports]:123::[offintv, onintvl, cycles];
#++          set a shutter for a special Port          ENT-PORT-FLAP::[Ports]:123::[offintv, onintvl, cycles];
#++                    offintv, onintvl, cycles [10, 500, 1]
#++                    e.g.: ENT-PORT-FLAP::10:123::1000, 500, 1;
#++
#++   OPR-PORT-FLAP::[Ports]:123;
#++                    activate a shutter : OPR-PORT-FLAP::[Ports]:123;
#++
#++   RLS-PORT-FLAP::[Ports]:123;
#++                    deactivate a shutter : RLS-PORT-FLAP::[Ports]:123;
#++
#++   NOTE: shutter should be set on a 'in-Port'
#++
#++
#++   Attenuation:
#++   RTRV-EQPT::ATTEN:123:::PARAMETER=CONFIG;
#++                    query the attenuation modes supported by the switch
#++                          possible modes are: NONE|ABSOLUTE|RELATIVE|CONVERGED
#++
#++   SET-PORT-ATTEN:[<tid>]:<port_aid>:<ctag>::: MODE=<mode>[,LEVEL=<level>][,REFS=<refs>];
#++                    sets the attenuation for the ports specified in port_aid
#++                    NOTE: port_aid must be an output Port !!
#++                    e.g.: SET-PORT-ATTEN::33:123:::MODE=NONE;
#++                          clears the attenuation on the port 33
#++
#++   RTRV-PORT-ATTEN::[Ports]:123:;
#++         retrieves the attenuation settings on the ports specified Prots
#++   ------------------------------------------------------------------------


#-----------------------------------------------------------------------------
PORT=3082
#-----------------------------------------------------------------------------
usage () {
  echo "usage: $0 -h Polatis-hostname   "
  echo "           e.g. -h 10.30.222.137 "
  echo " [-p  Ethernet port] "
  echo "           e.g. [-p 3082] this is optional, default: 3082 "
  echo " -u user"
  echo "           e.g.: -u linuxtest"
  echo " -pw Password"
  echo "            e.g.: -pw {Userpassword} "
  echo ""
  echo " -c {CMD}"
  echo "          e.g. -c \"rtrv-patch::10&12&4:123:;\""
  echo ""
  echo "e.g.: $0 -h 10.30.222.137 -u linuxtest -pw {Userpassword} -c \"rtrv-patch::10:123:;\""
  echo "----------------------------------------------------------------------"
  grep '^\#++' $0
  exit 1

}
#-----------------------------------------------------------------------------


while [ $# -gt 0 ]; do
    case "$1" in
          "-h"|"--host")          HOST="$2"; shift; ;;
          "-p"|"--port")          PORT="$2"; shift; ;;
          "-u"|"--user")          USER="$2"; shift; ;;
          "-pw"|"--password")     PASSWD="$2"; shift; ;;
          "-c"|"--cmd")           CMD="$2"; shift; ;;
          "-?"|"--help")          usage; ;;
           *)
                  echo "Unknown parameter: $1"
                  usage
                  ;;
    esac
    shift;
done
#-----------------------------------------------------------------------------

echo ""
echo "Script settings:"
echo "-h   host                   = ${HOST}"
echo "-p   port (default: 3082)   = ${PORT}"
echo "-u   user                   = ${USER}"
echo "-pw  password               = ${PASSWD}"
echo "-c   cmd                    = ${CMD}"
echo ""

if [[ -z ${HOST} ]] | [[ -z ${PORT} ]] |[[ -z ${USER} ]] | [[ -z ${PASSWD} ]] | [[ -z ${CMD} ]]  ; then
  usage
fi

#------------------------------------------------------------------------------
# do the telnet

( echo "open ${HOST} ${PORT} "
sleep 2
echo "act-user::${USER}:123::${PASSWD};"
sleep 1
echo "${CMD}"
sleep 1
echo "canc-user::${USER}:123:;"
sleep 1
echo  close  
sleep 2 ) | telnet | tee  tn.out
#------------------------------------------------------------------------------
# check the retun code
grep ^M tn.out |while read M tt RCode
do 
   if  [[ $RCode !=  COMPLD ]]
   then
	   rm -f tn.out
	   exit 1
   fi
done
rm -f tn.out
