
ROLE_storage_test
===================

This repository contains the packages and configuration which is required for storage-test executions.

## Deployment

This role can be used as an requirement in your requirements.yml file. After that you can use this role
in your playbook.

### Requirements

Add the following dependencies to your requirements.yml

``` yaml
- name: distro-prereq
  src: https://oauth2:<TOKEN>@github.ibm.com/Linux-On-Z-Test/ROLE_distro_prereq.git
  scm: git
- name: test-lib
  src: https://oauth2:<TOKEN>@github.ibm.com/Linux-On-Z-Test/ROLE_test_lib.git
  scm: git
- name: test-defprogs
  src: https://oauth2:<TOKEN>@github.ibm.com/Linux-On-Z-Test/ROLE_test_defprogs.git
  scm: git
- name: system-test
  src: https://oauth2:<TOKEN>@github.ibm.com/Linux-On-Z-Test/ROLE_system_test.git
  scm: git
- name: storage-test
  src: https://oauth2:<TOKEN>@github.ibm.com/Linux-On-Z-Test/ROLE_storage_test.git
  scm: git

```

### storage_test
Role dependencies
- system_test



This role creates a storage setup with the following steps
- Installation of storage shell scripts like 15_LUN_Setup.sh
 now at "/usr/local/storage-test/".

 - /usr/local/tp4/default/lib/storage is as a link still available:

 ```
 /usr/local/tp4/default/lib/storage -> /usr/local//storage-test/
 ```

- Installation of SCSI Luns configs at

   ```
   /usr/local/storage-test/configs/SCSI_basic_fio
   /usr/local/storage-test/configs/SCSI_cablepull_fio
   ```
