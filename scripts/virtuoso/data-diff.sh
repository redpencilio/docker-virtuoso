#!/bin/bash
apt-get update > /dev/null
apt-get -y install jq python3 > /dev/null

config=$1
source=$(jq -r ".source" $config)
target=$(jq -r ".target" $config)

command=$(python3 generate-datadiff.py $config)

diff <(cat $source | eval $command | sort) <(cat $target | eval $command | sort)
