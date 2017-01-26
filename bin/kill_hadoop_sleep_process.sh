#!/bin/bash
for each in `ps -u hadoop | grep sleep | awk '{ print  $1 }'`
do
	kill ${each}
done      