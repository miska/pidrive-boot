#!/bin/sh
export PATH="/bin:/usr/bin:/sbin:/usr/sbin"
IP=""
while [ -z "$IP" ]; do
IP="`ip a s eth0 scope global | sed -n 's|.*inet[[:blank:]]*\([0-9.]*\)/.*|\1|p'`"
sleep 3
done
convert /etc/background.png  -pointsize 120 -background Black -fill white  label:"http://$IP/" -gravity Center -pointsize 1000 -append /tmp/background_label.jpg
/usr/bin/fbi -T 1  -nocomments  -a -noverbose /tmp/background_label.jpg
