set terminal png
set output 'rss.png'
set style data linespoints
set datafile separator ","
set key autotitle columnhead
set xlabel 'Time increments (10s)'
set ylabel 'bytes'
plot 'psdata.csv' using 1:4 with lines

set output 'cpu.png'
set ylabel '% CPU'
plot 'psdata.csv' using 1:2 with lines
