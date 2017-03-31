#!/bin/bash

if [ $# -ne 1 ]
then
   echo  "usage: $0 JSON_FILE" >&2
   exit 1
fi

JSON_FILE=$1

if [ ! -f $JSON_FILE ]
then
  echo "File $JSON_FILE does not exist" >&2
  exit 2
fi

# read parameters from json file
PUB_KEY=`cat $JSON_FILE | jq -r .pub_key`
PROJECT_NAME=`cat $JSON_FILE | jq -r .project_name`
DESCRIPTION=`cat $JSON_FILE | jq -r .description`
USERNAME=`cat $JSON_FILE | jq -r .username`
EMAIL=`cat $JSON_FILE | jq -r .email`
PASSWORD=`cat $JSON_FILE | jq -r .password`

[ "$PASSWORD" = "null" ] && PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)

source admin-openrc

# Create the project
openstack project create --description "$DESCRIPTION" --domain default $PROJECT_NAME
# Set admin as administrator of the project
openstack role add --user admin --project $PROJECT_NAME admin

# Create a user for the project
openstack user create --project $PROJECT_NAME --password $PASSWORD --email $EMAIL $USERNAME
# Assign it to the project
openstack role add --user $USERNAME --project $PROJECT_NAME user                                                                 

# authorize to SSH and  ICMP instances
export OS_PROJECT_NAME=$PROJECT_NAME
nova secgroup-add-rule default tcp 22 22 0.0.0.0/0
nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0

# create a router to get Internet access (floating IPs)
ROUTER_NAME="internet-router-$PROJECT_NAME"
neutron router-create $ROUTER_NAME
neutron router-gateway-set $ROUTER_NAME provider

# create Linux user
useradd --create-home --shell /bin/bash $USERNAME

# give access in SSH
mkdir /home/$USERNAME/.ssh
echo $PUB_KEY >> /home/$USERNAME/.ssh/authorized_keys 

# Creat OpenStack configuration file
OPENRC_FILE=/home/$USERNAME/${USERNAME}-openrc
echo "export OS_PROJECT_DOMAIN_NAME=default " > $OPENRC_FILE
echo "export OS_USER_DOMAIN_NAME=default" >> $OPENRC_FILE
echo "export OS_PROJECT_NAME=$PROJECT_NAME" >> $OPENRC_FILE
echo "export OS_USERNAME=$USERNAME" >> $OPENRC_FILE
echo "export OS_PASSWORD=$PASSWORD" >> $OPENRC_FILE
echo "export OS_AUTH_URL=http://controller:35357/v3" >> $OPENRC_FILE
echo "export OS_IDENTITY_API_VERSION=3" >> $OPENRC_FILE
echo "export OS_IMAGE_API_VERSION=2" >> $OPENRC_FILE
chmod o-rwx $OPENRC_FILE

# Set credentials at login
echo "" >> /home/$USERNAME/.bashrc
echo "# OpenStack access" >> /home/$USERNAME/.bashrc
echo "source $OPENRC_FILE" >> /home/$USERNAME/.bashrc

# Create a keypair
. $OPENRC_FILE
PRIVATE_KEY_FILE=/home/$USERNAME/.ssh/${USERNAME}-key.pem
ssh-keygen -N "" -f $PRIVATE_KEY_FILE
# and add it to the OpenStack project
openstack keypair create --public-key ${PRIVATE_KEY_FILE}.pub ${USERNAME}_key

# Make sure all files belong to the new user
chown -R ${USERNAME}:${USERNAME} /home/$USERNAME
