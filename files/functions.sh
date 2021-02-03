#!/bin/bash 
#set -x 
# Script-Name: functions.sh
# Owner: Thorsten Diehl
# Date: 03.02.2021
# Description:  all required functions are contained here
#
# backticks removed, replaced by $(...) for better POSIX compliance
#

function add_lun {
    ADAPTOR=$1
    WWPN=$2
    LUN=$3
    for r in $(seq 0 10); do
        if (isSles12 || isRhel7); then
            echo ${LUN} > /sys/bus/ccw/drivers/zfcp/${ADAPTOR}/${WWPN}/unit_add
        else
            chzdev zfcp-lun ${ADAPTOR}:${WWPN}:${LUN} -e -a
        fi
        udevadm settle
        lszfcp -D | grep  ${ADAPTOR} | grep ${WWPN} | grep ${LUN}
        RC=$?
        if [ $RC -eq 0 ]; then break;
        fi
        if (isSles12 || isRhel7); then
            echo ${LUN} > /sys/bus/ccw/drivers/zfcp/${ADAPTOR}/${WWPN}/unit_remove
        else
            chzdev zfcp-lun ${ADAPTOR}:${WWPN}:${LUN} -d -a 2> /dev/null
        fi
            udevadm settle
    done
    PORTTYPE=$(lszfcp -Ha -b ${ADAPTOR}|grep port_type|cut -f 2 -d '"' )
    assert_fail $RC 0 "PASSED = LUN ${LUN} could be attached via ${PORTTYPE} adaptor ${ADAPTOR} and remote port ${WWPN} with $r retries"
}
	
function checkZfcpStatus {
    if [ $STORAGETYPE == "V7K" ]; then
        # This is to handle V7K LUN attachments in that way, that WWPNs are matched to zfp devices alternately
        for n in $(seq 0 $((${#ZFCPADAPTOR[@]}-1))); do
            ADAPTOR=${ZFCPADAPTOR[$n]}
            for m in $(seq $n ${#ZFCPADAPTOR[@]} $((${#STORAGEPORTS[@]}-1))); do
                WWPN=${STORAGEPORTS[$m]}
                lszfcp -Pa -b $ADAPTOR -p $WWPN | grep -i port_state | grep -q -i online
                assert_fail $? 0 "Target port $WWPN is working and online with login from $ADAPTOR"
                for LUN in ${SCSILUNS[@]}; do
                    echo "verifying status of $ADAPTOR:$WWPN:$LUN"
                    lszfcp -Da -b $ADAPTOR -p $WWPN -l $LUN | grep -w state | grep -q -i running
                    assert_fail $? 0 "LUN ${LUN} is running via port $WWPN on adaptor ${ADAPTOR}"
                    echo      
                done
            done
        done
    else  # DS8000 storage
        for ADAPTOR in ${ZFCPADAPTOR[@]}; do
            for WWPN in ${STORAGEPORTS[@]}; do
                lszfcp -Pa -b $ADAPTOR -p $WWPN | grep -i port_state | grep -q -i online
                assert_fail $? 0 "Target port $WWPN is working and online with login from $ADAPTOR"
                for LUN in ${SCSILUNS[@]}; do
                    echo "verifying status of $ADAPTOR:$WWPN:$LUN"
                    lszfcp -Da -b $ADAPTOR -p $WWPN -l $LUN | grep -w state | grep -q -i running
                    assert_fail $? 0 "LUN ${LUN} is running via port $WWPN on adaptor ${ADAPTOR}"
                    echo      
                 done
            done
        done
    fi
}

function createDeviceList {

    if [ ! -e ${DEVICE_LIST} ]; then
        if [ "${STORAGETYPE}" == "DS8K" ]; then
            LUNLIST=($(cat $CONFIG_FILE | grep  "^declare -a SCSILUNS" | sed 's/declare -a SCSILUNS=//g;s/(//g;s/)//'))
            for LUN in ${LUNLIST[@]}; do
                STRING=$(echo ${LUN:4:2};echo ${LUN:8:2})
                SUBSTRING=$(echo ${STRING//[[:space:]]}\))
                LINE=$(multipathd show topo | grep ${SUBSTRING} | sort -k 1 | sed 's/(//g;s/)//g;s/create: //g')
                MPATHDEV=/dev/disk/by-id/dm-name-$(echo ${LINE} | awk '{print $1" "$2" "$3" "$4" "$5}')
                echo ${MPATHDEV} >> ${DEVICE_LIST}
                echo ${MPATHDEV} added...
            done
        else
            multipathd show topo | grep "IBM" | grep -v "IBM,2107" | sort -k 1 | sed 's/(//g;s/)//g;s/create: //g' 1>multipath.txt 2>&1
            cat multipath.txt |
            while read LINE; do
                MPATHDEV=/dev/disk/by-id/dm-name-$(echo ${LINE} | awk '{print $1" "$2" "$3" "$4" "$5}')
                echo ${MPATHDEV} >> ${DEVICE_LIST}
                echo ${MPATHDEV} added...
             done
        fi
    else
        assert_warn 0 0 "Device list already exists..."
    fi

    assert_exec 0 "cat ${DEVICE_LIST}"
    echo
}

function createFIOLists {
    
    rm -f *.fio 
    if [ "${LVM}" == "TRUE" ]; then 
        MOUNT_POINTS=($(lvs -o lv_all --noheadings --separator : | awk -F: '{print $2}'))
        for ((i=0; i<${#MOUNT_POINTS[@]}; i++)); do
            if grep ${MOUNT_POINTS[$i]} /proc/mounts > /dev/null 2>&1; then
                fstype=$(stat -f -c %T ${MOUNT_DIR}/${MOUNT_POINTS[$i]})
                if [ ! -z "$1" ]; then # passed as parameter
                    workers=$1  
                else # get it from template
                    workers=$(cat fio.template | grep "numjobs" | sed -e s/numjobs=//g)
                fi
                fsfree=$(df -k ${MOUNT_DIR}/${MOUNT_POINTS[$i]} | grep ${MOUNT_DIR}/${MOUNT_POINTS[$i]} | awk '{print $4}')
                if [ "$fstype" == "btrfs" ]; then   
                  size=$((${fsfree}/${workers}*30/100))
                else
                  size=$((${fsfree}/${workers}*90/100))
                fi
                echo "[${MOUNT_POINTS[$i]}]"                       > ${MOUNT_POINTS[$i]}.fio 
                cat fio.template                                  >> ${MOUNT_POINTS[$i]}.fio
                echo "size=${size}k"                              >> ${MOUNT_POINTS[$i]}.fio
                echo "directory=${MOUNT_DIR}/${MOUNT_POINTS[$i]}" >> ${MOUNT_POINTS[$i]}.fio
                assert_warn 0 0 "${MOUNT_POINTS[$i]}.fio created, now merging the lists"
                cat ${MOUNT_POINTS[$i]}.fio >> jobfile.fio
                echo " "                    >> jobfile.fio
            else
                assert_warn 1 0 "${MOUNT_DIR}/${MOUNT_POINTS[$i]} not mounted"
            fi
            echo
        done
    else 
        cat ${DEVICE_LIST} |
        while read LINE; do
            if [[ $(echo ${LINE}) != "" ]]; then
                DEVICE=$(echo ${LINE} | awk '{print $1}')
                MOUNT_POINTS=($(ls ${DEVICE}* | grep "part\|p[1-9]\|[1-9]$" |  awk -F "/" '{print $5}'))
                if [ $(echo ${#MOUNT_POINTS[@]}) -ne 0 ]; then
                    for ((i=0; i<${#MOUNT_POINTS[@]}; i++)); do                
                        if grep ${MOUNT_POINTS[$i]} /proc/mounts > /dev/null 2>&1; then 
                            fstype=$(stat -f -c %T ${MOUNT_DIR}/${MOUNT_POINTS[$i]})
                            if [ ! -z "$1" ]; then # passed as parameter
                                workers=$1  
                            else # get it from template
                                workers=$(cat fio.template | grep "numjobs" | sed -e s/numjobs=//g)
                            fi
                            fsfree=$(df -k ${MOUNT_DIR}/${MOUNT_POINTS[$i]} | grep ${MOUNT_DIR}/${MOUNT_POINTS[$i]} | awk '{print $4}')
                            if [ "$fstype" == "btrfs" ]; then   
                                size=$((${fsfree}/${workers}*30/100))
                            else
                                size=$((${fsfree}/${workers}*90/100))
                            fi
                            echo "[${MOUNT_POINTS[$i]}]"                       > ${MOUNT_POINTS[$i]}.fio 
                            cat fio.template                                  >> ${MOUNT_POINTS[$i]}.fio
                            echo "size=${size}k"                              >> ${MOUNT_POINTS[$i]}.fio
                            echo "directory=${MOUNT_DIR}/${MOUNT_POINTS[$i]}" >> ${MOUNT_POINTS[$i]}.fio
                            assert_warn 0 0 "${MOUNT_POINTS[$i]}.fio created, now merging the lists"
                            cat ${MOUNT_POINTS[$i]}.fio >> jobfile.fio
                            echo " "                    >> jobfile.fio
                        else
                            assert_warn 1 0 "${MOUNT_DIR}/${MOUNT_POINTS[$i]} not mounted"
                        fi
                        echo
                    done
                else
                    assert_fail 1 0 "No partitions found!"
                fi
            fi 
        done
    fi
    if [ ! -z "$1" ]; then
      sed -i "s/numjobs=.*/numjobs=$NUMJOBS/g" jobfile.fio
      echo "jobfile.fio adjusted to numjobs=$NUMJOBS"
    fi

}

function createFilesystemOnPartition {

    DEVICES=( $(awk '{print $1}' ${DEVICE_LIST}) )
    DISTRO=$(common::getDistributionName)
 	
    case $DISTRO in
        sles-12 | sles-15 | ubuntu-16 )
            PARTITIONS=(); for dev in "${DEVICES[@]}"; do PARTITIONS+=( $(ls ${dev}* | grep "part") ); done ;;
        * )
            PARTITIONS=(); for dev in "${DEVICES[@]}"; do PARTITIONS+=( $(ls ${dev}* | grep "[1-9]$") ); done ;;
    esac
    

    FSCOUNT=0
    for ((i=0; i<${#PARTITIONS[@]}; i++)); do
        echo "creating filesystems on ${PARTITIONS[$i]}"
        ${FSTYPE[$FSCOUNT]} ${PARTITIONS[$i]}
        assert_fail $? 0 "${FSTYPE[$FSCOUNT]} ${PARTITIONS[$i]}"
        if [ ${FSCOUNT} -lt $(expr ${#FSTYPE[@]} - 1) ]; then
            FSCOUNT=$(expr ${FSCOUNT} + 1)
        else
            FSCOUNT=0
        fi
        echo
    done
}



function createFilesystemOnLV {

    VOLUMELIST=($(lvs -o lv_path --noheadings))
    FSCOUNT=0
    for ((i=0; i<${#VOLUMELIST[@]}; i++)); do
        echo "creating filesystems on ${VOLUMELIST[$i]}"
        echo "${FSTYPE[$FSCOUNT]} ${VOLUMELIST[$i]}"
        ${FSTYPE[$FSCOUNT]} ${VOLUMELIST[$i]}
        assert_fail $? 0 "${FSTYPE[$FSCOUNT]} ${VOLUMELIST[$i]}"
        sleep 2
        if [ ${FSCOUNT} -lt $(expr ${#FSTYPE[@]} - 1) ]; then
            FSCOUNT=$(expr ${FSCOUNT} + 1)
        else
            FSCOUNT=0
        fi
        echo
     done
}

function createLogicalVolume1 {

    vgdisplay | grep ${VGNAME1}
    if [ $? -eq 0 ]; then
        lvchange -an -f ${VGNAME1}/${LVNAME1}
        lvremove -f ${VGNAME1}/${LVNAME1}
        echo "lvcreate -Z y -i ${STRIPES1} -I ${STRIPESIZE1} -L ${LVSIZE1} -n ${LVNAME1} ${VGNAME1}"
        yes y | lvcreate -Z y -i ${STRIPES1} -I ${STRIPESIZE1} -L ${LVSIZE1} -n ${LVNAME1} ${VGNAME1}
        assert_fail $? 0 "PASSED if logical volume could be created"
        lvs | grep "Attr\|${LVNAME1}"
    else
        assert_warn 0 0 "No volume group ${VGNAME1} found. Exiting"
        exit 1
    fi
}

function createLogicalVolume2 {

    vgdisplay | grep ${VGNAME2}
    if [ $? -eq 0 ]; then
        lvchange -an -f ${VGNAME2}/${LVNAME2}
        lvremove -f ${VGNAME2}/${LVNAME2}
        if isSles; then
            echo "lvcreate -Z y -m ${MIRRORS} -L ${LVSIZE2} -n ${LVNAME2} ${VGNAME2}"
            yes y | lvcreate -Z y -m ${MIRRORS} --nosync -L ${LVSIZE2} -n ${LVNAME2} ${VGNAME2}
        else
        echo "lvcreate -Z y --monitor n -m ${MIRRORS} -L ${LVSIZE2} -n ${LVNAME2} ${VGNAME2}"
            yes y | lvcreate -Z y --monitor n -m ${MIRRORS} --nosync -L ${LVSIZE2} -n ${LVNAME2} ${VGNAME2}
        fi
        assert_fail $? 0 "PASSED if logical volume could be created"        
        lvs | grep "Attr\|${LVNAME2}"
    else
        assert_warn 0 0 "No volume group ${VGNAME2} found. Exiting"
        exit 1
    fi
}


function createLogicalVolume3 {

    vgdisplay | grep ${VGNAME3}
    if [ $? -eq 0 ]; then
        lvchange -an -f ${VGNAME3}/${LVNAME3}
        lvremove -f ${VGNAME3}/${LVNAME3}
        echo "lvcreate -Z y -m ${MIRRORS} --type mirror --nosync --mirrorlog core -L ${LVSIZE3} -n ${LVNAME3} ${VGNAME3}"
        yes y | lvcreate -Z y -m ${MIRRORS} --type mirror --nosync --mirrorlog core -L ${LVSIZE3} -n ${LVNAME3} ${VGNAME3}
        assert_fail $? 0 "PASSED if logical volume could be created"
        lvs | grep "Attr\|${LVNAME3}"
    else
        assert_warn 0 0 "No volume group ${VGNAME3} found. Exiting"
        exit 1
    fi
}

function createLogicalVolume4 {

    vgdisplay | grep ${VGNAME4}
    if [ $? -eq 0 ]; then
        lvchange -an -f ${VGNAME4}/${LVNAME4}
        lvremove -f ${VGNAME4}/${LVNAME4}
        echo "lvcreate -Z y -L ${LVSIZE4} --name ${LVNAME4} ${VGNAME4}"
        yes y | lvcreate -Z y -L ${LVSIZE4} --name ${LVNAME4} ${VGNAME4}
        assert_fail $? 0 "PASSED if logical volume could be created"
        lvs | grep "Attr\|${LVNAME4}"
    else
        assert_warn 0 0 "No volume group ${VGNAME4} found. Exiting"
        exit 1
    fi
}

function createLogicalVolume5 {

    vgdisplay | grep ${VGNAME5}
    if [ $? -eq 0 ]; then
        lvchange -an -f ${VGNAME5}/${LVNAME5}
        lvremove -f ${VGNAME5}/${LVNAME5}
        echo "lvcreate -Z y -L ${LVSIZE5} ${VGNAME5} --name ${LVNAME5}"
        yes y | lvcreate -Z y -L ${LVSIZE5} ${VGNAME5} --name ${LVNAME5}
        assert_fail $? 0 "PASSED if logical volume could be created"
        lvs | grep "Attr\|${LVNAME5}"
    else
        assert_warn 0 0 "No volume group ${VGNAME5} found. Exiting"
        exit 1
    fi
}

function createPartition {
      
    cat ${DEVICE_LIST} |
    while read LINE; do
        if [[ $(echo ${LINE}) != "" ]]; then
            DEVICE=$(echo ${LINE} | awk '{print $1}')
            STORAGENAME=$(echo ${LINE} | awk '{print $4}')
            echo
            echo "partitioning ${DEVICE} on storage unit ${STORAGENAME}"
            SIZE=$(parted ${DEVICE} -s unit MiB print | grep "Disk /" | awk '{print $3}')
            echo "INFO: Device ${DEVICE} size is: ${SIZE}"
            assert_exec 0 "parted -s ${DEVICE} mklabel gpt"
            PARTSIZE=$(echo "100/${AMOUNTOFPARTITIONS}" | bc)
            END=0
            for ((i=1; i<=${AMOUNTOFPARTITIONS}; i++)); do
                START=${END}
                END=$(( ${END} + ${PARTSIZE} ))
                echo "parted -s ${DEVICE} mkpart part${i} ${START}% ${END}%"
                parted -s ${DEVICE} mkpart part${i} ${START}% ${END}%
            done
            assert_fail $? 0 "PASSED if partitions could be created on ${DEVICE}"
            udevadm settle
            if (isUbuntu); then
                kpartx -as ${DEVICE}
            fi
        fi
    done
    if ! (isUbuntu); then
        partprobe
    fi
    cat ${DEVICE_LIST}
}

function createPhysicalVolumes {

    DEVICES=( $(awk '{print $1}' ${DEVICE_LIST}) )
    DISTRO=$(common::getDistributionName)

    case $DISTRO in
        sles-12 | sles-15 | ubuntu-16 )
            PARTITIONS=(); for dev in "${DEVICES[@]}"; do PARTITIONS+=( $(ls ${dev}-part*) ); done ;;
        * )
            PARTITIONS=(); for dev in "${DEVICES[@]}"; do PARTITIONS+=( $(ls ${dev}[1-9]) ); done ;;
    esac
    for ((i=0; i<${#PARTITIONS[@]}; i++)); do
        pvcreate -ff -y ${PARTITIONS[$i]}
        assert_fail $? 0 "PASSED if physical volume could be created on ${PARTITIONS[$i]}"
        sleep 0.3
        echo
    done

    echo
    echo "Listing all physical volumes:"
    echo
    pvs
}

function createVolumegroups {
    
    PHYSICAL_VOLUMES=($(pvs -o pv_all --noheadings --separator : | awk -F: '{print $4}'))
    NUMBER_PHYSICAL_VOLUMES=(${PVS1} ${PVS2} ${PVS3} ${PVS4} ${PVS5})
    VOLUMEGROUPS=(${VGNAME1} ${VGNAME2} ${VGNAME3} ${VGNAME4} ${VGNAME5})
    START=0
    for ((i=0; i<${#VOLUMEGROUPS[@]}; i++)); do
        echo "vgcreate -f -y ${VOLUMEGROUPS[$i]} ${PHYSICAL_VOLUMES[@]:${START}:${NUMBER_PHYSICAL_VOLUMES[$i]}}"
        vgcreate -f -y ${VOLUMEGROUPS[$i]} ${PHYSICAL_VOLUMES[@]:${START}:${NUMBER_PHYSICAL_VOLUMES[$i]}}
        assert_fail $? 0 "PASSED if volume ${VOLUMEGROUPS[$i]} group could be created"
        sleep 0.5
        START=$(expr ${START} + ${NUMBER_PHYSICAL_VOLUMES[$i]})
    done
    echo
    echo "Listing all volumegroups:"
    echo
    vgs
}

function deletePartitions {

    cat ${DEVICE_LIST} |
    while read LINE; do
        STORAGENAME=$(echo ${LINE} | awk '{print $4}')
        DEVICE=$(echo ${LINE} | awk '{print $1}')
                
        assert_warn 0 0 "deleting partition(s) on ${DEVICE} on storage unit ${STORAGENAME}"

        for i in $(parted -s ${DEVICE} print| awk '/^ / {print $1}'); do
            parted -s ${DEVICE} rm $i
        done            
        udevadm settle
        sleep 0.5
    done
    partprobe

}

function display_usage {

    echo "Incorrect usage of the script."
    echo 
    echo "Usage: "
    echo 
    echo "   ${0} [ -nocleanup ]"
    echo
    exit ${RC_ERROR}
}

function isMounted {
  
    if (grep "$1" /proc/mounts); then
        return 0
    fi
    return 1
}

function mountingLogicalVolumes {
    
    if (isSles); then
        grep btrfs /etc/filesystems
        if [ $? -ne 0 ]; then
          sed -i 1i"btrfs" /etc/filesystems
        fi
    fi

    VOLUMELIST=($(lvs -o lv_path --noheadings))
    MOUNT_POINTS=($(lvs -o lv_name --noheadings))

    for ((i=0; i<${#VOLUMELIST[@]}; i++)); do
        if [[ -d  ${MOUNT_DIR}/${MOUNT_POINTS[$i]} ]]; then
            rm -rf  ${MOUNT_DIR}/${MOUNT_POINTS[$i]}
            sleep 1
        fi
        mkdir -p  ${MOUNT_DIR}/${MOUNT_POINTS[$i]}
        assert_fail $? 0 "mkdir -p  ${MOUNT_DIR}/${MOUNT_POINTS[$i]}"
        sleep 1
        echo "mount ${VOLUMELIST[$i]} ${MOUNT_DIR}/${MOUNT_POINTS[$i]}"
        mount ${VOLUMELIST[$i]} ${MOUNT_DIR}/${MOUNT_POINTS[$i]}
        assert_fail $? 0 "mount ${VOLUMELIST[$i]} ${MOUNT_DIR}/${MOUNT_POINTS[$i]}"
        sleep 1
        udevadm settle
        echo
    done
    cat /proc/mounts | grep ${MOUNT_DIR}
}

function mountingPartitions {
        
    if (isSles); then
        grep btrfs /etc/filesystems
        if [ $? -ne 0 ]; then
          sed -i 1i"btrfs" /etc/filesystems
        fi
    fi

    DEVICES=( $(awk '{print $1}' ${DEVICE_LIST}) )
    DISTRO=$(common::getDistributionName)

    case $DISTRO in
        sles-12 | sles-15 | ubuntu-16 )
            PARTITIONS=(); for dev in "${DEVICES[@]}"; do PARTITIONS+=( $(ls ${dev}-part*) ); done 
            MOUNT_POINTS=(); for dev in "${DEVICES[@]}"; do MOUNT_POINTS+=( $(ls ${dev}-part*  | sed 's!.*/!!') ); done ;;
        * )
            PARTITIONS=(); for dev in "${DEVICES[@]}"; do PARTITIONS+=( $(ls ${dev}[1-9]) ); done
            MOUNT_POINTS=(); for dev in "${DEVICES[@]}"; do MOUNT_POINTS+=( $(ls ${dev}[1-9] | sed 's!.*/!!') ); done ;;
    esac
    for ((i=0; i<${#PARTITIONS[@]}; i++)); do                
        if [[ -d  ${MOUNT_DIR}${MOUNT_POINTS[$i]} ]]; then
            rm -rf  ${MOUNT_DIR}/${MOUNT_POINTS[$i]}
            sleep 1
        fi
        mkdir -p  ${MOUNT_DIR}/${MOUNT_POINTS[$i]}
        assert_fail $? 0 "mkdir -p  ${MOUNT_DIR}/${MOUNT_POINTS[$i]}"
        sleep 1
        mount -t auto ${PARTITIONS[$i]} ${MOUNT_DIR}/${MOUNT_POINTS[$i]}
        assert_fail $? 0 "mount ${PARTITIONS[$i]} ${MOUNT_DIR}/${MOUNT_POINTS[$i]}"
        sleep 1
        echo
    done           

}

function removeLogicalVolumes {

    lvs 1>lvs.txt
    if [ -s lvs.txt ]; then 
        VOLUMELIST=$(lvs -o lv_all --noheadings --separator : | awk -F: '{print $3}')
        for I in ${VOLUMELIST}; do
            echo "lvchange -an $I"
            lvchange -an $I
            echo "lvremove -ff $I"
            lvremove -ff $I
            assert_fail $? 0 "PASSED if logical volume $I could be removed"
            udevadm settle
            lvs
        done
    else
      assert_warn 0 0 "No logical volumes found."
    fi
    rm -f lvs.txt
}

function removePhysicalVolumes {

    pvs 1>pvs.txt
    if [ -s pvs.txt ]; then    
        PVLIST=$(pvs -o pv_all --noheadings --separator : | awk -F: '{print $4}')
        for I in ${PVLIST}; do
            echo "pvremove -ff $I"
            pvremove -ff $I
            assert_fail $? 0 "PASSED if physical volume $I could be removed"
            udevadm settle
            pvs
        done
    else
        assert_warn 0 0 "No physical volumes found."
    fi
    rm -f pvs.txt
}

function removeVolumegroups {

    vgs 1>vgs.txt
    if [ -s vgs.txt ]; then
        VOLUMEGROUPLIST=$(vgs -o vg_all --noheadings --separator : | awk -F: '{print $3}')
        for I in ${VOLUMEGROUPLIST}; do
            echo "vgchange -an $I"
            vgchange -an $I
            echo "vgremove -ff $I"
            vgremove -ff $I
            assert_fail $? 0 "PASSED if volume group $I could be removed"
            udevadm settle
            vgs
        done
    else
      assert_warn 0 0 "No volume groups found." 
    fi
    rm -f vgs.txt
}

#function removeLVMfilter {            ### most likely not required anymore; was used in 20_setup.sh   TDI
#
#    LVMCONF=`find /etc -name lvm.conf`
#
#    grep -x '[[:space:]]\+filter[[:space:]]=[[:space:]]\[[[:space:]]\"a\/\.\*\/\"[[:space:]]\]' ${LVMCONF}
#    if [ $? -eq 0 ]; then
#        sed -i.bak '/[[:space:]]\+filter[[:space:]]=[[:space:]]\[[[:space:]]\"a\/\.\*\/\"[[:space:]]\]/d' ${LVMCONF}
#        assert_fail $? 0 "PASSED if LVM filter \"filter = [ "a/.*/" ]\" could be removed in ${LVMCONF}"
#    else
#        echo "LVM filter \"filter = [ \"a/.*/\" ]\" not found in ${LVMCONF}"
#    fi
#    assert_exec 0 "echo"
#
#    grep -x '[[:space:]]\+filter[[:space:]]=[[:space:]]\[[[:space:]]\"r|\/dev\/\.\*\/by-path\/\.\*|\",[[:space:]]\"r|\/dev\/\.\*\/by-id\/\.\*|\",\"r|\/dev\/fd\.\*|\",[[:space:]]\"r|\/dev\/cdrom|\",[[:space:]]\+\"a\/\.\*\/\"[[:space:]]]' ${LVMCONF}
#    if [ $? -eq 0 ]; then
#        sed -i.bak '/[[:space:]]\+filter[[:space:]]=[[:space:]]\[[[:space:]]\"r|\/dev\/\.\*\/by-path\/\.\*|\",[[:space:]]\"r|\/dev\/\.\*\/by-id\/\.\*|\",\"r|\/dev\/fd\.\*|\",[[:space:]]\"r|\/dev\/cdrom|\",[[:space:]]\+\"a\/\.\*\/\"[[:space:]]]/d' ${LVMCONF}
#        assert_fail $? 0 "PASSED if LVM filter \"filter = [ \"r|/dev/.*/by-path/.*|\", \"r|/dev/.*/by-id/.*|\",\"r|/dev/fd.*|\", \"r|/dev/cdrom|\",  \"a/.*/\" ]\" could be removed in ${LVMCONF}"
#    else
#        echo "LVM filter \"filter = [ \"r|/dev/.*/by-path/.*|\", \"r|/dev/.*/by-id/.*|\",\"r|/dev/fd.*|\", \"r|/dev/cdrom|\",  \"a/.*/\" ]\" not found in ${LVMCONF}"
#    fi
#    echo
#
#    grep -x '[[:space:]]\+filter[[:space:]]=[[:space:]]\[[[:space:]]\"r|\/dev\/\.\*\/by-path\/\.\*|\",[[:space:]]\"r|\/dev\/\.\*\/by-id\/\.\*|\",[[:space:]]\"a\/\.\*\/\"[[:space:]]]' ${LVMCONF}
#    if [ $? -eq 0 ]; then
#        sed -i.bak '/[[:space:]]\+filter[[:space:]]=[[:space:]]\[[[:space:]]\"r|\/dev\/\.\*\/by-path\/\.\*|\",[[:space:]]\"r|\/dev\/\.\*\/by-id\/\.\*|\",[[:space:]]\"a\/\.\*\/\"[[:space:]]]/d' ${LVMCONF}
#        assert_fail $? 0 "PASSED if LVM filter \"filter = [ \"r|/dev/.*/by-path/.*|\", \"r|/dev/.*/by-id/.*|\", \"a/.*/\" ]\" could be removed in ${LVMCONF}"
#    else
#        echo "LVM filter \"filter = [ \"r|/dev/.*/by-path/.*|\", \"r|/dev/.*/by-id/.*|\", \"a/.*/\" ]\" not found in ${LVMCONF}"
#    fi
#    echo
#
#    grep -x  "filter[[:space:]]=[[:space:]]\[ \"a|\/dev\/\.\*\/by-id\/\.\*|\",\"a|\/dev\/mapper\/\.\*|\",\"r\/\.\*\/\" \]" ${LVMCONF}
#    if [ $? -ne 0 ]; then
#        sed -i '86i filter = [ "a|/dev/.*/by-id/.*|","a|/dev/mapper/.*|","r/.*/" ]' ${LVMCONF}
#        assert_fail $? 0 "PASSED if LVM filter \"filter = [ \"a|/dev/.*/by-id/.*|\",\"r/.*/\" \]\" could be set in ${LVMCONF}"
#    else
#        echo "LVM filter \"filter = [ \"a|/dev/.*/by-id/.*|\",\"a|/dev/mapper/.*|\",\"r/.*/\" \]\" already set in ${LVMCONF}"
#    fi
#}

function startFIO {

    FIO_BIN=$(which fio)
    if [ ! -x $FIO_BIN ] ; then
        echo "$0: ERROR - fio executable not found - aborting" >&2
        exit 1
    fi
    if [ ! -d ${FIO_LOG_DIR} ] ; then
        mkdir -p ${FIO_LOG_DIR}
    fi
    FIO_LOG_FILE="${FIO_LOG_DIR}/$(date +%Y%m%d-%H%M)-fio.log"
    echo running nohup $FIO_BIN jobfile.fio --output=$FIO_LOG_FILE
    echo "cat jobfile.fio"
    cat jobfile.fio
    nohup $FIO_BIN jobfile.fio --output=$FIO_LOG_FILE 1>/dev/null 2>/dev/null &
    pid=$!
    assert_warn 0 0 "FIO is running as pid $pid logging into $FIO_LOG_FILE"
    # to make these variables accessible after leaving script 40_Start_FIO.sh and entering 60_Stop_FIO.sh"
    echo "pid=$pid"                    > fio.run
    echo "FIO_LOG_FILE=$FIO_LOG_FILE" >> fio.run
}

function stopFIO {

    source fio.run
    ps $pid
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "FIO process was not found, most likely stopped due to an error!!"
        echo "Important: Please investigate FIO logs for the reason!!"
        assert_fail $rc 0 "FIO process had already been terminated!"
    else
        assert_fail $rc 0 "FIO process found. OK. Terminating now."
        echo "kill $pid"
        assert_exec 0 "kill $pid"
        for i in $(seq 1 120); do
          sleep 1
          ps $pid
          if [ $? -ne 1 ]; then
            assert_warn 0 0 "FIO process $pid was not terminated after $i seconds."
          else
          assert_warn 0 0 "FIO process $pid terminated successfully after $i seconds."
            grep pid $FIO_LOG_FILE |grep err
            if [ $? -ne 0 ]; then
                assert_exec $? "echo FIO log file could not be evaluated. Please check manually!!"
            else 
                total=$(grep  pid $FIO_LOG_FILE |grep "err="   |wc -l)
                passed=$(grep pid $FIO_LOG_FILE |grep "err= 0" |wc -l)
                if [ $passed -lt $total ]; then 
                    assert_fail $(($total - $passed)) 0 "FIO FAILED!!"
                else
                    assert_warn 0 0 "FIO passed!!"
                fi
            fi
            return  # end of fio process evaluation; leave here
          fi
        done  
        assert_fail $pid 0 "FIO process $pid could not be terminated after $i seconds."
    fi

}

function unmountFilesystem {
  
    if  grep ${MOUNT_DIR} /proc/mounts  ; then
        for mp in $(grep ${MOUNT_DIR} /proc/mounts | awk '{print $2}'); do
            umount $mp
            assert_fail $? 0 "PASSED if ${mp} could be unmounted"
        done        
    else
        assert_warn 0 0 "Nothing mounted on ${MOUNT_DIR}"
    fi
}
