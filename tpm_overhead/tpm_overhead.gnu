reset
set term postscript enhanced color eps 20 solid
set output "tpm_overhead.eps"

set ylabel "Latency (microseconds)" font ",16"

set loadpath '.'
load 'xyborder.cfg'

set auto x
set xtics font ",11"
set ytics 25
set key above width 0.8 horizontal font ",17" maxrows 1
set style data histograms
set style histogram cluster gap 1
set style fill solid border -1
set boxwidth 0.9 absolute
set xtics border scale 1,0 nomirror autojustify norangelimit
set bmargin 2
set size 1,0.7

set datafile separator ","

plot 'tpm_overhead.csv' \
      u 2:xtic(1) ti col lc rgb crimson_red, \
      ''  u 3 ti col lc rgb dblue, \
      ''  u ($0-1.2):($2+0.1):(stringcolumn(2)) w labels font ",10" center offset 0, character 0.4 notitle, \
      ''  u ($0-0.85):($3+0.1):(stringcolumn(3)) w labels font ",10" center offset 0, character 0.4 notitle
