#!/bin/bash 
#set -x 
# Script-Name:variables.sh
# Owner: Thorsten Diehl
# Date: 12.04.2017
# Description:  all required variables are stored here
#
#
#
#
DEBUG=yes

CONFIG_FILE="00_config-file"
CONTAINER_NAME=scsi_chpid_toggle_test
DEVICE_LIST=deviceList.txt
FIO_LOG_DIR=/root/log
MOUNT_DIR=/mnt1

# @Thorsten Winkler: you should remove the following, when you got rid of blast for docker testing
BLAST_CFG=blast.cfg
BLAST_LST=blast.lst
BLAST_LOG=/root/log
BLAST_BIN=/usr/local/tp4/BLAST/blast_s390x
