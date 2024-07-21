#!/bin/bash

#0xyassine
#SCRIPT USED TO SETUP VAULTWARDEN USING THE BEST SECURITY PRACTICE
#VAULTWARDEN WILL BE RUNNNG AS NON ROOT USER USING DOCKER ROOTLESS
#MAKE SURE YOU HAVE SUDO ACCESS BEFORE EXECUTING THE SCRIPT
#SCRIPT TESTED ON DEBIAN

#THE SCRIPT WILL:
# CREATE A NEW USER ACCOUNT WHERE VAULTWARDEN WILL BE INSTALLED
# INSTALL DOCKER IN ROOTLESS MODE
# DEPLOY VAULTWARDEN USING DOCKER COMPOSE RUNNNING WITH NON ROOT USER
# ADD A CRONJOB TO RUN VAULTWARDEN AT REBOOT

#VAULTWARDEN ACCESS WILL AT BE: https://DOMAIN
#TO SETUP A NEW DOMAIN YOU CAN FOLLOW https://www.byteninja.net/caddy-ssl-reverse-proxy/

#MODIFY IF NEEDED
VAULTWARDEN_USER_ACCOUNT="vaultwarden"
#ONLY USE PORT HIGHER THAN 1024 OR FEW MODIFICATIONS WILL BE REQUIRED
VAULTWARDEN_PORT=8081

#CHECK IF USER CAN EXECUTE SUDO COMMANDS
RESULT=$(sudo -l -U $USER)
if echo "$RESULT" | grep -q 'not allowed';then
	echo "[!] YOU ARE NOT ALLOWED TO EXECUTE SUDO COMMANDS"
	exit 1
fi

if [[ "$USER" == "$VAULTWARDEN_USER_ACCOUNT" ]];then
        echo "[!] IT'S NOT RECOMMENDED TO RUN DOCKER ROOTLESS AS PRIVILEGED USER"
fi

#INSTALL PACKAGES
echo "[+] INSTALLING REQUIRED PACKAGES"
sudo apt update
sudo apt install uidmap dbus-user-session curl -y
if ! which newuidmap &> /dev/null;then
	echo "[!] DOCKER ROOTLESS CAN NOT RUN WTHOUT THE uidmap package"
	exit 2
fi
if ! which curl &> /dev/null;then
	echo "[!] curl IS REQUIRED"
	exit 3
fi

#VARIABLES
USER_NAME=$VAULTWARDEN_USER_ACCOUNT
#CREATE USER
if ! grep $USER_NAME /etc/passwd;then
	if ! sudo adduser $USER_NAME;then
		echo "[!] $USER_NAME CAN NOT BE CREATED"
		exit 4
	fi
fi

#GENERATE THE ACCESS KEY
if [ ! -f ~/.ssh/id_rsa.pub ];then
	while true; do
		read -p "DO YOU WANT TO CREATE PRIVATE/PUBLIC KEYS FOR $USER ? (y/n)" ANSWER
		case $ANSWER in
			[Yy]* ) ssh-keygen; break;;
			[Nn]* )
				echo "[!] SSH KEYS ARE REQUIRED"
				exit 5;;
			* ) echo "PLEASE ANSWER WITH YES OR NO";;
		esac
	done
fi

#ADD THE ACCESS KEY
ID_RSA_PUB=$(cat ~/.ssh/id_rsa.pub)
USER_SSH_DIR=/home/$USER_NAME/.ssh
sudo mkdir -p $USER_SSH_DIR
[ ! -f $USER_SSH_DIR/authorized_keys ] && sudo touch $USER_SSH_DIR/authorized_keys
if ! sudo grep "$ID_RSA_PUB" $USER_SSH_DIR/authorized_keys;then
	echo "$ID_RSA_PUB" | sudo tee -a $USER_SSH_DIR/authorized_keys
fi

echo "[+] SET THE CORRECT PERMISSIONS"
sudo chown -R $USER_NAME:$USER_NAME $USER_SSH_DIR
sudo chmod 600 $USER_SSH_DIR/authorized_keys
sudo chmod 700 $USER_SSH_DIR
sudo chmod 700 /home/$USER_NAME

#TEST SSH CONNECTION
if ! ssh $USER_NAME@localhost 'id';then
	echo "[!] CAN NOT SSH TO THE USER [ $USER_NAME ]"
	exit 6
else
	echo "[+] SSH ACCESS IS READY"
fi

#INSTALLING DOCKER ROOTLESS
echo "[+] INSTALLING DOCKER ROOTLESS AS [ $USER_NAME ]"
if ! ssh $USER_NAME@localhost 'export SKIP_IPTABLES=1;curl -fsSL https://get.docker.com/rootless | sh';then
	echo "[!] DOCKER ROOTLESS INSTALL FAILED"
	exit 7
fi

if ! ssh $USER_NAME@localhost 'bin/docker &> /dev/null';then
	echo "[!] DOCKER BINARY NOT FOUND, EXECUTING THE INSTALLATION SCRIPT"
	if ! ssh $USER_NAME@localhost 'export SKIP_IPTABLES=1;curl -fsSL https://get.docker.com/rootless | sh';then
		echo "[!] DOCKER ROOTLESS INSTALL FAILED"
		exit 8
	fi
fi

#SETUP THE VARIABLES IN .BASHRC
echo "[+] CONFIGURE DOCKERD VARIABLES"
USER_BASH_RC="/home/$USER_NAME/.bashrc"
if ! sudo grep 'export PATH=/home/$USER/bin:$PATH' $USER_BASH_RC;then
	echo 'export PATH=/home/$USER/bin:$PATH' | sudo tee -a $USER_BASH_RC
fi
if ! sudo grep 'export PATH=/home/$USER/.local/bin:$PATH' $USER_BASH_RC;then
	echo 'export PATH=/home/$USER/.local/bin:$PATH' | sudo tee -a $USER_BASH_RC
fi
if ! sudo grep 'export XDG_RUNTIME_DIR=/home/$USER/.docker/run' $USER_BASH_RC;then
	echo 'export XDG_RUNTIME_DIR=/home/$USER/.docker/run' | sudo tee -a $USER_BASH_RC
fi

if ! sudo grep 'export DOCKER_HOST=unix:////run/user/`id -u`/docker.sock' $USER_BASH_RC;then
	echo 'export DOCKER_HOST=unix:////run/user/`id -u`/docker.sock' | sudo tee -a $USER_BASH_RC
fi
sudo chown  $USER_NAME:$USER_NAME $USER_BASH_RC

#ENABLE AND START DOCKER
echo "[+] ENABLE AND START DOCKER SERVICE AS [ $USER_NAME ]"
if ! ssh $USER_NAME@localhost 'systemctl --user enable docker.service';then
	echo "[!] FAILED TO ENABLE DOCKER SERVICE !"
else
	echo "[+] DOCKER SERVICE ENABLED"
fi
if ! ssh $USER_NAME@localhost 'systemctl --user start docker.service';then
	echo "[!] DOCKERD NOT STARTED CORRECTLY"
	exit 9
else
	echo "[+] DOCKERD SERVICE STARTED"
fi
if ! ssh $USER_NAME@localhost 'loginctl enable-linger $(whoami)';then
	echo "[!] DOCKER LINGER NOT ENABLED"
        exit 10
else
	echo "[+] DOCKER LINGER ENABLED"
fi

if [ `ssh $USER_NAME@localhost 'systemctl --user is-active docker.service'` == "active" ];then
	echo "[+] DOCKERD IS RUNNING"
else
	echo "[!] DOCKERD IS NOT RUNNING"
	exit 11
fi

#INSTALL DOCKER COMPOSE
echo "[+] INSTALLING DOCKER COMPOSE"
if ! ssh $USER_NAME@localhost 'mkdir -p .local/bin;curl -L "https://github.com/docker/compose/releases/download/v2.29.0/docker-compose-$(uname -s)-$(uname -m)" -o .local/bin/docker-compose;chmod +x .local/bin/docker-compose' &> /dev/null;then
	echo "[!] FAILED TO INSTALL DOCKER COMPOSE"
	exit 12
else
	echo "[+] DOCKER COMPOSE INSTALLED"
fi

#CONFIGURE DOCKER COMPOSE
echo "[+] CONFIGURE DOCKER COMPOSE"
PUID=$(id -u $USER_NAME)
PGID=$(id -g $USER_NAME)
VAULTWARDEN_DATA_PATH="/home/$USER_NAME/data"
VAULTWARDEN_LOG_PATH="/home/$USER_NAME/logs"
CONTAINER_TMP="/tmp/$USER_NAME/container-tmp"
DATA_TMP="/tmp/$USER_NAME/data-tmp"
TZ=$(sudo cat /etc/timezone)
FORCE_INSTALL=false
FRESH_INSTALL=true

if sudo test -f /home/$USER_NAME/docker-compose.yml;then
	FRESH_INSTALL=false
	while true; do
		echo "[!] THE docker-compose.yml FILE WILL BE OVERWRITTEN"
		read -p "ARE YOU SURE YOU WANT TO OVERWRITE ? (y/n)" ANSWER
		case $ANSWER in
			[Yy]* ) echo "[!] CONTINUE ANYWAY, DON'T FORGET TO RESTART THE CONTAINER AFTERWARD";FORCE_INSTALL=true;break;;
			[Nn]* )
				echo "[+] SKIPPING"
				break;;
			* ) echo "PLEASE ANSWER WITH YES OR NO";;
		esac
	done
fi

if $FRESH_INSTALL || $FORCE_INSTALL; then
	sudo cp `dirname $0`/templates/docker-compose.temp /home/$USER_NAME/docker-compose.yml
	sudo sed -i "s/PUID_TO_REPLACE/$PUID/g" /home/$USER_NAME/docker-compose.yml
	sudo sed -i "s/PGID_TO_REPLACE/$PGID/g" /home/$USER_NAME/docker-compose.yml
	sudo sed -i "s#VAULTWARDEN_DATA_PATH_TO_REPLACE#$VAULTWARDEN_DATA_PATH#g" /home/$USER_NAME/docker-compose.yml
	sudo sed -i "s#CONTAINER_TMP_TO_REPLACE#$CONTAINER_TMP#g" /home/$USER_NAME/docker-compose.yml
	sudo sed -i "s#DATA_TMP_TO_REPLACE#$DATA_TMP#g" /home/$USER_NAME/docker-compose.yml
	sudo sed -i "s#VAULTWARDEN_LOG_PATH_TO_REPLACE#$VAULTWARDEN_LOG_PATH#g" /home/$USER_NAME/docker-compose.yml
	sudo sed -i "s#TZ_TO_REPLACE#$TZ#g" /home/$USER_NAME/docker-compose.yml
	sudo sed -i "s#LOCAL_PORT_TO_REPLACE#$VAULTWARDEN_PORT#g" /home/$USER_NAME/docker-compose.yml
	sudo chown $USER_NAME:$USER_NAME /home/$USER_NAME/docker-compose.yml
fi

echo "[+] STARTING VAULTWARDEN"
if ! `ssh $USER_NAME@localhost 'export PATH=/home/$USER/bin:$PATH;export PATH=/home/$USER/.local/bin:$PATH;export XDG_RUNTIME_DIR=/home/$USER/.docker/run;export DOCKER_HOST=unix:////run/user/$(id -u)/docker.sock;bin/docker container inspect -f "{{.State.Running}}" vaultwarden &>/dev/null'`;then
	ssh $USER_NAME@localhost 'export PATH=/home/$USER/bin:$PATH;export PATH=/home/$USER/.local/bin:$PATH;export XDG_RUNTIME_DIR=/home/$USER/.docker/run;export DOCKER_HOST=unix:////run/user/$(id -u)/docker.sock; /home/$USER/.local/bin/docker-compose -f $HOME/docker-compose.yml up -d'
	sleep 30
fi

#VERIFY IF VAULTWARDEN IS RUNNING
if ! `ssh $USER_NAME@localhost 'export PATH=/home/$USER/bin:$PATH;export PATH=/home/$USER/.local/bin:$PATH;export XDG_RUNTIME_DIR=/home/$USER/.docker/run;export DOCKER_HOST=unix:////run/user/$(id -u)/docker.sock;bin/docker container inspect -f "{{.State.Running}}" vaultwarden &>/dev/null'`;then
	echo "[-] VAUTLWARDEN IS NOT RUNNING"
else
	echo "[+] VAULTWARDEN IS RUNNING"
fi

#START VAULTWARDEN @REBOOT
echo "[+] START VAULTWARDEN AT REBOOT"
if ! grep 'docker-compose up -d ' "$(sudo crontab -l -u $USER_NAME)" &> /dev/null;then
	sudo crontab -u $USER_NAME `dirname $0`/templates/vaultwarden.cron
fi
