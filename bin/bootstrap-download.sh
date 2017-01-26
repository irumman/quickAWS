#!/bin/bash
set -e
S3_CODE_REPO=$1
LOCAL_DIR=$2
aws s3 cp "${S3_CODE_REPO}" "${LOCAL_DIR}" 
ZIP_FILE=`basename ${S3_CODE_REPO}`
cd "${LOCAL_DIR}"
FILE_EXT="${ZIP_FILE##*.}"
if [[ ${FILE_EXT} == 'zip' ]];
then
	unzip "${ZIP_FILE}"
elif [[ ${FILE_EXT} == 'tar.gz' ]];
then 
	tar -xzf "${ZIP_FILE}"   -C "${LOCAL_DIR}"  
else
	echo "Unknown file type"
	exit 1
fi