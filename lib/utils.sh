#!/bin/bash

declare -a ALLOWED_INSTANCE_TYPE
ALLOWED_INSTANCE_TYPE=("r3.xlarge" "r3.2xlarge" "m1.medium" "m3.xlarge" "m3.2xlarge")
declare -a ALLOWED_CARRIER
ALLOWED_CARRIER=("rak" "jpn" "att" "vzw" "ana" "spr" "aff" "vzwi")
declare -a ALLOWED_ACTION
ALLOWED_ACTION=("uploadCode" "createCluster" "createClusterOnly" "stopCluster" "getClusterInfo" "createPipeline" "downloadYarnLogs" "createParameterFileOnly")
declare -a ALLOWED_REGION
ALLOWED_REGION=("us-east-1")



function fn_set_profile() {
	ENV=$1
	ROLES=$2
	SKIP_PROFILE_SET=$3
	SSO_JAR_FILE_LOCATION=$4
	if [ "${SKIP_PROFILE_SET}" -eq 0 ];
	then	
		if [ -f ~/.aws/credentials ];
		then
			LAST_MODIFIED_SECOND=$(expr `date +%s` - `stat -f%m ~/.aws/credentials`)
		else
			LAST_MODIFIED_SECOND=40000	
		fi	
		if [ ${LAST_MODIFIED_SECOND} -gt 3300 ];
		then
			if [ ! -f "${SSO_JAR_FILE_LOCATION}" ];
			then
				echo "FATAL! SSO authentication jar not found at ${SSO_JAR_FILE_LOCATION}"
				exit 1
			fi	
			java -jar ${SSO_JAR_FILE_LOCATION}
		else
			echo "Using  ~/.aws/credentials last generated ${LAST_MODIFIED_SECOND} second ago"	
		fi	
		if [[ ${ENV} == 'qa' ]];
		then	
			export AWS_DEFAULT_PROFILE="asurion-sqa.${ROLES}"
		elif [[ ${ENV} == 'dev' ]];
		then	
			export AWS_DEFAULT_PROFILE="asurion-dev.${ROLES}"
		elif [[ ${ENV} == 'prod' ]];
		then
			export AWS_DEFAULT_PROFILE="asurion-prod.${ROLES}"
		else
			echo "ERROR:! Invalid environment value; allowed (dev/qa)"
			exit 1	
		fi	
	fi	
}

function check_required_arguments() {
	Required=$1
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

function check_allowed_values() {
	declare -a ALLOWED
	ALLOWED=( "$1" )
	ARG_NAME="$2"
	vMatched=0
	for each in ${ALLOWED[@]}
	do
	  if [[ ${each}  == "${!ARG_NAME}" ]];
	  then
	  	vMatched=1
	  fi
	done
	if [ ${vMatched} -eq 0 ];
	then  	
		echo "Invalid ${ARG_NAME}; Allowed values - ${ALLOWED[@]}"
		usage
		exit 1
	fi	
}

function validate_integer() {
	ARG_NAME=$1
    if [[ ${!ARG_NAME} =~ ^[-0-9]+$ ]];
    then	
    	echo "ok"  >> /dev/null
    else
    	echo "Invalid value for ${ARG_NAME}; Allowed only integer"	
    	usage
    	exit 1
	fi

}

