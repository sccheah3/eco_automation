#! /bin/bash

HOST_SERV="172.16.219.209"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
# printf "${GREEN}$TEST_FAN${NC}\n"

BMC_IP=$( sed '1q;d' system_info.txt )
BMC_USER=$( sed '2q;d' system_info.txt )
BMC_PASS=$( sed '3q;d' system_info.txt )
LAN_MAC=$( sed '4q;d' system_info.txt )
CBURN_IMG=$( sed '5q;d' system_info.txt )
CBURN_PARAM=$( sed '6q;d' system_info.txt )


TEST_FAN=1
TEST_RSC=1
TEST_PMINFO=1
TEST_ONOFF=1
TEST_SUM=1
ENABLE_OOB=1


TURN_SYSTEM_ON()
{
	POWER_STATUS="$(ipmitool -H $BMC_IP -U $BMC_USER -P $BMC_PASS chassis power status | awk '{print $4}')"
	if [ $POWER_STATUS == off ]; then
		ipmitool -H $BMC_IP -U $BMC_USER -P $BMC_PASS chassis power on 
		sleep 30
		POWER_STATUS="$(ipmitool -H $BMC_IP -U $BMC_USER -P $BMC_PASS chassis power status | awk '{print $4}')"
		NUM_ATTEMPTS=1
		while [ $POWER_STATUS == off ] && [[ $NUM_ATTEMPTS -le 5 ]]; do
			NUM_ATTEMPTS=$(( $NUM_ATTEMPTS + 1 ))

			ipmitool -H $BMC_IP -U $BMC_USER -P $BMC_PASS chassis power on 
			sleep 30
			POWER_STATUS="$(ipmitool -H $BMC_IP -U $BMC_USER -P $BMC_PASS chassis power status | awk '{print $4}')"
		done
		if [ $POWER_STATUS == off ]; then
			printf "[${RED}ERROR${NC} - unable to set system to ON state]\n\n"
			echo "[ERROR - unable to set system to ON state]" | tee -a logs/sum_result.log
		else
			printf "[${GREEN}SUCCESS${NC} - system set to ON state]\n\n"
			echo "[SUCCESS - system set to ON state]" >> logs/sum_result.log
		fi
	fi
}

TURN_SYSTEM_OFF()
{
	POWER_STATUS="$(ipmitool -H $BMC_IP -U $BMC_USER -P $BMC_PASS chassis power status | awk '{print $4}')"
	if [ $POWER_STATUS == on ]; then
		ipmitool -H $BMC_IP -U $BMC_USER -P $BMC_PASS chassis power off 
		sleep 30
		POWER_STATUS="$(ipmitool -H $BMC_IP -U $BMC_USER -P $BMC_PASS chassis power status | awk '{print $4}')"
		NUM_ATTEMPTS=1
		while [ $POWER_STATUS == on ] && [[ $NUM_ATTEMPTS -le 5 ]]; do
			NUM_ATTEMPTS=$(( $NUM_ATTEMPTS + 1 ))

			ipmitool -H $BMC_IP -U $BMC_USER -P $BMC_PASS chassis power off
			sleep 30
			POWER_STATUS="$(ipmitool -H $BMC_IP -U $BMC_USER -P $BMC_PASS chassis power status | awk '{print $4}')"
		done
		if [ $POWER_STATUS == on ]; then
			printf "[${RED}ERROR${NC} - unable to set system to OFF state]\n\n"
			echo "[ERROR - unable to set system to OFF state]" | tee -a logs/sum_result.log
		else
			printf "[${GREEN}SUCCESS${NC} - system set to OFF state]\n\n"
			echo "[SUCCESS - system set to OFF state]" >> logs/sum_result.log
		fi
	fi
}


if [[ "$#" -eq 0 ]]; then
	TEST_FAN=0
	TEST_PMINFO=0
	TEST_ONOFF=0
	TEST_SUM=0
	ENABLE_OOB=0
fi

for arg in "$@" ; do
	if [[ $arg == "FAN" ]]; then
		TEST_FAN=0
	elif [[ $arg == "PMINFO" ]]; then
		TEST_PMINFO=0
	elif [[ $arg == "SUM" ]]; then
		TEST_SUM=0
	elif [[ $arg == "OOB" ]]; then
		ENABLE_OOB=0
	elif [[ $arg == "ONOFF" ]]; then
		TEST_ONOFF=0
	fi
done

if [[ $ENABLE_OOB -eq 0 ]]; then
	printf "${GREEN}Enabling OOB...${NC}\n"
	curl -X POST -F Login=$BMC_USER -F Password=$BMC_PASS -F address=$BMC_IP -F action=Enable 172.16.0.3/cgi-bin/oob1.php | tail -n 5 | tee -a logs/enable_oob.log
fi

if [[ $TEST_FAN -eq 0 ]]; then
	printf "${GREEN}Testing fan speed...${NC}\n"
	./fanspeedcheck.sh $BMC_IP $BMC_USER $BMC_PASS | tee -a logs/fanspeedcheck.log
fi


if [[ $TEST_PMINFO -eq 0 ]]; then
	printf "${GREEN}Testing PM INFO...${NC}\n"
	./SMCIPMITool*/SMCIPMITool $BMC_IP $BMC_USER $BMC_PASS pminfo | tee -a logs/pm_info.log
fi

if [[ $TEST_SUM -eq 0 ]]; then
	printf "${GREEN} Testing SUM...${NC}\n"

	SUM_TESTS=( QueryProductKey GetBIOSInfo GetBmcInfo CheckOOBSupport CheckAssetInfo \
				CheckSensorData GetDmiInfo GetKcsPriv GetEventLog \
				ClearEventLog GetEventLog GetPsuInfo GetPowerStatus GetRaidControllerInfo \
				GetNvmeInfo GetSataInfo GetDefaultBiosCfg )

	for TEST in ${SUM_TESTS[@]}; do
		printf "${GREEN} [SUM] $TEST${NC}\n" 
		echo [SUM - $TEST] >> logs/sum_result.log
		./sum*/sum -i $BMC_IP -u $BMC_USER -p $BMC_PASS -c $TEST | tee -a logs/sum_result.log
		printf "\n\n" | tee -a logs/sum_result.log
	done


	TURN_SYSTEM_OFF
	TURN_SYSTEM_ON

	# set both autopxe and autoipxe commands
	printf "${GREEN}Setting iPXE/PXE command to boot to cburn...${NC}\n\n"
	curl -X POST -F command="$CBURN_IMG RC=$HOST_SERV/eco_automate/cburn_TAS_install.sh" -F address=$LAN_MAC -F action=Update -F lega_only=LEGA 172.16.0.3/dct/cburnTools/httpIPXE | tail -n 20
	curl -X POST -F command="$CBURN_IMG RC=$HOST_SERV/eco_automate/cburn_TAS_install.sh" -F address=$LAN_MAC -F action=Update -F ipxe_only=IPXE 172.16.0.3/dct/cburnTools/httpIPXE | tail -n 20 

	printf "${GREEN}Waiting 9 mins to fully boot into cburn and install TAS for CheckSystemUtilization...${NC}\n\n"
	sleep 540

	printf "${GREEN} [SUM] CheckSystemUtilization${NC}\n" 
	echo [SUM - CheckSystemUtilization] >> logs/sum_result.log
	./sum*/sum -i $BMC_IP -u $BMC_USER -p $BMC_PASS -c CheckSystemUtilization | tee -a logs/sum_result.log
	echo "If you hit an error here, install Thin Agent Service (TAS) on cburn and run the sum command manually." | tee -a logs/sum_result.log
	printf "\n\n" | tee -a logs/sum_result.log

	printf "${GREEN} [SUM] GetMaintenEventLog${NC}\n" 
	echo [SUM - GetMaintenEventLog] >> logs/sum_result.log
	./sum*/sum -i $BMC_IP -u $BMC_USER -p $BMC_PASS -c GetMaintenEventLog --st $( date +%Y%m%d -d "5 day ago" ) --et $( date +%Y%m%d ) --count 5 | tee -a logs/sum_result.log
	printf "\n\n" | tee -a logs/sum_result.log

	printf "${GREEN} [SUM] BiosRotManage${NC}\n" 
	echo [SUM - BiosRotManage] >> logs/sum_result.log
	./sum*/sum -i $BMC_IP -u $BMC_USER -p $BMC_PASS -c BiosRotManage --action 1| tee -a logs/sum_result.log
	printf "\n\n" | tee -a logs/sum_result.log

	printf "${GREEN} [SUM] BmcRotManage${NC}\n" 
	echo [SUM - BmcRotManage] >> logs/sum_result.log
	./sum*/sum -i $BMC_IP -u $BMC_USER -p $BMC_PASS -c BmcRotManage --action 1| tee -a logs/sum_result.log
	printf "\n\n" | tee -a logs/sum_result.log


	printf "${GREEN} [SUM] SetPowerAction${NC}\n\n" 

	# make sure it's in the on state first
	TURN_SYSTEM_ON

	printf "${GREEN} [SUM] SetPowerAction - DOWN${NC}\n" 
	echo [SUM - SetPowerAction - DOWN] >> logs/sum_result.log
	./sum*/sum -i $BMC_IP -u $BMC_USER -p $BMC_PASS -c SetPowerAction --action 1 | tee -a logs/sum_result.log
	sleep 30
	POWER_STATUS="$(ipmitool -H $BMC_IP -U $BMC_USER -P $BMC_PASS chassis power status | awk '{print $4}')"
	if [[ $POWER_STATUS == off ]]; then
		printf "${GREEN}SUCCESS${NC} - system is off"
		echo "SUCCESS - system is off" >> logs/sum_result.log
	else
		printf "${RED}FAIL${NC} - system is still on"
		echo "FAIL - system is still on" >> logs/sum_result.log
	fi
	printf "\n\n" | tee -a logs/sum_result.log


	# make sure system is on off state 
	TURN_SYSTEM_OFF

	printf "${GREEN} [SUM] SetPowerAction - UP${NC}\n" 
	echo [SUM - SetPowerAction - UP] >> logs/sum_result.log
	./sum*/sum -i $BMC_IP -u $BMC_USER -p $BMC_PASS -c SetPowerAction --action 0 | tee -a logs/sum_result.log
	sleep 45
	POWER_STATUS="$(ipmitool -H $BMC_IP -U $BMC_USER -P $BMC_PASS chassis power status | awk '{print $4}')"
	if [[ $POWER_STATUS == on ]]; then
		printf "${GREEN}SUCCESS${NC} - system is on"
		echo "SUCCESS - system is on" >> logs/sum_result.log
	else
		printf "${RED}FAIL${NC} - system is still off"
		echo "FAIL - system is still off" >> logs/sum_result.log
	fi
	printf "\n\n" | tee -a logs/sum_result.log


	# make sure system is in ON state
	TURN_SYSTEM_ON

	# set both autopxe and autoipxe commands
	printf "${GREEN}Setting iPXE/PXE command to boot to cburn...${NC}\n\n"
	curl -X POST -F command=$CBURN_IMG -F address=$LAN_MAC -F action=Update -F lega_only=LEGA 172.16.0.3/dct/cburnTools/httpIPXE | tail -n 20
	curl -X POST -F command=$CBURN_IMG -F address=$LAN_MAC -F action=Update -F ipxe_only=IPXE 172.16.0.3/dct/cburnTools/httpIPXE | tail -n 20 

	printf "${GREEN}Waiting 8 mins to fully boot into cburn for SHUTDOWN action...${NC}\n\n"
	sleep 480

	printf "${GREEN} [SUM] SetPowerAction - SOFTSHUTDOWN${NC}\n" 
	echo [SUM - SetPowerAction - SOFTSHUTDOWN] >> logs/sum_result.log
	./sum*/sum -i $BMC_IP -u $BMC_USER -p $BMC_PASS -c SetPowerAction --action 4 | tee -a logs/sum_result.log
	sleep 45
	POWER_STATUS="$(ipmitool -H $BMC_IP -U $BMC_USER -P $BMC_PASS chassis power status | awk '{print $4}')"
	if [[ $POWER_STATUS == off ]]; then
		printf "${GREEN}SUCCESS${NC} - system is off"
		echo "SUCCESS - system is off" >> logs/sum_result.log
	else
		printf "${RED}FAIL${NC} - system is still on Try this manually by booting the SUT to cburn and run the command."
		echo "FAIL - system is still on. Try this manually by booting the SUT to cburn and run the command." >> logs/sum_result.log
	fi
	printf "\n\n" | tee -a logs/sum_result.log


	# make sure system is in ON state
	TURN_SYSTEM_ON


	# no good way to confirm these
	printf "${RED} May want to check CYCLE, RESET, and REBOOT manually. There is no good way to programmatically confirm success on these commands.${NC}\n\n"
	echo "[SUM] May want to check CYCLE, RESET, and REBOOT manually. There is no good way to programmatically confirm success on these commands." >> logs/sum_result.log

	printf "${GREEN}Waiting 8 mins to fully boot into cburn for REBOOT action...${NC}\n\n"
	sleep 480

	printf "${GREEN} [SUM] SetPowerAction - REBOOT${NC}\n" 
	echo [SUM - SetPowerAction - REBOOT] >> logs/sum_result.log
	./sum*/sum -i $BMC_IP -u $BMC_USER -p $BMC_PASS -c SetPowerAction --action 5 | tee -a logs/sum_result.log
	sleep 30
	printf "\n\n" | tee -a logs/sum_result.log

	printf "${GREEN} [SUM] SetPowerAction - CYCLE${NC}\n" 
	echo [SUM - SetPowerAction - CYCLE] >> logs/sum_result.log
	./sum*/sum -i $BMC_IP -u $BMC_USER -p $BMC_PASS -c SetPowerAction --action 2 | tee -a logs/sum_result.log
	sleep 30
	printf "\n\n" | tee -a logs/sum_result.log

	printf "${GREEN} [SUM] SetPowerAction - RESET${NC}\n" 
	echo [SUM - SetPowerAction - RESET] >> logs/sum_result.log
	./sum*/sum -i $BMC_IP -u $BMC_USER -p $BMC_PASS -c SetPowerAction --action 3 | tee -a logs/sum_result.log
	sleep 30
	printf "\n\n" | tee -a logs/sum_result.log


fi
