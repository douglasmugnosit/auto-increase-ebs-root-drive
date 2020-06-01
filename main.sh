#!/bin/bash


#########
# DISCLAIMER
# THIS IS NOT A PRODUCTION SCRIPT. BEFORE USE IT IN PRODUCTION MAKE SURE YOU TESTED
# IT IN YOUR LINUX FLAVOR/VERSION. I SUGGEST YOU TO  ADD CONDITIONS AND LOGGING
# TO HELP YOU TROUBLESHOOT IN CASE YOU NEED. THIS IS A TEMPLATE CREATED AS EXAMPLE 
# SO YOU CAN/MUST IMPROVE AND ADJUST TO YOUR NEEDs
#########


#Customizable variables
#Threshold to increase the volume size
THRESHOLD="80"
#How much % do you want to increase in case volume arrive in threshold.
#Ex. if 20%, the volume will increase 20% of the size. if it has 10G, it will
#become 12G. 
INCREASE_PERCENTAGE=20
########################################################################

#GET AWS INSTANCE ID
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

#Get AWS Region
REGION_ID=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep -oP '\"region\" : \"\K[^\"]+')

#get root drive name
ROOT_DRIVE_PARTITION=$(df / | grep -iv filesystem | awk '{print $1}')
ROOT_DRIVE_PARTITION_LETTER=$(echo ${ROOT_DRIVE_PARTITION::-1})
ROOT_DRIVE_PARTITION_NUMBER=$(echo ${ROOT_DRIVE_PARTITION} | tail -c 2)

#Get new size
NEW_REQUIRED_SIZE_IN_GB=$(df -m / | grep -vi "filesystem" | awk -v INCREASE_PERCENTAGE="$INCREASE_PERCENTAGE" '{printf ("%.0f\n",($2*((INCREASE_PERCENTAGE/100)+1)/1024))}' )

#get current usage in percentage
PERCENT_USAGE=$(df -h / | grep -vi "filesystem" | awk '{print $5}' | tr -d "%")

#
if [ $PERCENT_USAGE -ge $THRESHOLD ]; then
	#Try using xvda and sda
	VOLUME_ID=""
	echo $VOLUME_ID | grep -qi "vol-" || VOLUME_ID=$(aws ec2 describe-volumes  --filters Name=attachment.device,Values=/dev/xvda Name=attachment.instance-id,Values=$INSTANCE_ID --query 'Volumes[*].{ID:VolumeId}' --region $REGION_ID --output text)
	echo  $VOLUME_ID | grep -qi "vol-"  || VOLUME_ID=$(aws ec2 describe-volumes  --filters Name=attachment.device,Values=/dev/sda Name=attachment.instance-id,Values=$INSTANCE_ID --query 'Volumes[*].{ID:VolumeId}' --region $REGION_ID --output text)

	#increase volume
	aws ec2 modify-volume \
		--size $NEW_REQUIRED_SIZE_IN_GB \
		--volume-id $VOLUME_ID \
		--region $REGION_ID
			
	#Wait/loop until volume get resized in console. 
	while [[ $(aws ec2 describe-volumes  --filters Name=volume-id,Values=$VOLUME_ID --region $REGION_ID --query Volumes[*].Size --output text) -ne $NEW_REQUIRED_SIZE_IN_GB ]] ; do
	 sleep 10
	 echo "[INFO] - Waiting volume increase in AWS to resize inside server. in AWS it is still showing in the console with:"
	 aws ec2 describe-volumes  --filters Name=volume-id,Values=$VOLUME_ID --region us-east-1 --query Volumes[*].Size --output text
	done
	
	#Increase filesystem size
    growpart  $ROOT_DRIVE_PARTITION_LETTER	$ROOT_DRIVE_PARTITION_NUMBER
	
	#resize2fs - increase fs if EXT*
	resize2fs $ROOT_DRIVE_PARTITION
	
	#xfs_growfs - increase fs if XFS
	xfs_growfs $ROOT_DRIVE_PARTITION

fi
