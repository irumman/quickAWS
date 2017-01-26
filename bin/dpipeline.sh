#!/usr/bin/env bash

#Author : Ahmad.Iftekhar
#Version: 2.1
#Added support for respective properties file for each job

PROGDIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
#PROGDIR="${PROGDIR}"
#echo ${PROGDIR}
PROGNAME=`basename $0 | cut -d'.' -f1`

if [ ! -f "$PROGDIR"/../lib/utils.sh ];
then
  echo "FATAL: library file not found"
  exit 0
fi  
. $PROGDIR/../lib/utils.sh

BID_PERCENTAGE="0.8"
TMP_PIPELINE_VALUES_JSON="/tmp/quickaws-pipeline-tmp.json"
if [ -f ${TMP_PIPELINE_VALUES_JSON} ];
then
	rm ${TMP_PIPELINE_VALUES_JSON}
fi		
ENVIRONMENT=""
usage () {
 echo  "Usage: ${PROGNAME} <options>\nOptions:\n -A ACTION(uploadCode/createCluster/stopCluster/getClusterInfo/createPipeline/downloadYarnLogs/createParameterFileOnly)\n -e ENVIRONMENT\n -c CARRIER\n -n PIPELINE_NAME\n -i PIPELINE_ID\n -j JOBS(data,battery..)\n -T INSTANCE_TYPE\n -N NODE_COUNT_CORE\n -W NODE_COUNT_TASK\n -M TERMINATE_AFTER_MINUTE (Default: 30)\n -F REPOSITORY_ZIP\n -r ROLES\n -x NUMBER_OF_EXECUTOR\n -m EXECUTOR_MEMORY\n -P PROPERTIES_FILE\n -k SKIP_PROFILE_SET\n -S SUBNET\n -B BUILD_NUMBER\n -C CONFIG_BUILD_NUMBER\n -J SSO_JAR_FILE_LOCATION\n -O USE_SPOT_INSTANCE(0/1)\n -R REGION\n -X EXECUTOR_CORES(Default:1)\n -D DRIVER_MEMORY(Default:10G)" 
 exit 1
}

progess()
{
    #Function collected from online
    checkingFor=$1
    local pid=$!
    local delay=0.75
    local spinstr='|/-\'
    vDone=0
    counter=0
    while [ ${vDone} -eq 0 ]; do
    	let counter=${counter}+1
    	if [ ${counter} -gt 240 ]; #4 min
    	then
    		echo "Something went wrong. Pipeline may be stuck."
    		echo "Please check from console or re-create pipeline"
    		exit 1
    	fi		
		get_pipeline_id >> /dev/null
		fn_set_profile ${ENVIRONMENT} ${ROLES} ${SKIP_PROFILE_SET} >> /dev/null
		if [[ ${checkingFor} == "createCluster" ]];
		then	
			clusterID=`aws emr list-clusters --query 'Clusters[*].[Name,Id,Status.State,Status.Timeline.CreationDateTime]'  --active --output text  | grep ${PIPELINE_ID} | sort -k4 -n | tail -1 | awk '{print $2}'`
			if [ ! -z ${clusterID} ];
			then
				vClusterInfo=$(aws emr describe-cluster --cluster-id $clusterID  --query '{A:Cluster.Name,B:Cluster.MasterPublicDnsName,C:Cluster.Status.State}' --output text)
				vName=`echo ${vClusterInfo} | awk '{ print $1}'`
				vIP=`echo ${vClusterInfo} | awk '{ print $2}'`
				vState=`echo ${vClusterInfo} | awk '{ print $3}'`
				if [ ${#vName} ]; # [[ ${vIP} != "None" ]] || [[ ${vState} == "TERMINATED"* ]];
				then	
					echo " "
					echo  "ClusterId=${clusterID}"
					aws emr describe-cluster --cluster-id $clusterID  --query '{IP:Cluster.MasterPublicDnsName,KEY:Cluster.Ec2InstanceAttributes.Ec2KeyName,STATE:Cluster.Status.State,NAME:Cluster.Name}' --output table
					vDone=1
				fi	
			fi
		elif [[ ${checkingFor} == "stopCluster" ]];
		then	
			STATE=""
			STATE=`aws datapipeline describe-pipelines --pipeline-ids ${PIPELINE_ID} --output text | grep @pipelineState | awk '{ print $3}'`
			if [[ ${STATE} == "INACTIVE" ]];
			then	
				echo "Pipeline is INACTIVE"
				vDone=1
			fi	
		fi	
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}


upload_file() {

	echo "Uploading files ..."
	#LOCAL_FILE="${PROGDIR}"/../build/distributions/${PROJECT_NAME}-${PROJECT_VERSION}.zip
	LOCAL_FILE="${REPOSITORY_ZIP}"
	if [ ! -f "${LOCAL_FILE}" ];
	then
		echo "ERROR! Repository zip file not found at ${LOCAL_FILE}"
		exit 1
	fi	
	echo "aws s3 cp ${LOCAL_FILE} s3://${s3loc}/"
	aws s3 cp "${LOCAL_FILE}" s3://${s3loc}/
	if [ $? -gt 0 ];
	then
		echo "ERROR: File upload failed "
	fi		
	echo "Done"
}

create_parameter_file() {
	JOBS=`echo ${1} | sed s/\,/" "/g` 
	vStr=""
	HOLD_MIN=0
	vNL=$'\n\t\t'
	vFileName=`basename ${REPOSITORY_ZIP}`	
	vFileName=${vFileName%.*}
	if [ ! -z ${BUILD_NUMBER} ];
	then
		vFileName=${vFileName}"-\${BUILD_NUMBER}"
	fi	


	vStr="\"s3://us-east-1.elasticmapreduce/libs/script-runner/script-runner.jar,s3://my-#{myEnvironment}-files/datapipeline_emr/bootstrap-download.sh,s3://${s3loc}/`basename ${REPOSITORY_ZIP}`,/home/hadoop/\""
	vStr="${vStr},${vNL}\"s3://us-east-1.elasticmapreduce/libs/script-runner/script-runner.jar,s3://my-#{myEnvironment}-files/datapipeline_emr/bootstrap-yum-libraries.sh\""
	if [ ! -z ${CONFIG_BUILD_NUMBER} ];
	then
		vStr="${vStr},${vNL}\"s3://us-east-1.elasticmapreduce/libs/script-runner/script-runner.jar,s3://my-#{myEnvironment}-files/datapipeline_emr/bootstrap-download.sh,s3://${s3loc_config_files}/${CONFIG_BUILD_NUMBER}/conf-bdp-sparkjobs.zip,/home/hadoop/\""
		vConigFileLocation="/home/hadoop/conf-bdp-sparkjobs/${PROPERTIES_FILE}"
	else	
		vConigFileLocation="/home/hadoop/${vFileName}/${PROPERTIES_FILE}"
	fi	
	if [[ "${JOBS[@]}" =~ "seguploadtoes" ]]; then
		vStr="${vStr},${vNL}\"s3://us-east-1.elasticmapreduce/libs/script-runner/script-runner.jar,/home/hadoop/${vFileName}/elasticsearch_maintenance.sh,-A,createDomain,-P,${vConigFileLocation}\""
	fi

	vStr="${vStr},${vNL}\"s3://us-east-1.elasticmapreduce/libs/script-runner/script-runner.jar,s3://my-#{myEnvironment}-files/datapipeline_emr/wait_for_task_node.sh\""	      
	vStrJupyter=""
	for each in ${JOBS[@]}; 
	do 
		if [[ ${each} == "spark-shell" ]];
		then
			let HOLD_MIN=${TERMINATE_MIN}*60
		elif [[ ${each} == "jupyter" ]];
		then
			vStrJupyter="\"s3://us-east-1.elasticmapreduce/libs/script-runner/script-runner.jar,s3://my-#{myEnvironment}-files/datapipeline_emr/install_jupyter.sh\""	
		else	
			##Adding support for properties file respective for each job
			vJobName=`echo ${each} | awk -F':' '{print $1}'`
			vPropFile=`echo ${each} | awk -F':' '{print $2}'`
			if [ -z ${vPropFile} ];
			then
				vPropFile="${vConigFileLocation}"
			else
				if [ ! -z ${CONFIG_BUILD_NUMBER} ];
				then
					vPropFile="/home/hadoop/conf-bdp-sparkjobs/${vPropFile}"
				else
					vPropFile="/home/hadoop/${vFileName}/${vPropFile}"
				fi	
						
			fi	
	    	vStr="${vStr},${vNL}\"s3://us-east-1.elasticmapreduce/libs/script-runner/script-runner.jar,/home/hadoop/${vFileName}/insights.sh,${vJobName},${vPropFile},${NUM_OF_EXECUTOR},${EXECUTOR_MEMORY},${EXECUTOR_CORES},${DRIVER_MEMORY}\""

		fi
	done
	if [ ! -z "${vStr}" ];
	then
	    vStr="${vStr},${vNL}\"s3://us-east-1.elasticmapreduce/libs/script-runner/script-runner.jar,s3://my-#{myEnvironment}-files/datapipeline_emr/yarn_log_to_s3.sh,s3://my-#{myEnvironment}-logfiles/yarn-logs/#{@pipelineId},#{myEnvironment},#{myCarrier}\""	
	fi	
	if [ ${HOLD_MIN} -gt 0 ];
	then	
	 	vStr="${vStr},${vNL}\"s3://us-east-1.elasticmapreduce/libs/script-runner/script-runner.jar,/bin/sleep,${HOLD_MIN}\""
	fi
	if  [ ! -z "${vStrJupyter}" ];
	then
		vStr="${vStrJupyter},${vNL}${vStr}"	
	fi
	vSubnet=${SUBNET} 	

	##Using Spot instance
	if [ ${USE_SPOT_INSTANCE} -eq 1 ];
	then
		fn_spot_instance_az #Set AZ and BID_PRICE
		if [ ${BID_FOUND} -eq 0 ];
		then
			echo "WARNING! Bid failed. Please try after 10 minutes !!!!!!!!!!!!!!!!"
			exit 1
			USE_SPOT_INSTANCE=0
		fi			
	fi	
	if [ ${USE_SPOT_INSTANCE} -eq 1 ];
	then	
		vStrSpot="\"myClusterMaximumRetries\":\"3\",\"myTaskInstanceBidPrice\":\"${vBidPrice}\",\"myUseOnDemandOnLastAttempt\":\"false\","
		vSubnet=`fn_get_spot_az_subnet_id`
	else
		#Reading ondemand price again as a quick fix ot avoid waitng indefinitely for cluster	
		vCurrPrice=`fn_get_ondemand_price`
		vCurrPrice=`python -c "v=${vCurrPrice}; print ('%.3f' % v)"`
		vStrSpot="\"myClusterMaximumRetries\":\"3\",\"myTaskInstanceBidPrice\":\"${vCurrPrice}\",\"myUseOnDemandOnLastAttempt\":\"true\","
	fi	
	##end of spot instance
	cat <<EOT >> "${TMP_PIPELINE_VALUES_JSON}"
	{
	"values": {
	    "myTaskInstanceType": "${INSTANCE_TYPE}",
	    "myTaskInstanceCount": "${NODE_COUNT_TASK}",
	    "myEMRReleaseLabel": "emr-4.5.0",
	    "myMasterInstanceType": "${INSTANCE_TYPE}",
	    "mySubnetId": "${vSubnet}",
	    "myEmrStep": [
	      ${vStr}
	    ],
	    ${vStrSpot}
	    "myEC2KeyPair": "MY-`echo ${ENVIRONMENT} | awk '{print toupper($0)}'`-KEY",
	    "myCoreInstanceCount": "${NODE_COUNT_CORE}",
	    "myCoreInstanceType": "${INSTANCE_TYPE}",
	    "myEMRName" : "MY-#{myEnvironment}-#{myCarrier}",
	    "myTerminateAfterMinute" : "${TERMINATE_MIN}",
	    "myCarrier": "${CARRIER}",
	    "myEnvironment": "`echo ${ENVIRONMENT} | awk '{print tolower($0)}'`",
	    "myBuildNumber" : "${BUILD_NUMBER}",
	    "myConfigBuildNumber" : "${CONFIG_BUILD_NUMBER}"
	  }
	}

EOT

}


get_pipeline_id() {
	if [ -z ${PIPELINE_NAME} ] && [ -z ${PIPELINE_ID} ] ;
	then	
		PIPELINE_ID=""
		PIPELINE_NAME="MY-`echo ${ENVIRONMENT} | awk '{print toupper($0)}'`-DP-`whoami | awk '{print toupper($0)}'`"
	fi	

	if [ -z "${PIPELINE_ID}" ];
	then	
		
		PIPELINE_ID=$(aws datapipeline list-pipelines --query 'pipelineIdList[?name==`'${PIPELINE_NAME}'`]' --output text | awk '{print $1}')
	fi
	echo "PipelineId = ${PIPELINE_ID}"
	if [ -z "${PIPELINE_ID}" ];
	then
		echo "ERROR! No PIPELINE_ID found."
		exit 1
	fi	
} #get_pipeline_id

get_cluster_info() {

	get_pipeline_id
	clusterID=`aws emr list-clusters --query 'Clusters[*].[Name,Id,Status.State,Status.Timeline.CreationDateTime]'   --output text  | grep ${PIPELINE_ID} | sort -k4 -n | tail -1 | awk '{print $2}'`
	if [ -z ${clusterID} ];
	then
		echo "No cluster found"
		exit 1
	else		
		echo "Last ClusterId=${clusterID}"
		aws emr describe-cluster --cluster-id $clusterID  --query '{IP:Cluster.MasterPublicDnsName,KEY:Cluster.Ec2InstanceAttributes.Ec2KeyName,STATE:Cluster.Status.State,NAME:Cluster.Name}' --output table
	fi

} #get_cluster_info



create_cluster () {

	create_parameter_file $JOBS

	get_pipeline_id
	echo "Activating pipeline ${PIPELINE_ID}..."
	echo "aws datapipeline activate-pipeline --pipeline-id ${PIPELINE_ID} --parameter-values-uri file://${TMP_PIPELINE_VALUES_JSON}"	
	aws datapipeline activate-pipeline --pipeline-id ${PIPELINE_ID} --parameter-values-uri file://${TMP_PIPELINE_VALUES_JSON}
	
	if [ $? -eq 0 ];
	then
		progess "createCluster"			
		echo "Done; Check from console."
	else
		echo "ERROR: Failed to activate pipeline"
		exit 1
	fi		
} # create_cluster

stop_pipeline() {
	get_pipeline_id
	echo "Deactivating pipeline..."
	echo "aws datapipeline deactivate-pipeline --pipeline-id ${PIPELINE_ID}" 
	aws datapipeline deactivate-pipeline --pipeline-id ${PIPELINE_ID} 
	if [ $? -eq 0 ];
	then		
		progess "stopCluster"	
		echo "Done; Check from console."
	else
		echo "ERROR: Failed to deactivate pipeline"
		exit 1
	fi		
} #stop_pipeline

create_pipeline() {
	if [  -z ${PIPELINE_NAME} ];
	then
			PIPELINE_NAME="MY-`echo ${ENVIRONMENT} | awk '{print toupper($0)}'`-DP-`whoami | awk '{print toupper($0)}'`"
	fi		

	vPID=$(aws datapipeline list-pipelines --query 'pipelineIdList[?name==`'${PIPELINE_NAME}'`]' --output text | awk '{print $1}')	
	echo "Deleting existing pipeline with name ${PIPELINE_NAME}"
	for each in `echo "${vPID}" | sed 's/ /\n/g'`
	do
		echo "aws datapipeline delete-pipeline --pipeline-id ${each}"
		aws datapipeline delete-pipeline --pipeline-id ${each}
	done
	echo "Creating pipeline with name: ${PIPELINE_NAME} ..."
	vPID=`aws datapipeline create-pipeline --name ${PIPELINE_NAME} --unique-id ${PIPELINE_NAME} --tags key=Name,value=${PIPELINE_NAME} key=PLATFORM,value=BIGDATA key=REGION,value=NORTHAMERICA`
	if [ ! -z "${vPID}" ];
	then	
		vPID=`echo ${vPID}  | awk -F: '{print $2}' | tr -cd '[[:alnum:]]._-'`
		echo "PipelineId=$vPID"
		aws datapipeline put-pipeline-definition --pipeline-id ${vPID} --pipeline-definition file://${PROGDIR}/../definitions/pipeline-def-ondemand-${ENVIRONMENT}-spot.json
	fi	
	echo "Done"
} #create_pipeline


collect_yarn_logs() {
	get_pipeline_id
	clusterID=`aws emr list-clusters --query 'Clusters[*].[Name,Id,Status.State,Status.Timeline.CreationDateTime]'   --output text  | grep ${PIPELINE_ID} | sort -k4 -n | tail -1 | awk '{print $2}'`
	if [ -z ${clusterID} ];
	then
		echo "No cluster found"
		exit 1
	else		
		echo "Last ClusterId=${clusterID}"
		vIP=`aws emr describe-cluster --cluster-id ${clusterID} --query '{IP:Cluster.MasterPublicDnsName}' --output text | cut -d'.' -f1 | sed 's/[^0-9.-]*//g' | awk '{print substr($0,2)}' | sed 's/-/./g'`
		if [ ! -z ${vIP} ];
		then
			echo "Downloading file..."
			vLogDir="${PROGDIR}/../../yarn-logs/${vIP}/"
			mkdir -p "${vLogDir}"
			echo "aws s3 cp s3://my-${ENVIRONMENT}-logfiles/yarn-logs/${PIPELINE_ID}/${vIP}/ ${vLogDir} --recursive"
			aws s3 cp s3://my-${ENVIRONMENT}-logfiles/yarn-logs/${PIPELINE_ID}/${vIP}/ "${vLogDir}" --recursive
			echo "Done"
		fi	
	fi

}

fn_get_ondemand_price () {
	vPriceOfferFile="${PROGDIR}/../lib/ec2_price_offer.csv"
	if [ ! -f ${vPriceOfferFile} ];
	then
		echo "FATAL! Price offer file not found at ${vPriceOfferFile}"
		exit 1
	fi	
	if  [[ ${REGION} == "us-east-1" ]];
	then
		vRegion="US East (N. Virginia)"	
	else	
		echo "Only us-east-1 is supported"
		exit 1
	fi	
	vCurrPrice=`cat ${vPriceOfferFile} | grep -i "${vRegion}" | grep OnDemand | grep -i Shared | grep Linux | grep "${INSTANCE_TYPE}" | cut -d"," -f10 | sed 's/\"//g'`	
	echo ${vCurrPrice}
} #fn_get_ondemand_price

fn_spot_instance_az () {
	vSpotPriceFile="/tmp/quickaws_spot_price_history.txt"
	vStartTime=`python -c "import datetime; print (datetime.datetime.utcnow() - datetime.timedelta(minutes=${TERMINATE_MIN})).strftime('%Y-%m-%dT%H:%M:%S')"`
	vEndTime=`python -c "import datetime; print (datetime.datetime.utcnow()).strftime('%Y-%m-%dT%H:%M:%S')"`
	#Get current price
	vPriceOfferFile="${PROGDIR}/../lib/ec2_price_offer.csv"
	if  [[ ${REGION} == "us-east-1" ]];
	then
		vRegion="US East (N. Virginia)"	
	else	
		echo "Only us-east-1 is supported"
		exit 1
	fi	
	vCurrPrice=`cat ${vPriceOfferFile} | grep -i "${vRegion}" | grep OnDemand | grep -i Shared | grep Linux | grep "${INSTANCE_TYPE}" | cut -d"," -f10 | sed 's/\"//g'`	
	vBidPrice=`python -c "v=${vCurrPrice}*${BID_PERCENTAGE}; print ('%.3f' % v)"`
	echo "Bid price for ${INSTANCE_TYPE} = ${vBidPrice}"
	echo "Finding best availability zone for this bid price ..."
	if [ ! -f ${PROGDIR}/../lib/get_spot_duration.py ];
	then
		echo "FATAL!! Library not found at ${PROGDIR}/../lib/get_spot_duration.py"
		exit 1
	else
		SPOT_PRICE_HISTORY_FILE="/tmp/final-spot-history.txt"		
		${PROGDIR}/../lib/get_spot_duration.py --region ${REGION} --product-description 'Linux/UNIX' \
		--bids ${INSTANCE_TYPE}:${vBidPrice} --hours 10 --sort-by CurrentPrice --env ${ENVIRONMENT} \
		> ${SPOT_PRICE_HISTORY_FILE}
		
		#IFS=$'\n'
		AZ=""
		BID_PRICE=0
		BID_FOUND=0
		for eachLine in `cat ${SPOT_PRICE_HISTORY_FILE} | tail -n+3`
		#tail -n+3 ${SPOT_PRICE_HISTORY_FILE} |  while read eachLine; 
		do
			vAZ=`echo "${eachLine}" | cut -d',' -f3`
			vVolatilityDuration=`echo "${eachLine}" | cut -d',' -f1`
			vCurrPrice=`echo "${eachLine}" | cut -d',' -f4`

			if [[ "${vAZ}"  == 'us-east-1e' ]];
			then
				echo "No subnet available for us-east-1e where cost is ${vCurrPrice}. Skipping..."
				continue
			fi
			if [ `echo "${vCurrPrice}>${vBidPrice}" | bc` -eq 1  ];
			then
				echo "In ${vAZ}, ${vCurrPrice} is greater than bid price. So skipping ..."
				continue	
			fi	

			if [ `echo "${vVolatilityDuration}<0.2" | bc` -eq 1 ];
			then
				echo "${vAZ} is crossed bid price ${vVolatilityDuration} hour ago. Skipping..."	
				continue
			else
				AZ=${vAZ}
				BID_PRICE=${vBidPrice}
				echo "For bid price $"${vBidPrice}"( ${BID_PERCENTAGE} of ondemand cost), right now, best availability zone is ${AZ} and current price $"${vCurrPrice}
				#AZ:us-east-1e,BidPrice:0.532
				BID_FOUND=1
				break
			fi		
		done 
	fi
	

} #fn_spot_instance_az



fn_get_spot_az_subnet_id () {
	if [[ ${ENVIRONMENT} = 'qa' ]];
	then
		vEnv='SQA'
	else
		vEnv=`echo ${ENVIRONMENT} | awk '{print toupper($0)}'`	
	fi	
	#Samle subnet: US_NVA_SQA_1B_INTERNAL
	vSubnetName="US_NVA_${vEnv}_1`echo "${vAZ: -1}" | awk '{print toupper($0)}'`_INTERNAL"
	vSubnetId=$(aws ec2 describe-subnets --output text --query 'Subnets[?Tags[0].Value==`'${vSubnetName}'`][SubnetId]')
	if [ -z ${vSubnetId} ];
	then
		echo "FATAL: fn_spot_price_parameter_string: Subnet not found for ${vAZ}"
		exit 1
	fi
	echo ${vSubnetId} 
} #fn_get_spot_az_subnet_id


#echo $@
while getopts ":h:A:e:n:i:j:c:T:N:M:F:r:x:m:W:k:S:B:C:J:R:O:P:X:D:" OPTION
do
        case $OPTION in
        h)
        usage
        exit 1
        ;;
        A)
		ACTION=${OPTARG}
		;;
        e)
        ENVIRONMENT=${OPTARG}
        ;;
        n)
        PIPELINE_NAME=${OPTARG}
        ;;
        i)
        PIPELINE_ID=${OPTARG}
        ;;
        R)
		REGION=${OPTARG}
		;;
		j)
		JOBS=${OPTARG}
		;;
		c)
		CARRIER=${OPTARG}
		;;
		T)
		INSTANCE_TYPE=${OPTARG}
		;;
		N)
		NODE_COUNT_CORE=${OPTARG}
		;;
		W)
		NODE_COUNT_TASK=${OPTARG}
		;;
		M)
		TERMINATE_MIN=${OPTARG}
		;;
		F)
		REPOSITORY_ZIP=${OPTARG}
		;;
		r)
		ROLES=${OPTARG}
		;;
		x)
		NUM_OF_EXECUTOR=${OPTARG}
		;;
		m)
		EXECUTOR_MEMORY=${OPTARG}
		;;
		P)
		PROPERTIES_FILE=${OPTARG}
		;;		
		k)
		SKIP_PROFILE_SET=${OPTARG}
		;;
		S)
		SUBNET=${OPTARG}
		;;	
		B)
		BUILD_NUMBER=${OPTARG}
		;;
		C)
		CONFIG_BUILD_NUMBER=${OPTARG}
		;;
		J)
		SSO_JAR_FILE_LOCATION=${OPTARG}
		;;
		O)USE_SPOT_INSTANCE=${OPTARG}
		;;
		X)
		EXECUTOR_CORES=${OPTARG}
		;;
		D)
		DRIVER_MEMORY=${OPTARG}
		;;
        ?)
        usage
        exit
        ;;
        esac
  done
vKEEP_PARAMETER_FILE=0
if [ -z ${ENVIRONMENT} ];
then
	ENVIRONMENT='dev'
fi

if [ -z ${ROLES} ];
then
	ROLES="bigdatadevops"	
fi


if [ -z ${REGION} ];
then
	REGION='us-east-1'
fi	

if [ -z ${SKIP_PROFILE_SET} ];
then
 SKIP_PROFILE_SET=0
fi	

declare -a Required
Required=("ACTION" )
check_required_arguments ${Required}
check_allowed_values  "$(echo ${ALLOWED_ACTION[@]})" "ACTION"

if [ -z ${INSTANCE_TYPE} ];
then
	INSTANCE_TYPE="m1.xlarge"
else
	check_allowed_values  "$(echo ${ALLOWED_INSTANCE_TYPE[@]})" "INSTANCE_TYPE"
fi	
if [ -z ${CARRIER} ];
then
	CARRIER="rak"
else
	check_allowed_values   "$(echo ${ALLOWED_CARRIER[@]})"	"CARRIER"	
fi

if [ -z ${NODE_COUNT_CORE} ];
then
	NODE_COUNT_CORE=1
else
	validate_integer "NODE_COUNT_CORE"	
fi	
if [ -z ${NODE_COUNT_TASK} ];
then
	NODE_COUNT_TASK=2
else
	validate_integer "NODE_COUNT_TASK"	
fi	


if [ -z ${TERMINATE_MIN} ];
then
	TERMINATE_MIN=30
else
	validate_integer "TERMINATE_MIN"	
fi		

if [ -z ${BUILD_NUMBER} ];
then
	BUILD_NUMBER=""
else
 	validate_integer "BUILD_NUMBER"
fi 	

if [ -z ${CONFIG_BUILD_NUMBER} ];
then
	CONFIG_BUILD_NUMBER=""
else
	validate_integer "CONFIG_BUILD_NUMBER"	
fi 	

if [ -z ${USE_SPOT_INSTANCE} ];
then
	USE_SPOT_INSTANCE=1
else
	validate_integer "USE_SPOT_INSTANCE"	
fi 	

if [ -z ${DRIVER_MEMORY} ];
then
	DRIVER_MEMORY="10G"
fi

if [ -z ${EXECUTOR_CORES} ];
then
	EXECUTOR_CORES=1
else
	validate_integer "EXECUTOR_CORES"	
fi 	



if [ -z ${SUBNET} ];
then	
	if [[ ${ENVIRONMENT} == "qa" ]];
	then
		SUBNET="subnet-7e80f927"
	elif [[ ${ENVIRONMENT} == "dev" ]];
	then
		SUBNET="subnet-51082b26"
	elif [[ ${ENVIRONMENT} == "prod" ]]; 
	then
		SUBNET="subnet-7e8fe555" 
	fi
else
	if [ ${USE_SPOT_INSTANCE} -eq 1 ];
	then
		echo "WARNING! Spot instance cannot be used with explicit subnet declaration. Setting USE_SPOT_INSTANCE to 0"
		USE_SPOT_INSTANCE=0
	fi	
fi

s3loc="my-`echo ${ENVIRONMENT} | awk '{print tolower($0)}'`-files/spark-jobs/ondemand/`whoami`"
s3loc_config_files="my-`echo ${ENVIRONMENT} | awk '{print tolower($0)}'`-files/BUILDS/SPARK-JOBS-CONF"
if [ -z ${PROPERTIES_FILE} ];
then
	PROPERTIES_FILE="${ENVIRONMENT}/${CARRIER}.properties"
fi	


#### main ######
if [ ${SKIP_PROFILE_SET} -eq 0 ];
then	
	echo "Setting profile for ${ENVIRONMENT} environment ..."
	if [ -z ${SSO_JAR_FILE_LOCATION} ];
	then
		SSO_JAR_FILE_LOCATION="${PROGDIR}/../lib/SSOGenerator-1.1.8.jar"
	fi
	fn_set_profile ${ENVIRONMENT} ${ROLES} ${SKIP_PROFILE_SET} ${SSO_JAR_FILE_LOCATION}
	echo "Done"
fi

echo "Checking aws cli connection ..."
aws s3 ls > /dev/null
if [ $? -gt 0 ];
then
	echo "FAILED!! aws cli not able to connect"
	exit 1
fi	
echo "Done"

if [[ ${ACTION} == "uploadCode" ]];
then
	Required+=("REPOSITORY_ZIP")
	Required+=("CARRIER")
	check_required_arguments ${Required}	
	upload_file
elif [[ ${ACTION} == "createCluster" ]];
then	
	Required+=("REPOSITORY_ZIP")
	Required+=("CARRIER")
	Required+=("JOBS")
	Required+=("NUM_OF_EXECUTOR")
	Required+=("EXECUTOR_MEMORY")
	check_required_arguments
	upload_file
	create_cluster 
elif [[ ${ACTION} == "createClusterOnly" ]];
then	
	Required+=("REPOSITORY_ZIP")
	Required+=("CARRIER")
	Required+=("JOBS")
	Required+=("NUM_OF_EXECUTOR")
	Required+=("EXECUTOR_MEMORY")
	check_required_arguments
	create_cluster 
elif [[ ${ACTION} == "stopCluster" ]];
then	
	stop_pipeline 	
elif [[ ${ACTION} == "getClusterInfo" ]];
then	
	get_cluster_info 
elif [[ ${ACTION} == "createPipeline" ]];
then	
	create_pipeline 
elif [[ ${ACTION} == "downloadYarnLogs" ]];
then	
	collect_yarn_logs
elif [[ ${ACTION} == "createParameterFileOnly" ]];
then	
	Required+=("REPOSITORY_ZIP")
	Required+=("CARRIER")
	Required+=("JOBS")
	Required+=("NUM_OF_EXECUTOR")
	Required+=("EXECUTOR_MEMORY")
	check_required_arguments
	create_parameter_file $JOBS
	vKEEP_PARAMETER_FILE=1
	echo "Parameter file created at : ${TMP_PIPELINE_VALUES_JSON}"
fi
#if [ ${vKEEP_PARAMETER_FILE} -eq 0 ] && [ -f ${TMP_PIPELINE_VALUES_JSON} ];
#then	
#	rm "${TMP_PIPELINE_VALUES_JSON}"
#fi
