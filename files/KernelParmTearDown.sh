#!/bin/bash
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"
source ${TESTLIBDIR}lib/common/environment.sh || exit 1


if (isRhel); then
	parmDir="/boot/loader/entries/"
        parmFile=$(ls $parmDir*`uname -r`*.conf)
	bakFile=$(ls $parmDir*.zfcpbak)
        mv -f $bakFile $parmFile
	zipl
elif (isSles); then
	bakFile=$(ls /etc/default/*.zfcpbak)
	mv -f $bakFile /etc/default/grub
	grub2-mkconfig -o /boot/grub2/grub.cfg
fi
        


