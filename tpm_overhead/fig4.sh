#!/usr/bin/env bash

SCRIPT_DIR="$(readlink -f $(dirname $0))"
BASENAME="$(basename $0)"
PS2PDF_FLAGS="-dEPSCrop -dPDFSETTINGS=/printer -dColorConversionStrategy=/RGB -dProcessColorModel=/DeviceRGB -dEmbedAllFonts=true -dSubsetFonts=true -dMaxSubsetPct=100"

get_values() {
  LOG_PREFIX="../linux"
  if [ $1 == "svsm" ]; then
    LOG=${LOG_PREFIX}/"svsm-vtpm.log"
  elif [ $1 == "qemu" ]; then
    LOG=${LOG_PREFIX}/"qemu-vtpm.log"
  fi

  if [ -f ${LOG} ]; then
    grep "latency:" ${LOG} | awk '{print $1}' > header.csv
    rm -f $1.csv
    for v in $(grep "latency:" ${LOG} | awk '{print $(NF-1)}'); do
      echo "scale=1; $v/1000" | bc >> $1.csv
    done
  fi
}

get_csv() {
  get_values svsm
  get_values qemu

  if [[ -f "svsm.csv" && -f "qemu.csv" ]]; then
    echo "op, SVSM-vTPM, Qemu vTPM" > tpm_overhead.csv
    paste -d',' header.csv svsm.csv qemu.csv >> tpm_overhead.csv
  fi
}

plot_figure() {
  CSV=$1.csv
  EPS=$1.eps
  GNU=$1.gnu
  PDF=$1.pdf
  if [[ -f ${CSV} ]]; then
    echo "Plotting with gnuplot..."
    gnuplot ${GNU}
    if [[ $? == 0 && -f ${EPS} ]]; then
      echo "Converting EPS -> PDF"
      ps2pdf14 ${PS2PDF_FLAGS} ${EPS} ${PDF}
    fi
  fi
}

get_csv
plot_figure tpm_overhead
