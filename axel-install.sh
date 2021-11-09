#!/bin/bash

#
# Run/upgrade a brand new AXEL masternode in one kick
#

#
# Usage:
#     cd /root && rm -f ./axel-install.sh && wget https://raw.githubusercontent.com/axelnetwork/MN-Script/master/axel-install.sh && chmod u+x ./axel-install.sh
#     ./axel-install.sh   <-- or -->   mv /root/.axel/debug.log /root/.axel/debug.log-$(date +%y%m%d%H%M) && /root/axel-install.sh --upgrade && axel-cli -version
#

# TODO: to pass a MN private key as a param in order to prevent any manual input

COIN_NAME="AXEL"
COIN_PORT=32323
COIN_VERSION="3.1.0"
COIN_REPO="https://github.com/axelnetwork/${COIN_NAME}/releases/download/v${COIN_VERSION}/${COIN_NAME}-${COIN_VERSION}-x86_64-linux-gnu.tar.gz"
COIN_NAME_LOWER=$(echo $COIN_NAME | awk '{ print tolower($0) }')
CONFIG_FILE="${COIN_NAME_LOWER}.conf"
CONFIGFOLDER="/root/.${COIN_NAME_LOWER}"
COIN_DAEMON="/usr/local/bin/${COIN_NAME_LOWER}d"
COIN_CLI="/usr/local/bin/${COIN_NAME_LOWER}-cli"

RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"

IS_UPGRADE=$1
if [[ ${IS_UPGRADE} = "--upgrade" ]]
then
  systemctl stop $COIN_NAME.service
  sleep 3
  rm /usr/local/bin/${COIN_NAME_LOWER}*
fi


progressfilt () {
  local flag=false c count cr=$'\r' nl=$'\n'
  while IFS='' read -d '' -rn 1 c
  do
    if $flag
    then
      printf '%c' "$c"
    else
      if [[ $c != $cr && $c != $nl ]]
      then
        count=0
      else
        ((count++))
        if ((count > 1))
        then
          flag=true
        fi
      fi
    fi
  done
}

function compile_node() {
  echo -e "Prepare to download $COIN_NAME"
  TMP_FOLDER=$(mktemp -d)
  cd $TMP_FOLDER
  COIN_ZIP=$(echo $COIN_REPO | awk -F'/' '{print $NF}')
  wget -O $COIN_ZIP --progress=bar:force $COIN_REPO 2>&1 | progressfilt
  compile_error
# TODO: to enhance
  COIN_VER=$(echo $COIN_ZIP | awk -F'/' '{print $NF}' | sed -n 's/.*\([0-9]\.[0-9]\.[0-9]\).*/\1/p')
  tar xvf $COIN_ZIP >/dev/null 2>&1
  compile_error
  rm -f $COIN_ZIP >/dev/null 2>&1
  cp ./*/* /usr/local/bin
  compile_error
  cd - >/dev/null 2>&1
  rm -rf $TMP_FOLDER >/dev/null 2>&1
}


function configure_systemd() {
  cat << EOF > /etc/systemd/system/$COIN_NAME.service
[Unit]
Description=$COIN_NAME service
After=network.target

[Service]
User=root
Group=root

Type=forking
#PIDFile=$CONFIGFOLDER/$COIN_NAME.pid

ExecStart=$COIN_DAEMON -daemon -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER -forcestart -rescan
ExecStop=$COIN_CLI -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER stop

Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $COIN_NAME.service
  systemctl enable $COIN_NAME.service # >/dev/null 2>&1

  if [[ -z "$(ps axo cmd:100 | egrep $COIN_DAEMON)" ]]; then
    echo -e "${RED}$COIN_NAME is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start $COIN_NAME.service"
    echo -e "systemctl status $COIN_NAME.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}


function configure_startup() {
  cat << EOF > /etc/init.d/$COIN_NAME
#! /bin/bash
### BEGIN INIT INFO
# Provides: $COIN_NAME
# Required-Start: $remote_fs $syslog
# Required-Stop: $remote_fs $syslog
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: $COIN_NAME
# Description: This file starts and stops $COIN_NAME MN server
#
### END INIT INFO

case "\$1" in
 start)
   $COIN_DAEMON -daemon
   sleep 5
   ;;
 stop)
   $COIN_CLI stop
   ;;
 restart)
   $COIN_CLI stop
   sleep 10
   $COIN_DAEMON -daemon
   ;;
 *)
   echo "Usage: $COIN_NAME {start|stop|restart}" >&2
   exit 3
   ;;
esac
EOF
  chmod +x /etc/init.d/$COIN_NAME # >/dev/null 2>&1
  update-rc.d $COIN_NAME defaults # >/dev/null 2>&1
  /etc/init.d/$COIN_NAME start # >/dev/null 2>&1
  if [ "$?" -gt "0" ]; then
  sleep 5
  /etc/init.d/$COIN_NAME start # >/dev/null 2>&1
  fi
}


function create_config() {
  mkdir $CONFIGFOLDER # >/dev/null 2>&1
  RPCUSER=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n1)
  RPCPASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w22 | head -n1)
  cat << EOF > $CONFIGFOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
port=$COIN_PORT
EOF
}


function create_key() {
  echo -e "Enter your ${RED}$COIN_NAME Masternode Private Key:${NC}"
  read -e COINKEY
}


function update_config() {
  sed -i 's/daemon=1/daemon=0/' $CONFIGFOLDER/$CONFIG_FILE
  cat << EOF >> $CONFIGFOLDER/$CONFIG_FILE
logintimestamps=1
maxconnections=64
#bind=$NODEIP
masternode=1
externalip=$NODEIP:$COIN_PORT
masternodeprivkey=$COINKEY
EOF
}


function add_swap() {
  free -h | awk '$1 == "Swap:" && $2 == "0B" { system("fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile && cp /etc/fstab /etc/fstab.org && echo \"/swapfile none swap sw 0 0\" | tee -a /etc/fstab") }'
  free -h
}


function enable_firewall() {
  echo -e "Installing and setting up firewall to allow ingress on port ${GREEN}$COIN_PORT${NC}"
  ufw allow ssh # >/dev/null 2>&1
  ufw allow $COIN_PORT # >/dev/null 2>&1
  ufw default allow outgoing # >/dev/null 2>&1
  echo "y" | ufw enable # >/dev/null 2>&1
}


function get_ip() {
  NODEIP=$(curl -s4 icanhazip.com)
}


function compile_error() {
  if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Failed to compile $COIN_NAME. Please investigate.${NC}"
    exit 1
  fi
}


function detect_ubuntu() {
  if [[ $(lsb_release -d) == *18.04* ]]; then
    UBUNTU_VERSION=18
  elif [[ $(lsb_release -d) == *16.04* ]]; then
    UBUNTU_VERSION=16
  else
    echo -e "${RED}You are not running Ubuntu 16.04 or 18.04 -installation is cancelled.${NC}"
    exit 1
  fi
}


function checks() {
  detect_ubuntu
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}$0 must be run as root.${NC}"
    exit 1
  fi

  if [ -n "$(pidof $COIN_DAEMON)" ] || [ -e "$COIN_DAEMON" ] ; then
    echo -e "${RED}$COIN_NAME is already installed.${NC}"
    exit 1
  fi
}


function prepare_system() {
  echo -e "Prepare the system to install ${GREEN}$COIN_NAME${NC} master node."
  sudo add-apt-repository -y ppa:bitcoin/bitcoin
  apt-get update # >/dev/null 2>&1
  apt-get install -y wget curl ufw binutils net-tools mc libdb4.8-dev libdb4.8++-dev libboost-all-dev libzmq3-dev libminiupnpc-dev # >/dev/null 2>&1
}


function important_information() {
  echo
  echo -e "================================================================================"
  echo -e "$COIN_NAME Masternode is up and running listening on port ${RED}$COIN_PORT${NC}."
  echo -e "Configuration file is: ${RED}$CONFIGFOLDER/$CONFIG_FILE${NC}"
  if (( $UBUNTU_VERSION == 16 || $UBUNTU_VERSION == 18 )); then
    echo -e "Start: ${RED}systemctl start $COIN_NAME.service${NC}"
    echo -e "Stop: ${RED}systemctl stop $COIN_NAME.service${NC}"
    echo -e "Status: ${RED}systemctl status $COIN_NAME.service${NC}"
  else
    echo -e "Start: ${RED}/etc/init.d/$COIN_NAME start${NC}"
    echo -e "Stop: ${RED}/etc/init.d/$COIN_NAME stop${NC}"
    echo -e "Status: ${RED}/etc/init.d/$COIN_NAME status${NC}"
  fi
  echo -e "VPS_IP:PORT ${RED}$NODEIP:$COIN_PORT${NC}"
  echo -e "MASTERNODE PRIVATEKEY is: ${RED}$COINKEY${NC}"
  if [[ -n $SENTINEL_REPO  ]]; then
  echo -e "${RED}Sentinel${NC} is installed in ${RED}$CONFIGFOLDER/sentinel${NC}"
  echo -e "Sentinel logs is: ${RED}$CONFIGFOLDER/sentinel.log${NC}"
  fi
  echo -e "Check if $COIN_NAME is running by using the following command:\n${RED}ps -ef | grep $COIN_DAEMON ${NC}"
  echo -e "================================================================================"
}


function setup_node() {
  if [[ ${IS_UPGRADE} != "--upgrade" ]]
  then
    get_ip
    create_config
    create_key
    update_config
    enable_firewall
    add_swap
  fi
  important_information
  if [[ ${IS_UPGRADE} = "--upgrade" ]]
  then
    systemctl start $COIN_NAME.service
  else
    if (( $UBUNTU_VERSION == 16 || $UBUNTU_VERSION == 18 )); then
      configure_systemd
    else
      configure_startup
    fi
  fi
}


checks
prepare_system
compile_node
setup_node
