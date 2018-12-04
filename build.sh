#!/bin/bash

COMPILER=intel
C_VER=18.0.2 
COMPILE_FLAG=-xHASWELL
ARRAY_SIZE=10000000
N_TEST=10
N_THREAD_S=1
N_THREAD_E=1
N_LOOP=50
NO_BUILD=0
QUEUE=normal
R_TIME=02:00:00
HELP=0

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -c|--compiler)
    COMPILER="$2"
    shift # past argument
    shift # past value
    ;;
    -cv|--c_version)
    C_VER="$2"
    shift # past argument
    shift # past value
    ;;
    -f|--flag)
    COMPILE_FLAG="$2"
    shift # past argument
    shift # past value
    ;;
    -as|--array_size)
    ARRAY_SIZE="$2"
    shift # past argument
    shift # past value
    ;;
    -nt|--ntimes)
    N_TEST="$2"
    shift # past argument
    shift # past value
    ;;
    -tr|--nthreads)
    N_THREAD_S="$2"
    N_THREAD_E="$2"
    shift # past argument
    shift # past value
    ;;
    -trs|--nthreads_strat)
    N_THREAD_S="$2"
    shift # past argument
    shift # past value
    ;;
    -tre|--nthreads_end)
    N_THREAD_E="$2"
    shift # past argument
    shift # past value
    ;;
    -nl|--nloops)
    N_LOOP="$2"
    shift # past argument
    shift # past value
    ;;
    -t|--time)
    R_TIME="$2"
    shift # past argument
    shift # past value
    ;;
    -q|--queue)
    QUEUE="$2"
    shift # past argument
    shift # past value
    ;;
    -nb|--no-build)
    NO_BUILD=1
    shift # past argument
    ;;
    -h|--help)
    HELP=1
    shift # past argument
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [[ -n $1 ]]; then
    echo "Last line of file specified as non-opt/last argument:"
    tail -1 "$1"
fi


if [ "$HELP" -eq "1" ]; then
  echo "Usage: $0 [-options]"
  echo "  -h  | --help	    	  : This message "
  echo "  -c  | --compiler	  : compiler to build with (intel)"
  echo "  -cv | --c_version	  : version of the compiler (18.0.2)"
  echo "  -f  | --flag		  : architecture related flag (-xHASWELL)"
  echo "  -as | --array_size	  : STREAM's internal array size (10000000)"
  echo "  -nt | --ntimes	  : STREAM's internal ntimes parameter (10)"
  echo "  -tr | --nthreads	  : number of threads for the test (1)"
  echo "  -trs| --nthreads_start  : starting number of threads (1)"
  echo "  -tre| --nthreads_end    : ending number of threads (1)"
  echo "  -nl | --nloops	  : number of loops for the test (50)"
  echo "  -t  | --time		  : time requested for the run (03:00:00)"
  echo "  -q  | --queue		  : queue to submit the job (normal)"
  echo "  -nb | --no-build	  : skip the build steps"
  echo ""
  echo "Examples:"
  echo "  ./build.sh -c intel -cv 18.0.2 -f \"-xCORE-AVX2 -axCORE-AVX512,MIC-AVX512\""
  echo "  ./build.sh -c intel -cv 18.0.2 -f \"-xCORE-AVX2 -axCORE-AVX512,MIC-AVX512\" -nb -tr 4 -nl 50 -t 03:00:00 -q normal"
  exit
fi
  
module purge
module reset
module load $COMPILER/$C_VER

TEMP_V=${COMPILE_FLAG// /_}
COMPILE_F=${TEMP_V//,/}

mkdir test_${COMPILER}-${C_VER}_${COMPILE_F}_${ARRAY_SIZE}_${N_TEST}

if [ "$NO_BUILD" -eq "0" ]; then
  cd stream-5.10 
  icc -O3 -lrt ${COMPILE_FLAG} -qopenmp -DSTREAM_ARRAY_SIZE=${ARRAY_SIZE} -DNTIMES=${N_TEST} stream.c -o stream_${COMPILER}-${C_VER}_${COMPILE_F}_${ARRAY_SIZE}_${N_TEST}
  mv stream_${COMPILER}-${C_VER}_${COMPILE_F}_${ARRAY_SIZE}_${N_TEST} ../test_${COMPILER}-${C_VER}_${COMPILE_F}_${ARRAY_SIZE}_${N_TEST}
  cd ..
fi

if [ -f test_${COMPILER}-${C_VER}_${COMPILE_F}_${ARRAY_SIZE}_${N_TEST}/stream_${COMPILER}-${C_VER}_${COMPILE_F}_${ARRAY_SIZE}_${N_TEST} ]; then
  cd test_${COMPILER}-${C_VER}_${COMPILE_F}_${ARRAY_SIZE}_${N_TEST}
  cat > stream_job_${N_THREAD_S}_${N_THREAD_E}_${N_LOOP}.sh << EOF
#!/bin/bash
#SBATCH -J stream_${N_THREAD_S}_${N_THREAD_E}
#SBATCH -o stream_${N_THREAD_S}_${N_THREAD_E}.%j 
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -p ${QUEUE}
#SBATCH -t ${R_TIME}
#SBATCH -A A-ccsc

export streamexe=./stream_${COMPILER}-${C_VER}_${COMPILE_F}_${ARRAY_SIZE}_${N_TEST}

module purge
module load $COMPILER/$C_VER

mkdir \${SLURM_JOBID}

date

for j in {${N_THREAD_S}..${N_THREAD_E}}
do
  for i in {1..${N_LOOP}}; do OMP_NUM_THREADS=\${j} \${streamexe} ; done > \${SLURM_JOBID}/raw_output_\${j}.txt
  
  cd \${SLURM_JOBID}
  
  echo \${j}
  
  awk '(NR%33==27){sum+=\$2;n+=1} END { if (n > 0) print "Copy: " sum/n }' raw_output_\${j}.txt
  awk '(NR%33==28){sum+=\$2;n+=1} END { if (n > 0) print "Scale: " sum/n }' raw_output_\${j}.txt
  awk '(NR%33==29){sum+=\$2;n+=1} END { if (n > 0) print "Add: " sum/n }' raw_output_\${j}.txt
  awk '(NR%33==30){sum+=\$2;n+=1} END { if (n > 0) print "Triad: " sum/n }' raw_output_\${j}.txt

done
EOF
  sbatch stream_job_${N_THREAD_S}_${N_THREAD_E}_${N_LOOP}.sh
else
  echo "warning: cannot find the specified build!"
fi
