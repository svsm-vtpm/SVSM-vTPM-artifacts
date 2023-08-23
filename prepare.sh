#!/usr/bin/env bash

set -eou pipefail

SCRIPT_DIR="$(readlink -f $(dirname $0))"
BASENAME="$(basename $0)"
SVSM=$(readlink -f ${SCRIPT_DIR}/linux-svsm)

install_prereqs() {
  sudo apt update
  sudo apt install -y make ninja-build libglib2.0-dev libpixman-1-dev python3
  sudo apt install -y nasm iasl flex bison libelf-dev libssl-dev
  sudo apt install -y automake libclang-15-dev libtool build-essential autoconf autoconf-archive libc6-dev-i386 clang-15
  sudo apt install -y cloud-image-utils qemu-utils ovmf

  if ! dpkg -l | grep "libssl1.1:amd64"; then
    DPKG_TMP=$(mktemp -d)
    wget http://security.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2.19_amd64.deb -P ${DPKG_TMP}
    sudo dpkg -i ${DPKG_TMP}/*.deb
  fi
}

build_deps() {
  REBUILD=${1:-"no"}
  pushd ${SVSM}/scripts
  if [ ${REBUILD} == "yes" ]; then
    ./build.sh
  else
    if [ ! -f ./usr/local/bin/qemu-system-x86_64 ]; then
      ./build.sh qemu
    fi
    if [ ! -f usr/local/share/qemu/OVMF_CODE.fd ]; then
      ./build.sh ovmf
    fi
    if ! ls ../../linux/*-host*.deb ; then
      ./build.sh kernel host
    fi
    if ! ls ../../linux/*-guest*.deb ; then
      ./build.sh kernel guest
    fi
  fi
  popd
}

install_host_linux() {
  pushd ${SCRIPT_DIR}/linux
  if ls *.deb | grep "host"; then
    if ! ls /boot/vmlinuz-5.14.0-rc2-snp-host-e1287b7c0367; then
      sudo apt install ./*-host*.deb
    fi
  fi
  popd
}

build_svsm() {
  pushd ${SVSM}
  if [ ! -f svsm.bin ]; then
    make .prereq && make svsm.bin VERBOSE=1
  fi
  popd
}

IMAGE_FILE="jammy-server-cloudimg-amd64.img"
IMAGE_FILE_TPM="jammy-server-cloudimg-amd64-crb.img"

get_image_and_resize() {
  # get the cloud image
  if [ ! -f ${IMAGE_FILE}.orig ]; then
    wget https://cloud-images.ubuntu.com/jammy/current/${IMAGE_FILE}
  fi

  cp ${IMAGE_FILE}.orig ${IMAGE_FILE}
  cp ${IMAGE_FILE}.orig ${IMAGE_FILE_TPM}

  # resize
  qemu-img resize ${IMAGE_FILE} +20G
  qemu-img resize ${IMAGE_FILE_TPM} +20G
}

prepare_image() {
  if [ ! -d ${SCRIPT_DIR}/images ]; then
    mkdir -p ${SCRIPT_DIR}/images
  fi
  pushd ${SCRIPT_DIR}/images

  get_image_and_resize

  # create ssh keys
  if [ ! -f ${USER}.id_rsa ]; then
    ssh-keygen -t rsa -q -f ${USER}.id_rsa -N ""
  fi

  PUBKEY=""
  if [ -f ${USER}.id_rsa.pub ]; then
    PUBKEY=$(cat ${USER}.id_rsa.pub)
    KEYPATH=$(readlink -f ${USER}.id_rsa)
  fi

  cat > user-data <<EOF
#cloud-config
password: ubuntu
ssh_pwauth: false
ssh_authorized_keys:
  - ${PUBKEY}

package_update: true
package_upgrade: true
packages:
  - tpm2-tools
mounts:
 - [ host0, /mnt/shared, 9p, "trans=virtio,version=9p2000.L" ]
runcmd:
 - cd /mnt/shared
 - apt install -y ./*-guest*.deb
 - shutdown
EOF

  if [ ! -f ~/.ssh/config ]; then
  cat > ~/.ssh/config <<EOF
Host guest
    HostName 127.0.0.1
    User ubuntu
    IdentityFile ${KEYPATH}
    Port 5555
EOF
  fi

  # create user-data.img
  cloud-localds user-data.img user-data

  # copy benchmarking script
  if [ ! -f ${SCRIPT_DIR}/linux/tpm_benchmarks.sh ]; then
    cp ${SVSM}/scripts/benchmarks/tpm_benchmarks.sh ${SCRIPT_DIR}/linux/
  fi
  popd
}

install_new_guest_kernel() {
  pushd ${SVSM}/scripts
  sudo ./launch-qemu.sh -hda ../../images/${IMAGE_FILE} -mem 5G -console serial -novirtio -smp 1 -hdb ../../images/user-data.img -ssh-forward
  popd
}

run_svsm_benchmark() {
  pushd ${SCRIPT_DIR}/images
  cat > user-data-run <<EOF
#cloud-config
password: ubuntu
ssh_pwauth: false
ssh_authorized_keys:
  - ${PUBKEY}

package_update: true
package_upgrade: true
packages:
  - tpm2-tools
mounts:
 - [ host0, /mnt/shared, 9p, "trans=virtio,version=9p2000.L" ]

runcmd:
 - cd /mnt/shared
 - ./tpm_benchmarks.sh | tee svsm-vtpm.log
 - shutdown
EOF

  # create user-data.img
  cloud-localds user-data-run.img user-data-run
  popd

  pushd ${SVSM}/scripts
  sudo ./launch-qemu.sh -hda ../../images/${IMAGE_FILE} -mem 5G -console serial -novirtio -smp 1 -hdb ../../images/user-data-run.img -ssh-forward -sev-snp -svsmcrb -svsm ../svsm.bin
  popd
}

run_vtpm_benchmark() {
  pushd ${SCRIPT_DIR}/images

  PUBKEY=""
  if [ -f ${USER}.id_rsa.pub ]; then
    PUBKEY=$(cat ${USER}.id_rsa.pub)
  fi

  cat > user-data-qemu-tpm <<EOF
#cloud-config
password: ubuntu
chpasswd:
  expire: false
ssh_pwauth: false
ssh_authorized_keys:
  - ${PUBKEY}

package_update: true
package_upgrade: true
packages:
  - tpm2-tools
mounts:
 - [ host0, /mnt/shared, 9p, "trans=virtio,version=9p2000.L" ]

runcmd:
 - cd /mnt/shared
 - ./tpm_benchmarks.sh | tee qemu-vtpm.log
 - shutdown
EOF

  # create user-data.img
  cloud-localds user-data-qemu-tpm.img user-data-qemu-tpm
  get_image_and_resize

  popd

  pushd ${SVSM}/scripts
  sudo ./launch-qemu.sh -hda ../../images/${IMAGE_FILE_TPM} -mem 5G -console serial -novirtio -smp 1 -hdb ../../images/user-data-qemu-tpm.img -ssh-forward -tpm2
  popd
}

init() {
  # Install all the pre-requisites
  install_prereqs

  # Build the stack: Host/guest kernel, OVMF, Qemu
  build_deps

  # Build SVSM
  build_svsm
}

install_host_kernel() {
  # Install the SEV-SNP enabled host kernel
  install_host_linux
}

prep_guest() {
  # Prepare guest image
  prepare_image

  # Install guest kernel; relies on cloud-init
  install_new_guest_kernel
}

run_svtpm() {
  init

  prep_guest

  # Run SVSM-vTPM benchmark
  run_svsm_benchmark
}

run_qvtpm() {
  install_prereqs

  build_deps

  # Run Qemu-vTPM benchmarks
  run_vtpm_benchmark
}

help() {
  echo "Usage: ${BASENAME} <options>"
  echo "options:"
  echo -e "\tinit        installs prereqs and builds everything"
  echo -e "\tinstall     installs the SNP-enabled host kernel"
  echo -e "\tprep_guest  prepares guest image and installs SNP-enabled guest kernel"
  echo -e "\trun_svtpm   run SVSM-vTPM benchmark"
  echo -e "\trun_qvtpm   run Qemu-vTPM benchmark"
}

if [ $# == 0 ];then
  help
  exit
else
case $1 in
  init)
    init
    ;;
  install)
    install_host_kernel
    ;;
  prep_guest)
    prep_guest
    ;;
  run_svtpm)
    run_svtpm
    ;;
  run_qvtpm)
    run_qvtpm
    ;;
  *)
    echo "=> Unsupported option $1"
    help
    ;;
esac
fi
