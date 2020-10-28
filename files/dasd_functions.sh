#!/bin/bash
#set -x
# Script-Name: dasd_functions.sh
# Owner: Thomas Lambart
# Date: 12-03-2020
# Description:  all required functions for the DASD-scripts are contained here
#
#
#
#------------------------------------------------------------------------------



################################################################################
#                       file system handling                                   #
################################################################################

supported_file_systems="ext2 ext3 ext4 xfs btrfs"
default_file_system="ext3"

function fs_is_supported # fs
{
	for fs in $supported_file_systems
	do
		if [[ "$1" == "$fs" ]]
		then
			return 0
		fi
	done
	return 1
}

function apply_file_system_to_blockdev # blockdev fs
{
	local blockdev="$1"
	local fs="$2"

	echo "Apply fs $fs to $blockdev"
	if [[ "$fs" == "ext2" ]]
	then
		yes | mkfs.ext2 "$1"
		return $?
	elif [[ "$fs" == "ext3" ]]
	then
		yes | mkfs.ext3 "$1"
		return $?
	elif [[ "$fs" == "ext4" ]]
	then
		yes | mkfs.ext4 "$1"
		return $?
	elif [[ "$fs" == "xfs" ]]
	then
		if ! (command -v 'mkfs.xfs' &>/dev/null); then
	  		"${TESTLIBDIR}"lib/upm/upm.sh -y install xfsprogs
	  		assert_warn $? 0 "Install xfsprogs package"
		fi
		yes | mkfs.xfs -f "$1"
		return $?
	elif [[ "$fs" == "btrfs" ]]
	then
		if ! (command -v 'mkfs.btrfs' &>/dev/null); then
			"${TESTLIBDIR}"lib/upm/upm.sh -y install btrfs-progs
			assert_warn $? 0 "Install btrfs-progs package"
		fi
		yes | mkfs.btrfs -f "$1"
		return $?
	else
		echo "Cannot apply fs $fs to $blockdev: Unsupported file system"
	fi
	return 0
}


function apply_file_systems_to_list # devlist
{
	local devices="$1_dev"
	local nodes="$1_block"
	local filesystems="$1_fs"
	local count=0
	local i=0
	local dev devname devfs
	local rc=0
	local looprc=0

	eval count=\${#$devices[*]}
	for ((i = 0; i < count; ++i))
	do
		eval dev=\${$devices[$i]}
		eval devnode=\${$nodes[$i]}
		eval devfs=\${$filesystems[$i]}
		echo "Apply file systems to partitions of $dev $devnode"
		fdasd -s -p $devnode | while read partition rest
		do
			udevadm settle  # TDI 2019-02-19 Workaround for RHEL8 fdasd
			if [[ $partition =~ ^/dev/ ]]; then  # TDI 2019-02-18 Workaround for RHEL8 fdasd
				echo $partition
				if [[ -b $partition ]]
				then
					apply_file_system_to_blockdev $partition $devfs
					rc=$?
					if [[ $rc != 0 ]]
					then
						return $rc
					fi
				fi
			fi
		done
		looprc=$?
		if [[ $looprc != "0" ]]
		then
			return $looprc
		fi
	done
	return 0
}


# We need to get a list of all mount points for the call to fio later on
# so in addition to mounting, all mount points are added to the file fio_mountpoints
function mount_file_systems # devlist
{
	local devices="$1_dev"
	local nodes="$1_block"
	local filesystems="$1_fs"
	local fio_mountpoints="$2"
	local count=0
	local i=0
	local dev devname devfs

	eval count=\${#$devices[*]}
	for ((i = 0; i < count; ++i))
	do
		eval dev=\${$devices[$i]}
		eval devnode=\${$nodes[$i]}
		eval devfs=\${$filesystems[$i]}
		partno=0
		# Note: each part of a pipe executes in a subchell, so the return
		# jumps us out of the while loop but not from the for loop
		# and I have to explicitly check the return code
		fdasd -s -p $devnode | while read partition rest
		do
			udevadm settle # TDI 2019-02-19 Workaround for RHEL8 fdasd
			if [[ $partition =~ ^/dev/ ]]; then  # TDI 2019-02-18 Workaround for RHEL8 fdasd
				if ! [[ -b $partition ]] # pass over error messages
				then
					continue
				fi
				(( partno++ ))
				mountpoint="$MOUNT_DIR/$dev-part$partno"
				echo "mount $dev $partition to $mountpoint"
				if ! mkdir -p "$mountpoint"
				then
					echo "Could not create mount directory $mountpoint"
					return 1
				fi
				if ! mount "$partition" "$mountpoint"
				then
					echo "Could not mount $partition to $mountpoint"
					return 1
				fi

				echo "$dev-part$partno" >> $fio_mountpoints
			fi
		done
		looprc=$?
		if [[ $looprc != "0" ]]
		then
			return $looprc
		fi
	done
	return 0
}


function unmount_file_systems # devlist
{
	local devices="$1_dev"
	local nodes="$1_block"
	local filesystems="$1_fs"
	local count=0
	local i=0
	local dev devname devfs

	eval count=\${#$devices[*]}
	for ((i = 0; i < count; ++i))
	do
		# I am using the same iteration method as for mounting
		# perhaps I should rather go through all mount points
		# in $MOUNT_DIR
		eval dev=\${$devices[$i]}
		eval devnode=\${$nodes[$i]}
		eval devfs=\${$filesystems[$i]}
		partno=0
		# Note: each part of a pipe executes in a subchell, so the return
		# jumps us out of the while loop but not from the for loop
		# and I have to explicitly check the return code
		fdasd -s -p $devnode | while read partition rest
		do
      udevadm settle # TDI 2019-02-19 Workaround for RHEL8 fdasd
      if [[ $partition =~ ^/dev/ ]]; then  # TDI 2019-02-18 Workaround for RHEL8 fdasd
				if ! [[ -b $partition ]] # pass over error messages
				then
					continue
				fi
				(( partno++ ))
				mountpoint="$MOUNT_DIR/$dev-part$partno"
				if ! umount "$mountpoint"
				then
					echo "Could not unmount $mountpoint"
					return 1
				fi
                
				rmdir "$mountpoint"
			fi
		done
		looprc=$?
		if [[ $looprc != "0" ]]
		then
			return $looprc
		fi
	done
	return 0
}

# similar to unmount_file_systems, but this time we explicitly check
# if the device is actually mounted
function cleanup_old_mountpoints # devlist
{
	local devices="$1_dev"
	local nodes="$1_block"
	local filesystems="$1_fs"
	local count=0
	local i=0
	local dev devname devfs

	currentmounts=$(mount)

	eval count=\${#$devices[*]}
	for ((i = 0; i < count; ++i))
	do
		# I am using the same iteration method as for mounting
		# perhaps I should rather go through all mount points
		# in $MOUNT_DIR
		eval dev=\${$devices[$i]}
		eval devnode=\${$nodes[$i]}
		eval devfs=\${$filesystems[$i]}
		partno=0
		# Note: each part of a pipe executes in a subchell, so the return
		# jumps us out of the while loop but not from the for loop
		# and I have to explicitly check the return code
		fdasd -s -p $devnode | while read partition rest
		do
      udevadm settle # TDI 2019-02-19 Workaround for RHEL8 fdasd
      if [[ $partition =~ ^/dev/ ]]; then  # TDI 2019-02-18 Workaround for RHEL8 fdasd
				if ! [[ -b $partition ]] # pass over error messages
				then
					continue
				fi
				if ! echo $currentmounts | grep -q "$partition"
				then
					continue
				fi
				(( partno++ ))
				mountpoint="$MOUNT_DIR/$dev-part$partno"
				if ! umount "$partition"
				then
					echo "old mounts:"
					echo $currentmounts
					echo
					echo "Could not unmount $partition"
					return 1
				fi
				rmdir "$mountpoint"
			fi
		done
		looprc=$?
		if [[ $looprc != "0" ]]
		then
			return $looprc
		fi
	done
	return 0
}


################################################################################
#                        device handling                                       #
################################################################################

CIO_SETTLE="/proc/cio_settle"

function wait_for_cio_settle
{
	if [ -w $CIO_SETTLE ]
	then
		echo 1 > $CIO_SETTLE
	else
		echo "no cio_settle available, sleep a bit instead"
		sleep 5
	fi
}

# strip css and ssid from busid to get device number
# attach or link as required
function attach_link_device # busid
{
	local busid=$1
	local devno=""
	local safe_IFS="$IFS"
	IFS="."
	set $busid
	IFS="$safe_IFS"
	if [[ $# == "1" ]]
	then
		devno="$1"
	elif [[ $# == "3" ]]
	then
		devno="$3"
	else
		echo "Cannot attach device. Busid \"$input\" is malformed."
		return 1
	fi
	# Try attach first, if that fails try linking
	if ! vmcp "att $devno *" && [[ $MDISKOWNER != "" ]]
	then
		echo "Attaching device $devno failed, try to link it."
		vmcp "LINK $MDISKOWNER $devno $devno WR"
	fi
	wait_for_cio_settle
	udevadm settle
	return $?
}

function detach_device # busid
{
	local busid=$1
	local devno=""
	local safe_IFS="$IFS"
	IFS="."
	set $busid
	IFS="$safe_IFS"
	if [[ $# == "1" ]]
	then
		devno="$1"
	elif [[ $# == "3" ]]
	then
		devno="$3"
	else
		echo "Cannot detach device. Busid \"$input\" is malformed."
		return 1
	fi

	vmcp "det $devno"
	return $?
}


function make_device_available # busid
{
	echo "Try to make device $1 available"
	# first, remove device from cio_ignore list
	cio_ignore -r $1
	if [[ -d "/sys/bus/ccw/devices/$dev" ]]
	then
		return 0
	fi

	# if the device is still not available and we are
        # in z/VM, we may need to attach or link the device
	if [[ "$ISVM" != "0" ]]
	then
		return 1
	fi
	attach_link_device $1
	return $?
}

# make DASD available, attach if necessary
# and verify that it is actually a DASD
function enable_and_check_DASD # devlist base_or_alias
{
	local devices=$1
	local base_or_alias=$2 # "base" or "alias"
	local count=0
	local i=0
	local dev

	eval count=\${#$devices[*]}
	for ((i = 0; i < count; ++i))
	do
		eval dev=\${$devices[$i]}
		# assert that device exist
		if [[ ! -d "/sys/bus/ccw/devices/$dev" ]]
		then
			make_device_available $dev
			wait_for_cio_settle
		fi
		sleep 0.5
		if [[ ! -d "/sys/bus/ccw/devices/$dev" ]]
		then
			echo "Device $dev is not available in the system"
			return 1
		fi
		virt_io_count=$(readlink -m  "/sys/bus/ccw/devices/$dev" | cut -d'/' -f5 | cut -d'.' -f3 | sed 's/^0\+//g' )

		driver=$(readlink "/sys/bus/ccw/devices/$dev/driver")

		if ! [[ $driver =~ .*(eckd|fba|virtio_ccw)$ ]]
		then
			echo "Device $dev is not an ECKD, FBA DASD or Virtblk"
			return 1
		else
			if [[ $driver =~ .*(virtio_ccw)$ ]]
				then
					virt_io=/virtio$virt_io_count/block
					virt_io_state=y
				else
					virt_io=/block
					virt_io_state=n
			fi
		echo "variable virtio: "$virt_io
		fi
		if ! chccwdev -e $dev
		then
			echo "Failed to enable device $dev"
			return 1
		fi

		read isAlias < /sys/bus/ccw/devices/$dev/alias
		if [[ $base_or_alias == "base" ]] && [[ $isAlias == "1" ]]
		then
			echo "Device $dev is not a DASD base device, it is an alias."
			return 1
		elif [[ $base_or_alias != "base" ]] && [[ $isAlias == "0" ]]
		then
			echo "Device $dev is not an alias device, it is a DASD base device."
			return 1
		fi
	done
	return 0
}

function disable_DASD # devlist
{
	local devices=$1
	local count=0
	local i=0
	local dev

	eval count=\${#$devices[*]}
	for ((i = 0; i < count; ++i))
	do
		eval dev=\${$devices[$i]}
		if [[ ! -d "/sys/bus/ccw/devices/$dev" ]]
		then
			echo "Device $dev is not available in the system"
		fi
		if ! chccwdev -d $dev
		then
			echo "Failed to disable device $dev"
		fi
		if [[ "$ISVM" == "0" ]]
		then
			detach_device $dev
		fi
	done
	return 0
}

function find_devname_for_busid # devnamevar busid
{
	local devnamevar=$1
	local busid=$2
	echo $virt_io
	local virt_io2=$virt_io
	echo $virt_io2
	echo $virt_io_state

	if [[ $virt_io_state == 'y' ]]; then
		if [[ -d /sys/bus/ccw/devices/$busid/$virt_io2/ ]]; then
			# use bash file name globbing to find the block device name
			name=/sys/bus/ccw/devices/$busid/$virt_io2/vd*
			name=$(basename $name)
		else
			name=""
		fi
	else
		if [[ -d /sys/bus/ccw/devices/$busid/$virt_io2/ ]]; then
			# use bash file name globbing to find the block device name
			name=/sys/bus/ccw/devices/$busid/$virt_io2/dasd*
			name=$(basename $name)
		else
			name=""
		fi
	fi

	eval $devnamevar=\$name
}


# this function takes the base name for one of the device list (e.g. regular)
# takes every device busid in regular_dev, finds the matching block device names
# and creates a list regular_block with device node names
function find_names_for_devices # listbasename
{

	local devices="$1_dev"
	local nodes="$1_block"
	local count=0
	local i=0
	local dev
	local devnode

	eval count=\${#$devices[*]}
	for ((i = 0; i < count; ++i))
	do
		eval dev=\${$devices[$i]}
		find_devname_for_busid devname $dev
		if [[ "$devname" == "" ]]
		then
			echo "could not determine device name for busid $dev"
			return 1
		fi
		devnode="/dev/$devname"
		eval "$nodes[$i]"="\$devnode"
	done
	return 0
}

function verify_EAV_size # devlist
{
	local devices="$1_dev"
	local nodes="$1_block"
	local count=0
	local i=0
	local dev
	local devname

	eval count=\${#$devices[*]}
	for ((i = 0; i < count; ++i))
	do
		eval dev=\${$devices[$i]}
		eval devnode=\${$nodes[$i]}
		if ! cylline=$(dasdview -i "$devnode" | grep "number of cylinders")
		then
			echo "error when gathering cylinder information for $devnode/$dev"
			return 1
		fi
		set $cylline
		cylinders=$8
		if (( cylinders <= 65520 )) # cylinder boundary for EAV
		then
			echo "Device $devnode / $dev has $cylinders and is too small for an EAV."
			return 1
		fi
	done
	return 0
}

function is_dasd_formatted # devnode
{
	local devnode=$1
	local sectorsize
	local disksize
	sectorsize=$(blockdev --getss "$devnode")
	disksize=$(blockdev --getsize64 "$devnode")
	if [[ $virt_io_state == 'y' ]]
	then
		iscdl=0
	else
		dasdview -x "$devnode" | grep -q "CDL formatted"
		iscdl=$?
	fi
	if [[ $sectorsize != 4096 ]] || [[ $disksize == 0 ]] || [[ $iscdl != 0 ]]
	then
		return 1
	fi
	return 0
}


# I want to format all devices in parallel, so I need to go
# through both lists in one call
function format_devices # regular eav type
{
	local regdev="$1_dev"
	local regnodes="$1_block"
	local eavdev="$2_dev"
	local eavnodes="$2_block"
	local formattype=$3
	local count=0
	local i=0
	local dev
	local devname

	echo "Start formatting of devices (format type \"$formattype\")"
	if [[ $formattype == "no" ]]
	then
		echo " suppress low level format "
	else
		eval count=\${#$regdev[*]}
		for ((i = 0; i < count; ++i))
		do
			eval dev=\${$regdev[$i]}
			eval devnode=\${$regnodes[$i]}
			if [[ $formattype == "smart" ]] && is_dasd_formatted "$devnode"
			then
				echo "low level format not necessary for device $dev $devnode"
				continue
			fi
			echo "format device $dev $devnode"
			dasdfmt -b 4096 -d cdl -y "$devnode" &
		done
		eval count=\${#$eavdev[*]}
		for ((i = 0; i < count; ++i))
		do
			eval dev=\${$eavdev[$i]}
			eval devnode=\${$eavnodes[$i]}
			if [[ $formattype == "smart" ]] && is_dasd_formatted "$devnode"
			then
				echo "low level format not necessary for device $dev $devnode"
				continue
			fi
			echo "format device $dev $devnode"
			dasdfmt -b 4096 -d cdl -y "$devnode" &
		done
	fi
	wait

	wait_for_cio_settle
	udevadm settle

	# verify that devices are now formatted
	eval count=\${#$regdev[*]}
	for ((i = 0; i < count; ++i))
	do
		eval dev=\${$regdev[$i]}
		eval devnode=\${$regnodes[$i]}
		if ! is_dasd_formatted "$devnode"
		then
			echo "Device $dev $devnode has not been properly formatted"
			return 1
		fi
	done
	eval count=\${#$eavdev[*]}
	for ((i = 0; i < count; ++i))
	do
		eval dev=\${$eavdev[$i]}
		eval devnode=\${$eavnodes[$i]}
		if ! is_dasd_formatted "$devnode"
		then
			echo "Device $dev $devnode has not been properly formatted"
			return 1
		fi
	done
	return 0
}


function partition_regular # devlist
{
	local devices="$1_dev"
	local nodes="$1_block"
	local count=0
	local i=0
	local dev
	local devname

	eval count=\${#$devices[*]}
	for ((i = 0; i < count; ++i))
	do
		eval dev=\${$devices[$i]}
		eval devnode=\${$nodes[$i]}
		udevadm settle
		if ! fdasd -a "$devnode"
		then
			echo "Error when partitioning regular device $dev $devnode "
			return 1
		fi
	done
	return 0
}


# Important: This function assumes that the device is formatted with 4KB blocks
#            => 12 * 4KB per track
#            If you want to extend this to all record sizes, then you need a
#            way to find out the number of records per track (e.g. dasdview).
#            This function also assumes that we are on a device with more than
#            65520 cylinders (== EAV).
function partition_eav # devlist
{
	local devices="$1_dev"
	local nodes="$1_block"
	local count=0
	local i=0
	local dev
	local devname
	local sectorsize
	local disksize
	local totalsizeintracks
	# partition size is in tracks 65520*15
	local partitionsize=982800


	eval count=\${#$devices[*]}
	for ((i = 0; i < count; ++i))
	do
		eval dev=\${$devices[$i]}
		eval devnode=\${$nodes[$i]}

		sectorsize=$(blockdev --getss "$devnode")
		disksize=$(blockdev --getsize64 "$devnode")

		if (( sectorsize != 4096 ))
		then
			echo "Unsupported record size ($sectorsize) for EAV partitioning."
		fi
		(( totalsizeintracks = disksize / (sectorsize * 12) ))

		if (( totalsizeintracks <= partitionsize ))
		then
			echo "Unsupported disk size ($totalsizeintracks tracks) for EAV partitioning."
		fi

		echo "Partition device $dev $devnode (disksize = $disksize, total size in tracks = $totalsizeintracks)"
		# TBD do I need to worry about the current directory?

		echo "# partition configuration for EAV device $dev $devnode" > partconf.tmp
		# first partition: first 65520 cylinders
		(( partend = partitionsize - 1))
		echo "[first,$partend]" >> partconf.tmp

		# second partition: next 65520 cylinders, or to the end of the device
		partstart=$partitionsize
		(( partend = 2 * partitionsize - 1))
		if (( partend >= totalsizeintracks - 1))
		then
			echo "[$partstart,last]]" >> partconf.tmp
		else
			echo "[$partstart,$partend]" >> partconf.tmp
		fi

		# third partition: rest of the device
		(( partstart = 2 * partitionsize ))
		if (( partstart <= totalsizeintracks ))
		then
			echo "[$partstart,last]" >> partconf.tmp
		fi

		udevadm settle

		if ! fdasd -c partconf.tmp "$devnode"
		then
			echo "Error when partitioning EAV device $dev $devnode "
			return 1
		fi
	done
	return 0
}




################################################################################
#                       Input parameter parser                                 #
################################################################################

# This function parses the input string (devno or busid), splits it into parts
# and makes sure they are recognized as hex numbers by adding '0x' to the string
# If the input is just a devno then css and ssid are set to 0.
function convert_busid_to_int # cssout ssidout devnoout input
{
	local cssvar=$1
	local ssidvar=$2
	local devnovar=$3
	local input=$4

	local safe_IFS="$IFS"
	IFS="."
	set $input
	IFS="$safe_IFS"
	if [[ $# == "1" ]]
	then
		eval $cssvar=0
		eval $ssidvar=0
		eval $devnovar="$1"
	elif [[ $# == "3" ]]
	then
		eval $cssvar="$1"
		eval $ssidvar="$2"
		eval $devnovar="$3"
	else
		echo "The input value \"$input\" has neither the format of a devno nor of a busid."
		return 1
	fi

	#verify that all strings are numbers
	if ! [[ ${!cssvar} =~ ^[0-9a-f]$ ]]
	then
		echo "The string \"${!cssvar}\" does not match the pattern for a channel subsystem number."
		return 1
	fi
	if ! [[ ${!ssidvar} =~ ^[0-9a-f]$ ]]
	then
		echo "The string \"${!ssidvar}\" does not match the pattern for a subsystem ID number."
		return 1
	fi
	if ! [[ ${!devnovar} =~ ^[0-9a-f]{1,4}$ ]]
	then
		echo "The string \"${!devnovar}\" does not match the pattern for a device number."
		return 1
	fi

	eval $cssvar=0x${!cssvar}
	eval $ssidvar=0x${!ssidvar}
	eval $devnovar=0x${!devnovar}
	return 0
}

function parse_group # output_variable group
{
	local output_dev="${1}_dev"
	local output_fs="${1}_fs"
	local group=$2
	local token
	local count
	local usefs
	local outputdev

	# split the group string in the device list and the
	# parameters part in parentheses
	# Note that 'expr' starts indexing at 1 but bash at 0
	firstparpos=$(expr index "$group" '\(')
	if [[ $firstparpos -lt "1" ]]
	then
		# no parameter, use default file system
		usefs=$default_file_system
		devices=$group
	else
		((firstparpos--))
		devices=${group:0:$firstparpos}
		parameters=${group:$firstparpos}

		# parameter parsing is very simple at the moment,
        	# we only allow to specify the file system
		secondparpos=$(expr index "$parameters" '\)')
		((secondparpos -= 2)) # the index before the ')'
		bareparameters=${parameters:1:$secondparpos}
		if ! fs_is_supported $bareparameters
		then
			echo "Unknown option $bareparameters in device group $group"
			return 1
		fi
		usefs=$bareparameters
	fi
	# At this point $usefs contains the file system we use for all
	# devices in the group and $devices contains the device
	# specification, which we have to parse now.

	# The devices string should either be a single device number
	# or busid, or a start-end pair (<busid> or <busid>-<busid>).
	# If it is a device number, we assume that it is in channel
	# subsystem 0 and subsystem set 0 If it is a full busid, and
	# the busid is part of a pair, then both busids need to
	# specify the same css and ssid.

	# 1. search for a '-' to identify pairs
        # 2. if there is a pair, split up into start and end busid
        #    otherwise we only have a start busid
	# 3. convert the busid strings in to triples of integers
        #    add missing information
        # 4. verify the start and end numbers (e.g. check for too large device numbers, etc.)
	# 5. create one or a sequence of busid+filesystem pairs in the output variables

	hyphenpos=$(expr index "$devices" '-')

	if [[ $hyphenpos -lt "1" ]]
	then
		# just a single value
		startinput=$devices
		endinput=""
	else
		endinput=${devices:$hyphenpos}
		((hyphenpos--))
		startinput=${devices:0:$hyphenpos}
	fi

	# convert busid strings to separate numbers
	if ! convert_busid_to_int startcss startssid startdevno $startinput
	then
		return 1
	fi

	# how many elements are currently in the indirect addressed output array?
	eval count=\${#$output_dev[*]}
	# if we have just a single busid, then add the busid to the output array
	if [[ -z $endinput ]]
	then
		# handle single device here
		printf -v outputdev "%x.%x.%04x" $startcss $startssid $startdevno
		eval "$output_dev[$count]"="\$outputdev"
		eval "$output_fs[$count]"="\$usefs"
		return 0
	fi

	# handle sequence here
	if convert_busid_to_int endcss endssid enddevno $endinput
	then
		if [[ "$startcss" != "$endcss" ]]
		then
			echo "Channel Subsystem ID does not match in range \"$devices\""
			return 1
		fi
		if [[ "$startssid" != "$endssid" ]]
		then
			echo "Subsystem Set ID does not match in range \"$devices\""
			return 1
		fi
		for ((dev = startdevno; dev <= enddevno; ++dev))
		do
			printf -v outputdev "%x.%x.%04x" $startcss $startssid $dev
			eval "$output_dev[$count]"="\$outputdev"
			eval "$output_fs[$count]"="\$usefs"
			((++count))
		done
	else
		echo "could not parse \"$endinput\""
		return 1
	fi
}


# This is the main function to parse an device parameter string of the
# form "4711,9900-990a(ext4),0.1.8800(xfs)" or similar
# (TBD more formal description of input string)
#
# The function parses an the input parameter string and creates one or
# more busid/filesystem pairs, which are placed in two output arrays.
# The base name of the output arrays is given as parameter and
# the arrays are named ${output_base}_dev and ${output_base}_fs
function parse_device_list # output_base
{
	local token
	local count=0
	local output_variable=$1


	local safe_IFS="$IFS"
	IFS=","
	for token in $2
	do
		IFS="$safe_IFS"
		if ! parse_group $output_variable $token
		then
			echo "Error during parsing of \"$token\""
			return 1
		fi
		((++count))
	done
	IFS="$safe_IFS"
}

function parse_global_options
{
	local token
	local safe_IFS="$IFS"
	IFS=","
	for token in $1
	do
		IFS="$safe_IFS"
		if [[ "$token" == "noformat" ]]
		then
			DASDFORMATTYPE="no"
		elif [[ "$token" == "smartformat" ]]
		then
			DASDFORMATTYPE="smart"
		elif [[ "$token" == "forceformat" ]]
		then
			DASDFORMATTYPE="force"
		elif [[ $token =~ mdiskowner=.*$ ]]
		then
			MDISKOWNER=${token:11}
		elif [[ $token =~ numjobs=.*$ ]]
		then
			NUMJOBS=$(echo $token |cut -d "=" -f 2)
		else
			echo "unrecognized option \"$token\""
			return 1
		fi
	done
	IFS="$safe_IFS"
	return 0
}


################################################################################
#                            fio functions                                     #
################################################################################

function make_job_file # build the jobfile.fio
{

  local fio_mountpoints=$1
  local fio_runtime=$2      # (in minutes)

  cat ${fio_mountpoints} |
  while read MOUNT_POINT; do
    if [[ `echo ${MOUNT_POINT}` != "" ]]; then
      if grep ${MOUNT_POINT} /proc/mounts > /dev/null 2>&1; then
        fstype=$(stat -f -c %T ${MOUNT_DIR}/${MOUNT_POINT})
        if [ ! -z "$NUMJOBS" ]; then # passed as parameter
          workers=$NUMJOBS
        else # get it from template
          workers=$(cat fio.template | grep "numjobs" | sed -e s/numjobs=//g)
        fi
        fsfree=$(df -k ${MOUNT_DIR}/${MOUNT_POINT} | grep ${MOUNT_DIR}/${MOUNT_POINT} | awk '{print $4}')
        if [ "$fstype" == "btrfs" ]; then
          size=$((${fsfree}/${workers}*40/100))
            else
          size=$((${fsfree}/${workers}*90/100))
        fi
        echo "[${MOUNT_POINT}]"                       > ${MOUNT_POINT}.fio
        cat fio.template                             >> ${MOUNT_POINT}.fio
        # echo "runtime=${fio_runtime}m"               >> ${MOUNT_POINT}.fio
        echo "size=${size}k"                         >> ${MOUNT_POINT}.fio
        echo "directory=${MOUNT_DIR}/${MOUNT_POINT}" >> ${MOUNT_POINT}.fio
        assert_warn 0 0 "${MOUNT_POINT}.fio created, now merging the lists"
        cat ${MOUNT_POINT}.fio >> jobfile.fio
        echo " "               >> jobfile.fio
      else
        assert_warn 1 0 "${MOUNT_DIR}/${MOUNT_POINT} not mounted"
      fi
      echo
    fi
  done


 if [ ! -z "$NUMJOBS" ]; then
   sed -i "s/numjobs=.*/numjobs=$NUMJOBS/g" jobfile.fio
   echo "jobfile.fio adjusted to numjobs=$NUMJOBS"
 fi
  
}

