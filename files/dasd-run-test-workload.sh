#!/bin/bash
# Usage notes
# The purpose of this script is to
# - accept lists of DASD base and alias devices
# - set those devices online
# - lowlevel format
# - apply partitions
# - apply file systems
# - mount file systems
# - run a fio workload on all file systems for a given time (DASD_fio_basic)
#   or for a certain number of cable pull cycles (DASD_cablepull_fio)
#
# The scripts accepts five positional parameters:
# 1: either
#    a positive decimal number as runtime (in minutes) for the fio workload
#    in case of DASD_basic_fio
#    or
#    a set of parameters to control the SAN switch for cable pulling to run
#    DASD_cablepull_fio, as of:
#    -sw: hostname/IP of the SAN switch/Polatis switch
#    -ui: userid
#    -pw: password
#    -p: ports to use for cable pulls, within single quotes
#    -n: number of cable pull cycles
#    -toff: off-time in seconds
#    -ton: on-time in seconds
# 2: list of regular devices
# 3: list of large volumes (extended address volumes, EAV)
# 4: list of alias devices
# 5: options
#
# DASD_basic_fio: The runtime is given in minutes and must be a positive
#                 decimal integer number
# DASD_cablepull_fio: Cablepull control paramaters need to be specified,
#                     as shown above, encapsulated by double quotes
#
# Each device list must be a single string (no spaces) of comma
# separated devices specifications. Each device specification may be
# a single devno or busid, or range of the form <start>-<end>. If a
# devno is given, we assume that channel subsystem and subsystem set
# id are both 0. If a range is given with busids, both must have the
# same CSS and SSID
#
# The list of regular and EAV devices allow to specify
# file systems in the form <device-spec>(<fs name>)
# The supported file systems are:
#     ext2, ext3, ext4, xfs, btrfs (default is ext3)
#
# Regular DASD devices (can also be fullpack minidisks) may have any size and
# are only used with one partition. The EAV device(s) must have more than
# 65520 cylinders and will be used with up to three partitions.
#
# Supported options (parameter #5) are:
#   noformat:    do not apply low level format (dasdfmt)
#                This means that all devices must already be low
#                level formatted, or the script will fail.
#                The expected format is CDL with 4096 byte record size.
#   smartformat: Do lowlevel format only when necessary.
#                This is the default.
#   forceformat: Do a lowlevel format on all given devices.
#   mdiskowner=<userid>:
#                For z/VM minidisks specify the owning userid
#                to be used in the link statement
#   numjobs:     integer parameter overrides the default value of "4"
#                in the fiojobs.template (recommended value: 2....8)
#
# Multiple options have to be comma separated, without spaces.
#
# All parameters may be empty (just specify an empty string with double
# quotes ""), but you must specify at least one regular or large volume device.
#
# Please note, that you must use quotes if you specify file systems, to prevent
# the shell from interpreting the parentheses
#
# Example
# dasd-run-test-workload 120 "4711-4715(ext4),0.1.8000(btrfs)" "" 47f0-47ff "" "" noformat
#
# Please note, that the runtime counts before(!) the DASDs have been formatted
# and mounted and fio has written all fio files onto the file system.
#


# Load testlib
TESTLIBDIR="${TESTLIBDIR:-$(dirname $0)/}"
. "${TESTLIBDIR}lib/common/results.sh" || exit 1
. "${TESTLIBDIR}lib/common/environment.sh" || exit 1
. "${TESTLIBDIR}functions.sh" || exit 1
. "${TESTLIBDIR}dasd_functions.sh" || exit 1

DASDFORMATTYPE="smart"
MDISKOWNER=""

# all file systems will be mounted in automatically created subdirectories
# under the following directory
# BE CAREFUL:
#    To support cleanup after a failed run, all existing
#    subdirectories in this director may be removed automatically!
MOUNT_DIR="/mnt2"

# where to store the fio log files
FIO_LOG_DIR="./fio_log"

# Implementation notes:
# Many of the following functions work on arrays of devices, nodes, etc. Since
# we have similar arrays for regular devices, large volumes (EAV), fullpack
# minidisk and alias devices, we want to be able to call each function for each list.
# So we need a way to pass a whole array to a function, without using global
# variables. In addition we would like functions to return complex values,
# e.g. a list of busids, etc.
# To this end we use indirect variables, i.e. we only pass the name
# of the array or variable and dereference that name within the function.
# As an added complexity, we often need not just a single value, but multiple
# values, that belong together. In a language like C one would create a structure
# and pass arrays or lists of that structure type around, but we do not have
# that in bash. Instead we use a base name and add suffixes _dev, _fs, _block:
#  ${array_name}_dev   -> device busids
#  ${array_name}_fs    -> file system to be used on this device
#  ${array_name}_block -> block device nodes for this device
# The base names we use are
#  regular  -> any kind of DASD/MDISK (will get one partition)
#  eav      -> large volumes (Extended Address Volumes)
#  alias    -> alias devices


################################################################################
# all functions are located in this script:
# https://github.ibm.com/Linux-On-Z-Test/tree/master/roles/storage-test/files/dasd_functions.sh
#
################################################################################
################################################################################
#                               main                                           #
################################################################################


start_section 0 "Start of the DASD basic fio test"
init_tests

################################################################################
start_section 1 "Start of the parameter parsing"

# define ISVM as global variable, so I do not need to execute the isVM function every times
isVM	# Loads vmcp automatically
ISVM=$?

#echo $@
fio_run_time="$1"
regular_dasd="$2"
eav_dasd="$3"
alias_devices="$4"
options="$5"

echo "The test script was started with the following parameters:"

# detect whether we have a valid time setting or a set of cable pull parmeters
[[ $fio_run_time =~ ^[0-9]+$ ]]
if [ "$?" == "0" ]; then
    echo "fio run time           : $fio_run_time minutes"
else
    cablepull_controls="$fio_run_time"
    echo "cablepull controls     : $cablepull_controls"
    fio_run_time="14400"    # 10 days ~ infinite; cable pull will limit it
fi
echo "regular DASDs          : $regular_dasd (including fullpack minidisks)"
echo "Large Volumes          : $eav_dasd"
echo "Alias Devices          : $alias_devices"
echo "Options                : $options"

parse_device_list regular "$regular_dasd"
assert_fail $? 0 "parse the regular DASD list"

parse_device_list eav "$eav_dasd"
assert_fail $? 0 "parse the large volume (EAV) DASD list"

parse_device_list alias "$alias_devices"
assert_fail $? 0 "parse alias device list"

parse_global_options $options
assert_fail $? 0 "parse global options"

count_reg=${#regular_dev[*]}
count_eav=${#eav_dev[*]}
count_alias=${#alias_dev[*]}

# assert that we have at least one device to test with
(( count_reg + count_eav > 0 ))
assert_fail $? 0 "have at least one DASD"

[ -f "fio.template" ]
assert_fail $? 0 "fio.template exists"

end_section 1 "End of the parameter parsing"

################################################################################

start_section 1 "Start of device preparation"

# Includes opt. fullpack minidisks base dev.
enable_and_check_DASD regular_dev base
assert_fail $? 0 "enable regular DASD devices"

enable_and_check_DASD eav_dev base
assert_fail $? 0 "enable large volume (EAV) DASD devices"

wait_for_cio_settle

enable_and_check_DASD alias_dev alias
assert_fail $? 0 "enable alias devices"

wait_for_cio_settle
udevadm settle

find_names_for_devices regular
assert_fail $? 0 "find block device names for regular DASDs"

find_names_for_devices eav
assert_fail $? 0 "find block device names for EAV DASDs"

verify_EAV_size eav
assert_fail $? 0 "large volume (EAV) size check"

cleanup_old_mountpoints regular
assert_fail $? 0 "check regular devices for old mountpoints that need cleanup"

cleanup_old_mountpoints eav
assert_fail $? 0 "check EAV devices for old mountpoints that need cleanup"

format_devices regular eav $DASDFORMATTYPE
assert_fail $? 0 "apply and check low level format of devices"

partition_regular regular
assert_fail $? 0 "partition regular devices"

partition_eav eav
assert_fail $? 0 "partition EAV devices"

wait_for_cio_settle
udevadm settle

apply_file_systems_to_list regular
assert_fail $? 0 "apply file system to regular devices"

apply_file_systems_to_list eav
assert_fail $? 0 "apply file system to EAV devices"

udevadm settle

# Removing old files and mountpoins
rm -f fio.mountpoints
unmount_file_systems regular
unmount_file_systems eav

mount_file_systems regular fio.mountpoints
assert_fail $? 0 "mount file system for regular devices"

mount_file_systems eav fio.mountpoints
assert_fail $? 0 "mount file system for EAV devices"

echo "mount output after device preparation:"
mount


end_section 1 "End of device preparation"

################################################################################
###  THL & TDI  -  March 2020

start_section 1 "Install fio, if it does not exist"
FIO_BIN=$(which fio)
if [[ ! $FIO_BIN ]] && [[ ! -x $FIO_BIN ]]; then
    upm -y install fio
    assert_warn $? 0 "Install fio package"
fi

test -x $(which fio)
assert_fail $? 0 "0 = executable fio exists!"
end_section 1
################################################################################

start_section 1 "Start building the jobfile.fio"
rm -f jobfile.fio
make_job_file fio.mountpoints
echo " "
assert_fail $? 0 "building the jobfile.fio"
end_section 1
################################################################################

start_section 1 "Start of device workload via startFIO"
startFIO
assert_fail $? 0 "run fio workload via startFIO"
end_section 1
################################################################################

if [ "$fio_run_time" != "14400" ]; then   # DASD_basic_fio scenario with runtime
    start_section 1 "Start waiting $fio_run_time min"
    sleep ${fio_run_time}m
    assert_warn $? 0 "waiting (sleep) $fio_run_time min"
    end_section 1
else                       # DASD_cablepull_fio scenario with "infinite" runtime
    start_section 1 "Starting cable pull script"
    ./50_Cablepull.sh $cablepull_controls
    assert_fail $? 0 "cable pull script must return 0"
    end_section 1
fi

################################################################################

start_section 1 "Start shutdown FIO via stopFIO"
stopFIO
assert_fail $? 0 "shutdown FIO via stopFIO"
end_section 1
################################################################################

start_section 1 "Start of device shutdown"

wait_for_cio_settle
udevadm settle

unmount_file_systems regular
assert_fail $? 0 "unmount file system for regular devices"

unmount_file_systems eav
assert_fail $? 0 "unmount file system for EAV devices"

udevadm settle

if ! disable_DASD alias_dev
then
	echo "Warning: Problem encountered when disabling alias devices"
fi
if ! disable_DASD regular_dev
then
	echo "Warning: Problem encountered when disabling regular DASD devices"
fi
if ! disable_DASD eav_dev
then
	echo "Warning: Problem encountered when disabling EAV DASD devices"
fi

end_section 1 "End of device shutdown"


show_test_results
end_section 0
