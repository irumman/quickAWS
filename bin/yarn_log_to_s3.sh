#!/bin/bash

PROGDIR=`dirname $0`
pushd "$PROGDIR" >> /dev/null
PROGDIR=`echo $PWD`
PROGNAME=`basename $0 | cut -d'.' -f1`

#Directories
LOG_DIR="${PROGDIR}"/yarnlogstos3
TMP_DIR="${PROGDIR}"/tmp
mkdir -p "${TMP_DIR}"
mkdir -p "${LOG_DIR}"
cd "${LOG_DIR}"
#Files
TMP_LIST="${TMP_DIR}"/list_all_app

S3LOC=$1
ENVIRONMENT=$2
CARRIER=$3

function usage() {
 echo "Usage: ${PROGNAME} <S3LOCATION> <ENVIRONMENT> <CARRIER>"
 exit 1
}

function check_required_arguments() {
	for each in ${Required[@]}
	do
	  v=${each}
	  #echo $v=${!v}  # get value of actual variable
	  if [ -z "${!v}" ];
	  then
	    echo "Required paramter missing; These are - ${Required[@]}"
	    usage
	    exit 1
	  fi  
	done  
}

declare -a Required
Required=("S3LOC" "ENVIRONMENT" "CARRIER")
check_required_arguments


#### Main section ##############
vHOST_IP=`curl http://169.254.169.254/latest/meta-data/local-ipv4`
dt=`date +%Y%m%d_%H%M%S`
vFail=1
yarn application --list --appStates ALL > ${TMP_LIST} 
for each in `cat ${TMP_LIST} |  awk -F'\t' 'BEGIN{OFS=",";} {print $1,$6,$7,$2}'  | awk   '/,/{gsub(/ /, "", $0); print}' | awk 'NR>2 {print}'  `
do
  	vFail=0
	vAppId=`echo $each | cut -f1 -d','`
	vState=`echo $each | cut -f2 -d','`
	vFinalState=`echo $each | cut -f3 -d','`
  vJobName=`echo $each | cut -f4 -d',' | cut -d'-' -f1`
	vLogFile="${LOG_DIR}"/"${ENVIRONMENT}-${CARRIER}-${dt}-${vJobName}-${vFinalState}-${vAppId}.log"
	yarn logs --applicationId  ${vAppId} > "${vLogFile}" 2>&1
  aws s3 cp  "${vLogFile}" ${S3LOC}/${vHOST_IP}/ 
done

if [  ${vFail} -eq 1  ] ; 
then
	vLogFile="${LOG_DIR}"/"${ENVIRONMENT}-${CARRIER}-${dt}-ERROR.log"
	echo "No application found" > "${vLogFile}"
	aws s3 cp  "${vLogFile}" ${S3LOC}/${vHOST_IP}/ 
	exit 1
fi

