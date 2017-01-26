#!/bin/bash
vClusterId=`cat /mnt/var/lib/info/job-flow.json | grep -i jobFlowId | sed 's/[",]//g' | awk '{print $2}'`
vState=""
while [[ ${vState} != "RUNNING"  ]];
do
	vRow=`aws emr describe-cluster --cluster-id ${vClusterId}  --query 'Cluster.InstanceGroups[*].{TYPE:InstanceGroupType,STATE:Status.State}' --output text | grep TASK`
	vState=`echo "${vRow}" | awk '{print $1}' `
	echo ${vState}
	if [[ ${vState} == "RUNNING"  ]];
	then
		break
	fi		
	sleep 120
done	

