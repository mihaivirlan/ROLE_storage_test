#!/bin/bash 
#set -x 
# Script-Name:variables.sh
# Owner: Thorsten Diehl
# Date: 04.03.2021
#
# Description:  some required variables are stored here
# This script should be sourced for manual debiggung in bash only
# The nn_... scripts get their variables from the environment definition in 
# the testcase.xml file
#
DEBUG=yes

DEVICE_LIST=deviceList.txt
FIO_LOG_DIR=/root/log
MOUNT_DIR=/mnt1

