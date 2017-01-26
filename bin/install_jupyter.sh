#!/usr/bin/env bash
fn_install_jupyter() {
	sudo pip install jupyter
	sudo pip install pandas
	mkdir -p /home/hadoop/notebooks
	curl -L -o jupyter-scala https://git.io/vrHhi && chmod +x jupyter-scala && ./jupyter-scala && rm -f jupyter-scala
	SPARK_HOME="/usr/lib/spark"
	PY4J=`python -c 'import os; from glob import glob; py4j = glob(os.path.join("/usr/lib/spark/python", "lib", "py4j-*.zip"))[0]; print py4j;'`
	PYTHONPATH=$SPARK_HOME/python:$PY4J:\$PYTHONPATH
	echo -e "\n\n###Added for jupyter###" >> ~/.bashrc
	echo "export SPARK_HOME=$SPARK_HOME" >> ~/.bashrc
	echo "export PYTHONPATH=$PYTHONPATH" >> ~/.bashrc
	. ~/.bashrc
	vIP=`hostname -I | awk '{ print $1 }'`
	/usr/local/bin/jupyter notebook --generate-config
	mkdir -p /tmp/jupyter
	cd /tmp/jupyter
	nohup /usr/local/bin/jupyter notebook --ip=${vIP} --port=8889 --notebook-dir=/home/hadoop/notebooks --no-browser  < /dev/null > /tmp/logFile 2>&1 &
	echo "Jupyter Started ..."
}

fn_create_restart_file() {

rm /home/hadoop/restart_jupyter.sh
touch /home/hadoop/restart_jupyter.sh
cat <<EOT >> "/home/hadoop/restart_jupyter.sh"
	restart_jupyter(){
	for eachPid in \$(ps -ef | grep -i jupyter | grep hadoop | grep -v grep | grep -v restart_jupyter | awk '{ print \$2 }')	
	do 
	  kill \${eachPid}
	done  
	mkdir -p /tmp/jupyter
	cd /tmp/jupyter
	nohup /usr/local/bin/jupyter notebook --ip=${vIP} --port=8889 --notebook-dir=/home/hadoop/notebooks --no-browser   > /tmp/logFile 2>&1 &
}
restart_jupyter
EOT
}

fn_install_jupyter
fn_create_restart_file
exit 0