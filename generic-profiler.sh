#!/bin/bash
#SBATCH -p TempProject3,TempProject1
#SBATCH -c 8
#SBATCH --mem 100G
#SBATCH -J profileJob
#SBATCH -o profiler.%j.%n.out
#SBATCH --mail-type BEGIN,END
. lmod-6.1
ml gcc zlib

# Inspired on: https://github.com/glennklockwood/bioinformatics-profile
#
#  Environment variables for configuring behavior:
#     
set -u


NO_PROFILE=0
NO_FILEHANDLES=0
PROFILE_STACK=0

BINARYBASE="" # PATH TO YOUR BINARY

my_pid=""
#
#    INPUT - path to file containing input queries
#    SCRATCH_DIR - working directory when application is run; also where
#      database/input queries will be copied if NO_STAGE is not set
#    SCRATCH_DEV - the block device underneath SCRATCH_DEV for iostat to query;
#      leave empty ("") to skip iostat
#

SCRATCH_DEV="" # If running on a local disk, pass the disk "dev" info
SCRATCH_DIR="/scratch/$USER/profiling/myJob/${SLURM_CPUS_PER_TASK}cpus" # This is preferably a full path
INPUT="ALL_R2.fastq" # This are preferably full paths

PROFILE_OUTPUT_DIR="/usr/users/TGAC_ga007/yanesl/profiling/myJob/${SLURM_CPUS_PER_TASK}cpus" # Where to store the samples?

### Seconds before dropping profile output
### periodic gstack dumping
PROFILE_INTERVAL=10

#
#  Location of various binaries
#
TIME="/usr/bin/time -v"
BINARY="${BINARYBASE}/myProgram" # The binary file
APP_NAME="$(basename $BINARY)"

OUTPUT_FILE="${APP_NAME}.out"
OUTPUT_DIR="/tgac/workarea/users/$USER/profiling/myJob/${SLURM_CPUS_PER_TASK}cpus"

THREADS="${SLURM_CPUS_PER_TASK}"
APWRAP="" # if a launcher is required (MPI)

clean_profile_dir() {
    #
    #  Ensure we don't carry over the results from a previous profiling run
    #
    PROFILE_OUTPUT_DIR=$1
    if [ -d ${PROFILE_OUTPUT_DIR} ]; then
        echo "$(date) - Need to kill ${PROFILE_OUTPUT_DIR}"
        if [ -d ${PROFILE_OUTPUT_DIR}.old ]; then
            rm -rf ${PROFILE_OUTPUT_DIR}.old
        fi
        mv -v ${PROFILE_OUTPUT_DIR} ${PROFILE_OUTPUT_DIR}.old
    fi
    mkdir -p ${PROFILE_OUTPUT_DIR}
}

#
#  Functions to generate profiling data
#
drop_begin() {
    if [ -z "$1" ]; then
        echo "PROF_BEGIN $1"
    else
        echo "PROF_BEGIN $(date +%s)"
    fi
}
startmon() { 
    echo "$(date) - Starting IO profile..."
    if [ ! -z "${SCRATCH_DEV}" ]; then
        drop_begin  > ${PROFILE_OUTPUT_DIR}/prof_iostat.txt
        iostat -dkt ${PROFILE_INTERVAL} ${SCRATCH_DEV} >> ${PROFILE_OUTPUT_DIR}/prof_iostat.txt &
    fi

    for profile_output in prof_df.txt prof_ps.txt prof_filehandles.txt prof_vmstat.txt prof_meminfo.txt prof_gstack.txt prof_lcache.txt 
    do
        if [ -e ${PROFILE_OUTPUT_DIR}/${profile_output} ]; then
            rm ${PROFILE_OUTPUT_DIR}/${profile_output}
        fi
    done

    while [ 1 ]
    do 
        # One timestamp for each record to ensure all profile outputs' columns
        # can be pasted together and remain in-phase
        timestamp=$(date +%s)

        # Check if the process has started by looking at the .pid file
        if [ -e ${PROFILE_OUTPUT_DIR}/myJob.pid ] ; then
            my_pid=$(cat ${PROFILE_OUTPUT_DIR}/myJob.pid)
        fi
        if [ ! -z "${my_pid}" ]; then

            # save record of ssd capacity
            drop_begin $timestamp >> ${PROFILE_OUTPUT_DIR}/prof_df.txt
            df -k >> ${PROFILE_OUTPUT_DIR}/prof_df.txt

            # save record of running processes
            drop_begin $timestamp >> ${PROFILE_OUTPUT_DIR}/prof_ps.txt
            ps -p $my_pid -o pid,ppid,lwp,nlwp,etime,pcpu,pmem,rss,vsz,maj_flt,min_flt,state,cmd -www >> ${PROFILE_OUTPUT_DIR}/prof_ps.txt

            # save record of open file handles
            if [ -z "${NO_FILEHANDLES}" ]; then
                drop_begin $timestamp >> ${PROFILE_OUTPUT_DIR}/prof_filehandles.txt
                cat /proc/sys/fs/file-nr >> ${PROFILE_OUTPUT_DIR}/prof_filehandles.txt
            fi

            # save record of virtual memory state
            drop_begin $timestamp >> ${PROFILE_OUTPUT_DIR}/prof_vmstat.txt
            cat /proc/vmstat >> ${PROFILE_OUTPUT_DIR}/prof_vmstat.txt

            # save record of memory
            drop_begin $timestamp >> ${PROFILE_OUTPUT_DIR}/prof_meminfo.txt
            cat /proc/meminfo >> ${PROFILE_OUTPUT_DIR}/prof_meminfo.txt
 
            # only probe the process stack if we are doing coarse-grained profiling
            if [ ${PROFILE_INTERVAL} -ge 5 ] && [ $PROFILE_STACK -ne 0 ]; then
                if [ ! -z "${my_pid}" ]; then
                    drop_begin ${timestamp} >> ${PROFILE_OUTPUT_DIR}/prof_gstack.txt
                    gstack ${my_pid} 2>&1 >> ${PROFILE_OUTPUT_DIR}/prof_gstack.txt
                fi
            fi
        fi
        sleep ${PROFILE_INTERVAL}s

    done
}


################################################################################
### End of function definitions ################################################
################################################################################

################################################################################
### Begin profiled workflow ####################################################
################################################################################


clean_profile_dir ${PROFILE_OUTPUT_DIR}

test -d "${SCRATCH_DIR}" && rm -r "${SCRATCH_DIR}"
mkdir -p ${SCRATCH_DIR} || exit 1

#
#  Start profiling
#
if [ $NO_PROFILE = 0 ]; then
    startmon &
    monpid=$!
    sleep 5
fi

#
#  Launch application
#
echo "$(date) - Running command (check stderr for invocation)"

set -x
if [ "$test_type" = "basic" ]
then

$APWRAP $BINARY \
    -p "profile" \
    -t ${THREADS} \
    --dump_all 1 \
    -K 200 \
    $log_level \
    -r ${INPUT} \
    -o ${SCRATCH_DIR} > ${SCRATCH_DIR}/${OUTPUT_FILE} 2> ${SCRATCH_DIR}/${OUTPUT_FILE%out}err &

elif [ "$test_type" = "exp" ]
then

$APWRAP $BINARY \
    -p "profile" \
    -t ${THREADS} \
    --dump_all 1 \
    -K 200 \
    $log_level \
    --experimental 1 \
    -r ${INPUT} \
    -o ${SCRATCH_DIR} > ${SCRATCH_DIR}/${OUTPUT_FILE} 2> ${SCRATCH_DIR}/${OUTPUT_FILE%out}err &

elif [ "$test_type" = "dv" ]
then

$APWRAP $BINARY \
    -p "profile" \
    -t ${THREADS} \
    --dump_all 1 \
    -K 200 \
    $log_level \
    --dv_like 1 \
    -r ${INPUT} \
    -o ${SCRATCH_DIR} > ${SCRATCH_DIR}/${OUTPUT_FILE} 2> ${SCRATCH_DIR}/${OUTPUT_FILE%out}err &

fi
wrap_pid=$!
echo $wrap_pid > ${PROFILE_OUTPUT_DIR}/myJob.pid
if wait $wrap_pid; then
    echo "The application SUCCEEDED"
else
    echo "The application FAILED"
fi

echo "$(date) - Finished running command"

if [ ${NO_PROFILE} = 0 ]; then
    ### Let one last ps/df fire before shutting everything down
    sleep 30
    kill ${monpid}
fi
unload_gnuplot=0
# Plot the CPU/MEM resources usage
if ! type "gnuplot" &> /dev/null; then
    set +x
    ml gnuplot
    set -x
    unload_gnuplot=1
fi
digest_ps ${PROFILE_OUTPUT_DIR}/prof_ps.txt > ${PROFILE_OUTPUT_DIR}/psdata.csv
cd ${PROFILE_OUTPUT_DIR}
gnuplot ~/scripts/plot_ps.gp # This is the plotting script
rm psdata.csv
cd -

if [ $unload_gnuplot -eq 1 ]; then
    set +x
    ml -gnuplot
    set -x
fi

#
#  Post-run stage-off and cleanup
#
clean_profile_dir ${OUTPUT_DIR}
echo "$(date) - Begin moving output data off of local disk"
mv -v ${SCRATCH_DIR}/${OUTPUT_FILE%out}err ${OUTPUT_DIR}/
mv -v ${SCRATCH_DIR}/* ${OUTPUT_DIR}/
echo "$(date) - Finished moving output data off of local disk"

echo "$(date) - Removing ${SCRATCH_DIR}"
rm -rf ${SCRATCH_DIR}
echo "$(date) - Done cleaning up ${SCRATCH_DIR}"

