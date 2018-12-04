#!/bin/bash

COMPILER=intel
C_VER=18.0.2 
COMPILE_FLAG=-xHASWELL
N_THREAD=1
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
    -tr|--nthreads)
    N_THREAD="$2"
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
  echo "  -tr | --nthreads	  : number of threads for the test (1)"
  echo "  -t  | --time		  : time requested for the run (03:00:00)"
  echo "  -q  | --queue		  : queue to submit the job (normal)"
  echo "  -nb | --no-build	  : skip the build steps"
  echo ""
  echo "Examples:"
  echo "  ./build.sh -c intel -cv 18.0.2 -f \"-xCORE-AVX2 -axCORE-AVX512,MIC-AVX512\""
  echo "  ./build.sh -c intel -cv 18.0.2 -f \"-xCORE-AVX2 -axCORE-AVX512,MIC-AVX512\" -nb -tr 4 -t 03:00:00 -q normal"
  exit
fi
  
module purge
module reset
module load $COMPILER/$C_VER

TEMP_V=${COMPILE_FLAG// /_}
COMPILE_F=${TEMP_V//,/}

mkdir test_${COMPILER}-${C_VER}_${COMPILE_F}

if [ "$NO_BUILD" -eq "0" ]; then
  cd stream-5.10 
  icc -O3 -lrt ${COMPILE_FLAG} -qopenmp stream.c -o stream_${COMPILER}-${C_VER}_${COMPILE_F}
  mv stream_${COMPILER}-${C_VER}_${COMPILE_F} ../test_${COMPILER}-${C_VER}_${COMPILE_F}
  cd ..
fi

if [ -f test_${COMPILER}-${C_VER}_${COMPILE_F}/stream_${COMPILER}-${C_VER}_${COMPILE_F} ]; then
  cd test_${COMPILER}-${C_VER}_${COMPILE_F}
  cat > stream_job_${N_THREAD}.sh << EOF
#!/bin/bash
#SBATCH -J stream_${N_THREAD}
#SBATCH -o stream_${N_THREAD}.%j 
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -p ${QUEUE}
#SBATCH -t ${R_TIME}
#SBATCH -A A-ccsc

export streamexe=./stream_${COMPILER}-${C_VER}_${COMPILE_F}
export OMP_NUM_THREADS=${N_THREAD}

module purge
module load $COMPILER/$C_VER

date

for i in {1..50}; do OMP_NUM_THREADS=${N_THREAD} \${streamexe} | head -n 30 | tail -n 4 ; done | awk '{ sum += \$2 } END { if (NR > 0) print sum/NR }'

EOF
  sbatch stream_job_${N_THREAD}.sh
else
  echo "warning: cannot find the specified build!"
fi
