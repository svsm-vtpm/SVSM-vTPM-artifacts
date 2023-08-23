# Artifact evaluation for SVSM-vTPM - ACSAC'23

Thank you for your time and for picking our paper for the artifact evaluation.

This documentation contains the steps necessary to reproduce the artifacts for
our paper titled **Remote attestation of confidential VMs using ephemeral
vTPMs**

We use a Dell PowerEdge R6525 machine on the
[Cloudlab Infrastructure](https://www.clemson.cloudlab.us/portal/show-nodetype.php?type=c6525)
to evaluate all the experiments.

The artifact contains the source code of the vTPM implementation running inside
the Secure VM Service Module (SVSM). Also, the entire software stack consisting
of Linux kernel, Qemu, OVMF, and Keylime is available as submodules.

## Setting up the hardware (Own infrastructure)

* To evaluate the experiments, you need to configure the BIOS to enable SEV-SNP
  related settings as described in the [official
  repository](https://github.com/AMDESE/AMDSEV/tree/sev-snp-devel#prepare-host)
  - If you encounter any issues in preparing the host, please refer to the existing
    [github issues](https://github.com/AMDESE/AMDSEV/issues).

* Once you have successfully setup the node, skip to [Manual
  setup](#manual-setup) to continue with the evaluation.

## Setting up the Cloudlab hardware

* Create an account on [Cloudlab](https://www.cloudlab.us/) and login.

### Configuring the experiment

#### Automated setup (Recommended)
* The easiest way to setup our experiment is to use "Repository based profile".

* Create an experiment profile by selecting
  `Experiments > Create Experiment profile`

* Select `Git Repo` and use this repository. The profile comes pre-installed
  with source code for evaluating DRAMHiT hash table.
```
https://github.com/svsm-vtpm/cloudlab-profiles
```
* Populate the name field and click `Create`

* If successful, instantiate the created profile by clicking `Instantiate`
  button on the left pane.

* **NOTE** You can select different branches on the git repository. Please select
  `svsm-vtpm-ae` branch.

* For a more descriptive explanation and its inner details, consult the
  cloudlab documentation on [repo based profiles](https://docs.cloudlab.us/creating-profiles.html#(part._repo-based-profiles)

* The `profile` git repository contains a bootstrapping script which
  automatically clones and builds the following repositories, upon a successful
  bootup of the node.

## Manual Setup

* Use the helper script `prepare.sh` to build all the necessary components. At a
high-level, the `prepare.sh` script does the following:
 - installs prerequisites
 - builds all the software
    - Linux host, guest, ovmf, qemu, svsm.bin
 - generates an ssh key
 - downloads an Ubuntu cloud-image and prepares user-data

```bash
./prepare.sh init
./prepare.sh install
```

* Now reboot the host machine to boot with the SEV-SNP enabled kernel. Make
  sure you pick the appropriate kernel from the GRUB menu or change the
defaults in `/etc/default/grub'

## Evaluation

* To make the artifact evaluation process easier, we have prepared a cloudlab
  node with the appropriate BIOS options and the host kernel that enables
  SEV-SNP.

## Launch guest

* To play around with the guest image and interact with the SVSM-vTPM, we need
  to launch the guest. `prepare.sh` script installs the guest kernel
  automatically.

```bash
./prepare.sh prep_guest
sudo ./launch-qemu.sh -hda ../../images/jammy-server-cloudimg-amd64.img -mem 5G -console serial -novirtio -smp 1 -ssh-forward -sev-snp -svsmcrb -svsm ../svsm.bin
```

* Login to the guest via ssh. `prepare.sh` should append a guest configuration
  to the ssh config file `~/.ssh/config`.
```bash
ssh guest
```

* Inside the guest, now you can access the vTPM
```bash
ls /dev/tpm*
sudo tpm2_pcrread
```

## TPM Benchmarks

* The script automatically invokes the appropriate guest image (Qemu based vTPM
  or SVSM based vTPM) and runs the TPM benchmark automatically and collects the
  log inside the `linux` directory which is shared with the guest.
  - Run the TPM benchmarking on SVSM-vTPM configuration . This communicates
    with the SVSM-vTPM running inside the SVSM.
  ```bash
  ./prepare.sh run_svtpm
  ```

  - Run the TPM benchmarking on a regular Qemu-vTPM (based on `swtpm`)
  ```bash
  ./prepare.sh run_qvtpm
  ```
