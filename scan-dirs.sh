#!/bin/bash

rootdirs=`find / -maxdepth 1 -mindepth 1 -type d | grep -v "/proc" | grep -v  "/boot"| grep -v  "/sys" | grep -v  "/dev"`

find $rootdirs -type f -print0 | xargs -0 md5sum > /tmp/A.txt

bash -c "$@"

find $rootdirs -type f -print0  | xargs -0 md5sum > /tmp/B.txt

export IFS='\n'
newfiles=`diff /tmp/A.txt /tmp/B.txt | grep -v '/tmp/A.txt$' | grep -v '/tmp/B.txt$' | grep '^> ' | cut -f4 -d" " `

echo $newfiles

tar -czf /tmp/archive.tgz --files-from - <<< "$newfiles"


while read  line; do
    echo "line: $line"
done <<< "$newfiles"
