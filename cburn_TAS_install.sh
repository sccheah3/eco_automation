#! /bin/bash

#################################
# Prep for SUM CheckSystemUtilization Test
# Developed by Stanley Cheah
# Rev 1.0
################################

HOSTSERV="172.16.219.209"

wget --recursive --no-parent --reject="index.html*" http://${HOSTSERV}/tools/TAS > /dev/null
if [ $? -ne 0 ]; then
	echo "Error acquiring TAS from ${HOSTSERV}" > /dev/tty0
	exit 1
fi

cd $HOSTSERV/tools/TAS
chmod 755 *
./install.sh

return 0
