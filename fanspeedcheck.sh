#/bin/bash

#################################
# Fan Speed Checker 
# Author: Kenneth Ching
# Rev 1.0 7/16/2020
#################################
# Rev 1.0 Initial build
# Rev 1.1 Fixed PUE2 recognition error 

#File Creator
if [ -e fanspeedchecker ]
then
	rm -f fanspeedchecker
fi
#FILE=fanspeedchecker

#Input IPMI naming (passing arguments)
IPMI=$1
IPMIuser=$2
IPMIpass=$3

# DIR="$( cd "$( dirname "$0" )" && pwd )"
# echo ./SMCIPMITool*

#Help Menu
if [ "$1" == '-h' ] || [ "$1" == '--help' ]; then
	echo "parameters taken: ./Fanspeedtest.sh <IPMI IP> <username> <password>"
fi

#Prompt if no arguments are passed
if [ -z "$IPMI" ] && [ -z "$IPMIuser" ] && [ -z "$IPMIpass" ]; then
	echo Fan Speed Checker 
	read -p "What is the IPMI of the system: " -e IPMI
	read -p "What is the username? " -e IPMIuser
	read -p "What is the password? " -e IPMIpass

fi

#Test if IPMI is valid
PING="$(ping -c 3 $IPMI | grep -i pack | awk '{print $6}')"
if [ $PING == '0%' ]; then
	echo IPMI is alive
else
	echo IPMI is dead, please check the IPMI connection or username and password
	exit 1
fi

#Check number of Fans
NUMFAN="$(./SMCIPMITool*/SMCIPMITool $IPMI $IPMIuser $IPMIpass ipmi sensor | grep -i FAN | wc -l)"
ACTFAN="$(./SMCIPMITool*/SMCIPMITool $IPMI $IPMIuser $IPMIpass ipmi sensor | grep -i -E 'OK.*FAN' | wc -l)"
echo Current Fan Reading #| tee -a $FILE
./SMCIPMITool*/SMCIPMITool $IPMI $IPMIuser $IPMIpass ipmi sensor | grep -i -e 'fan\|reading' #| tee -a $FILE
echo There are $NUMFAN fans on the motherboard, $ACTFAN fans are plugged in. #| tee -a $FILE

#Available fan mode
NUMMODE="$(./SMCIPMITool*/SMCIPMITool $IPMI $IPMIuser $IPMIpass ipmi fan | grep -E [0-9] | grep -Ev Current | wc -l)"
echo $NUMMODE fan modes are supported: #| tee -a $FILE
./SMCIPMITool*/SMCIPMITool $IPMI $IPMIuser $IPMIpass ipmi fan | grep -E [0-9] | grep -Ev Current | awk -F ':' '{print $2}' #| tee -a $FILE

#Gather initial fan mode
FIRSTMODE="$(./SMCIPMITool*/SMCIPMITool $IPMI $IPMIuser $IPMIpass ipmi fan | awk -F[ 'NR==1{print $2}' | sed 's/..$//' | sed '1s/^.//')"
FIRSTSWITCH="$(./SMCIPMITool*/SMCIPMITool $IPMI $IPMIuser $IPMIpass ipmi fan | grep -i "$FIRSTMODE" | awk -F: NR==2'{print $1}')"
echo First mode is $FIRSTMODE

#Switch fan mode
CURRENT="$(./SMCIPMITool*/SMCIPMITool $IPMI $IPMIuser $IPMIpass ipmi fan | awk 'NR==1{print $0}')"
echo $CURRENT #| tee -a $FILE
FIRSTCAPTURE="$(./SMCIPMITool*/SMCIPMITool $IPMI $IPMIuser $IPMIpass ipmi sensor | grep -i -E 'OK.*FAN' | awk -F ')' '{print $2}' | awk '{print $1" "$3" "$4}')"
echo "$FIRSTCAPTURE" #| tee -a $FILE
sleep 2

#echo Starting fan mode switch
for (( i=1; i<=$NUMMODE; i++ ))
do
	FANMODE[i]=$(./SMCIPMITool*/SMCIPMITool $IPMI $IPMIuser $IPMIpass ipmi fan | grep -E [0-9] | grep -Ev Current | awk -F: NR==$i'{print $2}' | sed '1s/^.//')
	SWITCHNUM[i]=$(./SMCIPMITool*/SMCIPMITool $IPMI $IPMIuser $IPMIpass ipmi fan | grep -E [0-9] | grep -Ev Current | awk -F: NR==$i'{print $1}')
	if [[ "${FANMODE[i]}" != "$FIRSTMODE" ]]; then
		echo Starting fan mode switch
		./SMCIPMITool*/SMCIPMITool $IPMI $IPMIuser $IPMIpass ipmi fan ${SWITCHNUM[i]}
		echo Current Fan Speed Mode is [ ${FANMODE[i]} ] #| tee -a $FILE
		echo "Waiting for fans to ramp up/down to capture the correct fan speed (8s)"
		sleep 8
		CAPTURE[i]="$(./SMCIPMITool*/SMCIPMITool $IPMI $IPMIuser $IPMIpass ipmi sensor | grep -i -E 'OK.*FAN' | awk -F ')' '{print $2}' | awk '{print $1" "$3" "$4}')"
		echo "${CAPTURE[i]}" #| tee -a $FILE
		sleep 3
	else
		continue
	fi
done

#Switch back to initial fan mode
echo Switching back to First fan mode: $FIRSTMODE
./SMCIPMITool*/SMCIPMITool $IPMI $IPMIuser $IPMIpass ipmi fan $FIRSTSWITCH

echo Completed all the fan modes supported. Please review the captured fan speeds on fanspeedchecker file for info.




