#!/bin/bash
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"
source ${TESTLIBDIR}lib/common/environment.sh || exit 1

usage(){

	echo "usage : ./AddKernelParm.sh -o <dif|dix>"
	exit 0
}

while getopts o: opt
    do
    case "$opt" in
        o) dc="$OPTARG";;
    esac
done
shift $(expr $OPTIND - 1)

if [ ! -z "$dc" ]; then
	if [ $dc == 'dif' ]; then
		KernParm="zfcp.dif=1"
    elif [ $dc == 'dix' ]; then
		KernParm="zfcp.dix=1"
	else
		echo "Not a valid parameter passed"
		exit 1
	fi
else
	usage
fi
if (isRhel); then
	parmDir="/boot/loader/entries/"
        parmFile=$(ls $parmDir*`uname -r`*.conf)
        sed -i.zfcpbak '/^options/ s/$/ '$KernParm'/' $parmFile
	zipl
elif (isSles); then
	sed -i.zfcpbak '/^GRUB_CMDLINE_LINUX="/ s/"$/ '$KernParm'"/' /etc/default/grub
	grub2-mkconfig -o /boot/grub2/grub.cfg
fi



