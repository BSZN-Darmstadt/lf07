#!/bin/bash
#
# Copyright 2016,2024 JS Foundation and other contributors, https://js.foundation/
# Copyright 2015,2016 IBM Corp.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Node-RED Installer for DEB based systems

umask 0022
tgta12=12.22.12  # need armv6l latest from https://unofficial-builds.nodejs.org/download/release/
tgtl12=12.16.3   # need x86 latest from https://unofficial-builds.nodejs.org/download/release/
tgta14=14.21.3   # need armv6l latest from https://unofficial-builds.nodejs.org/download/release/
tgtl14=14.21.3   # need x86 latest from https://unofficial-builds.nodejs.org/download/release/
tgta16=16.20.2   # need armv6l latest from https://unofficial-builds.nodejs.org/download/release/
tgtl16=16.20.2   # need x86 latest from https://unofficial-builds.nodejs.org/download/release/
tgta18=18.20.4   # need armv6l latest from https://unofficial-builds.nodejs.org/download/release/
tgtl18=18.20.4   # need x86 latest from https://unofficial-builds.nodejs.org/download/release/
tgta20=20.18.0   # need armv6l latest from https://unofficial-builds.nodejs.org/download/release/
tgtl20=20.18.0   # need x86 latest from https://unofficial-builds.nodejs.org/download/release/

usage() {
  cat << EOL
Usage: $0 [options]

Options:
  --help            display this help and exit
  --confirm-root    install as root without asking confirmation
  --confirm-install confirm installation without asking confirmation
  --confirm-pi      confirm installation of PI specific nodes without asking confirmation
  --skip-pi         skip installing PI specific nodes without asking confirmation
  --restart         restart service if install succeeds
  --allow-low-ports add capability to bind to ports below 1024 (default is disallow)
  --update-nodes    run npm update on existing installed nodes (within scope of package.json)
  --no-init         don't ask to initialise settings if they don't exist
  --nodered-user    specify the user to run as, useful for installing as sudo - e.g. --nodered-user=pi
  --nodered-version if not set, the latest version is used - e.g. --nodered-version="4.0.2"
  --node16          if set, forces install of major version of nodejs 16 LTS
  --node18          if set, forces install of major version of nodejs 18 LTS
  --node20          if set, forces install of major version of nodejs 20 LTS
                    if none set, install nodejs 20 LTS if nodejs version is less than 18,
                    otherwise leave current install

Note: if you use allow-low-ports it may affect the node modules paths - see https://stackoverflow.com/a/65560687
EOL
}

SUDO=sudo
SUDOE="sudo -E"
NODE_VERSION=""
LOW_PORTS="n"
if [ $# -gt 0 ]; then
  # Parsing parameters
  while (( "$#" )); do
    case "$1" in
      --help)
        usage && exit 0
        shift
        ;;
      --confirm-root)
        CONFIRM_ROOT="y"
        shift
        ;;
      --confirm-install)
        CONFIRM_INSTALL="y"
        shift
        ;;
      --skip-pi)
        CONFIRM_PI="n"
        shift
        ;;
      --confirm-pi)
        CONFIRM_PI="y"
        shift
        ;;
      --node12)
        NODE_VERSION="12"
        shift
        ;;
      --node14)
        NODE_VERSION="14"
        shift
        ;;
      --node16)
        NODE_VERSION="16"
        shift
        ;;
      --node18)
        NODE_VERSION="18"
        shift
        ;;
      --node20)
        NODE_VERSION="20"
        shift
        ;;
      --node22)
        NODE_VERSION="22"
        shift
        ;;
      --restart)
        RESTART="y"
        shift
        ;;
      --update-nodes)
        UPDATENODES="y"
        shift
        ;;
      --nodered-version=*)
        NODERED_VERSION="${1#*=}"
        shift
        ;;
      --nodered-user=*)
        NODERED_USER="${1#*=}"
        shift
        ;;
      --allow-low-ports)
        LOW_PORTS="y"
        shift
        ;;
      --no-init)
        INITSET="n"
        shift
        ;;
      --) # end argument parsing
        shift
        break
        ;;
      -*|--*=) # unsupported flags
        echo "Error: Unsupported flag $1" >&2
        exit 1
        ;;
    esac
  done
fi

# helper function to test for existance of node and npm
function HAS_NODE {
    if [ -x "$(command -v node)" ]; then return 0; else return 1; fi
}
function HAS_NPM {
    if [ -x "$(command -v npm)" ]; then return 0; else return 1; fi
}

# check for apt and systemctrl (set flags for later use and log if not found)
if [ -x "$(command -v apt)" ]; then
    APTOK=true;
else
    APTOK=false
    echo "apt not found. Node/npm install will be skipped" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
fi
if [ -x "$(command -v systemctl)" ]; then
    SYSTEMDOK=true;
else
    SYSTEMDOK=false
    echo "systemctl not found. shortcuts/services setup will be skipped" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
fi

echo -ne "\033[2 q"
if [[ -e /mnt/dietpi_userdata ]]; then
    echo -ne "\n\033[1;32mDiet-Pi\033[0m detected - only going to add the  \033[0;36mnode-red-start, -stop, -log\033[0m  commands.\n"
    echo -ne "Flow files and other things worth backing up can be found in the \033[0;36m/mnt/dietpi_userdata/node-red\033[0m directory.\n\n"
    echo -ne "Use the  \033[0;36mdietpi-software\033[0m  command to un-install and re-install \033[38;5;88mNode-RED\033[0m.\n"
    echo "journalctl -f -n 100 -u node-red -o cat" > /usr/bin/node-red-log
    chmod +x /usr/bin/node-red-log
    echo "systemctl stop node-red" > /usr/bin/node-red-stop
    chmod +x /usr/bin/node-red-stop
    echo "systemctl start node-red" > /usr/bin/node-red-start
    echo "journalctl -f -n 0 -u node-red -o cat" >> /usr/bin/node-red-start
    chmod +x /usr/bin/node-red-start
else

if [ "$EUID" == "0" ]; then
# if [[ $SUDO_USER != "" ]]; then
  echo -en "\nroot user detected. Typical installs should be done as a regular user.\r\n"
  echo -en "If you are running this script using sudo, please cancel and rerun without sudo.\r\n"
  echo -en "--nodered-user can be used to specify the user otherwise installation will happen under /root.\r\n"
  echo -en "If you know what you are doing as root, please continue.\r\n\r\n"

  yn="${CONFIRM_ROOT}"
  [ ! "${yn}" ] && read -t 10 -p "Are you really sure you want to install as root ? (y/N) ? " yn
  case $yn in
    [Yy]* )
    ;;
    * )
      echo " "
      exit 1
    ;;
  esac
  SUDO=''
  SUDOE=''
  id -u nobody &>/dev/null || adduser --no-create-home --shell /dev/null --disabled-password --disabled-login --gecos '' nobody &>/dev/null
else
    groups "$USER" | grep -q '\bsudo\b' && GRS="Y" || GRS="N"
    if [[ "$GRS" == "N" ]]; then
        echo "User $USER not in sudoers group. Exiting"
        exit 1;
    fi
fi

# setup user, home and group
if [[ "$NODERED_USER" == "" ]]; then
    NODERED_HOME=$HOME
    NODERED_USER=$USER
    NODERED_GROUP=`id -gn`
else
    NODERED_GROUP="$NODERED_USER"
    NODERED_HOME="/home/$NODERED_USER"
    if [[ "$NODERED_USER" == "root" ]]; then
        NODERED_HOME="/root"
    fi
fi
SUDOU="sudo -u $NODERED_USER"

if [[ "$(uname)" != "Darwin" ]]; then
if curl -I https://registry.npmjs.org/@node-red/util  >/dev/null 2>&1; then
echo -e '\033]2;'$NODERED_USER@`hostname`:  Node-RED update'\007'
echo " "
echo "******************************************"
echo "*      Node-RED Installer by BSZN       *"
echo "*           Version 1.3.0               *"
echo "******************************************"
echo " "
echo "This script checks the version of node.js installed is 16 or greater. It will try to"
echo "install node 20 if none is found. It can optionally install node 18 or 20 LTS for you."
echo " "
echo "If necessary it will then remove the old core of Node-RED, before then installing the latest"
echo "version. You can also optionally specify the version required."
echo " "
echo "It also tries to run 'npm rebuild' to refresh any extra nodes you have installed"
echo "that may have a native binary component. While this normally works ok, you need"
echo "to check that it succeeds for your combination of installed nodes."
echo " "
echo "Note: PT-Miniscreen will be automatically re-enabled at the end of the process"
echo "      to ensure your display continues to work properly."
echo " "
echo "To do all this it runs commands as root - please satisfy yourself that this will"
echo "not damage your Pi, or otherwise compromise your configuration."
echo "If in doubt please backup your SD card first."
echo " "
echo "See the optional parameters by re-running this command with --help"
echo " "
if [[ -e $NODERED_HOME/.nvm ]]; then
    echo -ne '\033[1mNOTE:\033[0m We notice you are using \033[38;5;88mnvm\033[0m. Please ensure it is running the current LTS version.\n'
    echo -ne 'Using nvm is NOT RECOMMENDED. Node-RED will not run as a service under nvm.\r\n\n'
fi

yn="${CONFIRM_INSTALL}"
[ ! "${yn}" ] && read -p "Are you really sure you want to do this ? [y/N] ? " yn
case $yn in
    [Yy]* )
        echo ""
        EXTRANODES=""
        EXTRAW="update"

        response="${CONFIRM_PI}"
        [ ! "${response}" ] && read -r -t 15 -p "Would you like to install the Pi-specific nodes ? [y/N] ? " response
        if [[ "$response" =~ ^([yY])+$ ]]; then
            EXTRANODES="node-red-node-pi-gpio@latest node-red-node-random@latest node-red-node-ping@latest node-red-contrib-play-audio@latest node-red-node-smooth@latest node-red-node-serialport@latest node-red-contrib-buffer-parser@latest"
            EXTRAW="install"
        fi

        # this script assumes that $HOME is the folder of the user that runs node-red
        # that $NODERED_USER is the user name and the group name to use when running is the
        # primary group of that user
        # if this is not correct then edit the lines below
        MYOS=$(cat /etc/os-release | grep "^ID=" | cut -d = -f 2 | tr -d '"')
        GLOBAL="true"
        TICK='\033[1;32m\u2714\033[0m'
        CROSS='\033[1;31m\u2718\033[0m'
        cd "$NODERED_HOME" || exit 1
        clear
        echo -e "\nRunning Node-RED $EXTRAW for user $NODERED_USER at $NODERED_HOME on $MYOS\n"

        nv=0
        # nv2=""
        nv2=`dpkg -s nodejs 2>/dev/null | grep Version | cut -d ' ' -f 2`
        nrv=`echo $NODERED_VERSION | cut -d "." -f1`

        if [[ "$APTOK" == "false" ]]; then
            if HAS_NODE && HAS_NPM; then
                : # node and npm is installed, we can continue :)
            else
                if HAS_NODE; then :; else echo -en "\b$CROSS   MISSING: nodejs\r\n"; fi
                if HAS_NPM; then :; else echo -en "\b$CROSS   MISSING: npm\r\n"; fi
                echo -en "\b$CROSS   MISSING: apt"
                echo -e "\r\n\r\nThis script uses apt to install nodejs and npm.\n"
                echo -e "You can install nodejs and npm manually then run the script again to continue.\r\n\r\n"
                exit 2
            fi
        fi

        if [[ "$APTOK" == "true" ]]; then
            ndeb=$(apt-cache policy nodejs | grep Installed | awk '{print $2}')
        fi
        if HAS_NODE && HAS_NPM; then
            nv=`node -v | cut -d "." -f1 | cut -d "v" -f2`
            nvs=`node -v | cut -d "." -f2`
            # nv2=`node -v`
            # nv2=`apt list nodejs 2>/dev/null | grep dfsg | cut -d ' ' -f 2 | cut -d '-' -f 1`
            echo "Already have nodejs $nv2" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        fi
        # ensure ~/.config dir is owned by the user
        $SUDO chown -Rf $NODERED_USER:$NODERED_GROUP $NODERED_HOME/.config/

        echo "OLD nodejs "$nv" :" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        echo "NEW nodejs "$NODE_VERSION" :" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        # If older than version of 12.17 then force it to update to support es modules
        if [[ "$nv" -eq 12 && "$nvs" -lt 17 ]]; then
            nv=0
            NODE_VERSION="12"
        fi

        if [[ "$nv" -lt 18 && "$nv" -ne 0  && "$nrv" != 1 ]]; then
            if [[ "$NODE_VERSION" == "" ]]; then
                echo "Detected Node.js $nv - updating to Node.js 20 LTS" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                NODE_VERSION="20"
                # Statt Beendigung fortfahren mit Node.js 20
                echo -ne "  Installing Node.js 20 LTS            \r"
            fi
        fi

        time1=$(date)
        echo "" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        echo "***************************************" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        echo "" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        echo "Started : "$time1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        echo "Running for user $NODERED_USER at $NODERED_HOME" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        echo -ne '\r\nThis can take 20-30 minutes on the slower Pi versions - please wait.\r\n\n'
        echo -ne '  Stop Node-RED                       \r\n'
        echo -ne '  Remove old version of Node-RED      \r\n'
        echo -ne '  Remove old version of Node.js       \r\n'
        echo -ne '  Install Node.js                     \r\n'
        echo -ne '  Clean npm cache                     \r\n'
        echo -ne '  Install Node-RED core               \r\n'
        echo -ne '  Move global nodes to local          \r\n'
        echo -ne '  Npm rebuild existing nodes          \r\n'
        echo -ne '  Install extra Pi nodes              \r\n'
        echo -ne '  Add shortcut commands               \r\n'
        echo -ne '  Update systemd script               \r\n'
        echo -ne '  Mark PT dependencies               \r\n'
        echo -ne '  Re-enable PT-Miniscreen            \r\n'
        echo -ne '  Installing PT device support          \r\n'
        echo -ne '                                      \r\n'
        echo -ne '\r\nAny errors will be logged to   /var/log/nodered-install.log\r\n'
        echo -ne '\033[14A'

        # stop any running node-red service
        if $SUDO service nodered stop 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null ; then CHAR=$TICK; else CHAR=$CROSS; fi
        echo -ne "  Stop Node-RED                       $CHAR\r\n"

        # save any global nodes
        GLOBALNODES=$(find /usr/local/lib/node_modules/node-red-* -maxdepth 0 -type d -printf '%f\n' 2>/dev/null)
        GLOBALNODES="$GLOBALNODES $(find /usr/lib/node_modules/node-red-* -maxdepth 0 -type d -printf '%f\n' 2>/dev/null)"
        echo "Found global nodes: $GLOBALNODES :" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null

        # remove any old node-red installs or files
        if [[ "$APTOK" == "true" ]]; then
            $SUDO apt remove -y nodered 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        fi
        # sudo apt remove -y node-red-update 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        $SUDO rm -rf /usr/local/lib/node_modules/node-red* /usr/local/lib/node_modules/npm /usr/local/bin/node-red* /usr/local/bin/node /usr/local/bin/npm 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        $SUDO rm -rf /usr/lib/node_modules/node-red* /usr/bin/node-red* 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        echo -ne '  Remove old version of Node-RED      \033[1;32m\u2714\033[0m\r\n'

        if [[ "$APTOK" == "false" ]]; then
            echo -ne "  Node option not possible            :   Skipped - apt not found\n"
            echo -ne "  Leave existing Node.js              :"
        elif [[ "$NODE_VERSION" == "" && "$nv" -ne 0 ]]; then
            CHAR="-"
            echo -ne "  Node option not specified           :   --node18 or --node20\n"
            echo -ne "  Leave existing Node.js              :"
        else
            if [[ "$NODE_VERSION" == "12" ]]; then
                tgtl=$tgtl12
                tgta=$tgta12
            elif [[ "$NODE_VERSION" == "14" ]]; then
                tgtl=$tgtl14
                tgta=$tgta14
            elif [[ "$NODE_VERSION" == "16" ]]; then
                tgtl=$tgtl16
                tgta=$tgta16
            elif [[ "$NODE_VERSION" == "18" ]]; then
                tgtl=$tgtl18
                tgta=$tgta18
            elif [[ "$NODE_VERSION" == "20" ]]; then
                tgtl=$tgtl20
                tgta=$tgta20
            elif [[ "$NODE_VERSION" == "22" ]]; then
                tgtl="None"
                tgta="None"
            else
                tgtl=$tgtl20
                tgta=$tgta20
                NODE_VERSION="20"
            fi
            # maybe remove Node.js - or upgrade if nodesource.list exists
            if [[ -d $NODERED_HOME/.nvm ]]; then
                GLOBAL="false"
                echo -ne '  Using NVM to manage Node.js         +   please run   \033[0;36mnvm use lts\033[0m   before running Node-RED\r\n'
                echo -ne '  NOTE: Using nvm is NOT RECOMMENDED.     Node-RED will not run as a service under nvm.\r\n'
                export NVM_DIR=$NODERED_HOME/.nvm
                [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
                echo "Using NVM !!! $(nvm current)" 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                nvm install $NODE_VERSION --no-progress --latest-npm >/dev/null 2>&1
                nvm use $NODE_VERSION >/dev/null 2>&1
                nvm alias default $NODE_VERSION >/dev/null 2>&1
                echo "Now using --- $(nvm current)" 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                ln -f -s $NODERED_HOME/.nvm/versions/node/$(nvm current)/lib/node_modules/node-red/red.js  $NODERED_HOME/node-red
                echo -ne "  Update Node.js $NODE_VERSION                   $CHAR"
            elif [[ $(which n) ]]; then
                echo "Using n" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                echo -ne "  Using N to manage Node.js           +\r\n"
                if $SUDO n $NODE_VERSION 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
                echo -ne "  Update Node.js $NODE_VERSION                   $CHAR"
            elif [[ "$(uname -m)" =~ "i686" ]] || [[ "$(uname -m)" =~ "x86_64" && "$(getconf LONG_BIT)" =~ "32" ]]; then
                echo "Using 32bit nodejs" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                if [[ "$tgtl" != "None" ]]; then
                    curl -sSL -o /tmp/node.tgz https://unofficial-builds.nodejs.org/download/release/v$tgtl/node-v$tgtl-linux-x86.tar.gz 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                    # unpack it into the correct places
                    hd=$(head -c 9 /tmp/node.tgz)
                    if [ "$hd" == "<!DOCT" ] || [ "$hd" == "<html>" ]; then
                        CHAR="$CROSS File $f not downloaded";
                    else
                        if [[ -d /tmp/nodejs ]]; then
                            $SUDO rm -rf /tmp/nodejs
                        fi
                        mkdir -p /tmp/nodejs
                        $SUDO tar -zxof /tmp/node.tgz --strip-components=1 -C /tmp/nodejs
                        $SUDO chown -R 0:0 /tmp/nodejs 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                        if $SUDO cp -PR /tmp/nodejs/* /usr/ 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
                        $SUDO rm -rf /tmp/nodejs 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                    fi
                    rm /tmp/node.tgz 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                    echo -ne "  Install Node.js for i686            $CHAR"
                else
                    echo -ne "  Nodejs "$tgtl" for i686 does not exist   $CROSS"
                fi
            elif uname -m | grep -q armv6l ; then
                if [[ "$tgta" != "None" ]]; then
                    $SUDO apt remove -y nodejs nodejs-legacy npm 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                    $SUDO rm -rf /etc/apt/sources.d/nodesource.list /usr/lib/node_modules/npm*
                    echo -ne "  Remove old version of Node.js       $TICK   $nv2\r\n"
                    echo -ne "  Install Node.js for Armv6           \r"
                    # f=$(curl -sL https://nodejs.org/download/release/latest-dubnium/ | grep "armv6l.tar.gz" | cut -d '"' -f 2)
                    # curl -sL -o node.tgz https://nodejs.org/download/release/latest-dubnium/$f 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                    curl -sSL -o /tmp/node.tgz https://unofficial-builds.nodejs.org/download/release/v$tgta/node-v$tgta-linux-armv6l.tar.gz 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                    # unpack it into the correct places
                    hd=$(head -c 6 /tmp/node.tgz)
                    if [ "$hd" == "<!DOCT" ] || [ "$hd" == "<html>" ]; then
                        CHAR="$CROSS File $f not downloaded";
                    else
                        if [[ -d /tmp/nodejs ]]; then
                            $SUDO rm -rf /tmp/nodejs
                        fi
                        mkdir -p /tmp/nodejs
                        $SUDO tar -zxof /tmp/node.tgz --strip-components=1 -C /tmp/nodejs
                        $SUDO chown -R 0:0 /tmp/nodejs 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                        if $SUDO cp -PR /tmp/nodejs/* /usr/ 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
                        $SUDO rm -rf /tmp/nodejs 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                    fi
                    # remove the tgz file to save space
                    rm /tmp/node.tgz 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                    echo -ne "  Install Node.js for Armv6           $CHAR"
                else
                    echo -ne "  Nodejs "$tgta" for Armv6 does not exist  $CROSS"
                fi
            else
                echo "Installing nodejs $NODE_VERSION" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                # clean out old nodejs stuff
                npv=$(npm -v 2>/dev/null | head -n 1 | cut -d "." -f1)
                $SUDO apt-mark manual pt-miniscreen
                $SUDO apt remove -y nodejs nodejs-legacy npm 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                $SUDO dpkg -r nodejs 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                $SUDO dpkg -r node 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                $SUDO rm -rf /opt/nodejs 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                $SUDO rm -rf /usr/local/lib/nodejs* 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                $SUDO rm -f /usr/local/bin/node* 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                $SUDO rm -rf /usr/local/bin/npm* /usr/local/bin/npx* /usr/lib/node_modules/npm* 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                if [ "$npv" = "1" ]; then
                    $SUDO rm -rf /usr/local/lib/node_modules/node-red* /usr/lib/node_modules/node-red* 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                fi
                $SUDO apt -y autoremove 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                $SUDO rm -rf /etc/apt/sources.list.d/nodesource.list 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                $SUDO rm -rf /etc/apt/keyrings/nodesource.gpg 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                echo -ne "  Remove old version of Node.js       \033[1;32m\u2714\033[0m   $nv2\r\n"
                echo "Grab the LTS bundle" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                echo -ne "  Install Node.js $NODE_VERSION LTS              \r"

                # block debian nodejs install
                echo "Package: nodejs" | $SUDO tee /etc/apt/preferences.d/nodejs.pref >>/dev/null
                echo "Pin: release a=stable-security" | $SUDO tee -a /etc/apt/preferences.d/nodejs.pref >>/dev/null
                echo "Pin-Priority: -1" | $SUDO tee -a /etc/apt/preferences.d/nodejs.pref >>/dev/null

                # use the official script to install for other debian platforms
                $SUDO apt install -y ca-certificates curl gnupg 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                $SUDO mkdir -p /etc/apt/keyrings 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | $SUDOE gpg --batch --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                # curl -sSL https://deb.nodesource.com/setup_$NODE_VERSION.x | $SUDOE bash - 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_VERSION.x nodistro main" | $SUDOE tee -a /etc/apt/sources.list.d/nodesource.list >>/dev/null
                $SUDO apt-get update 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                if $SUDO apt install -y nodejs 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
                nov2=$(dpkg -s nodejs | grep Version | cut -d ' ' -f 2)
                echo -ne "  Install Node $nov2   $CHAR"
                # echo -ne "  Install Node.js $NODE_VERSION LTS              $CHAR"
            fi
        fi

        NUPG=$CHAR
        hash -r
        rc=""
        if nov=$(node -v 2>/dev/null); then :; else rc="ERR"; fi
        if npv=$(npm -v 2>/dev/null); then :; else rc="ERR"; fi
        if [[ "$npv" == "" ]]; then npv="missing"; fi
        if [[ "$nov" == "" ]]; then nov="missing"; fi

        echo -ne "\nVersions: node:$nov npm:$npv\n" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        if [[ "$rc" == "" ]]; then
            echo -ne "   $nov   Npm $npv\r\n"
        else
            echo -ne "\b$CROSS   Bad install:  Node.js $nov  Npm $npv - Exit\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n"
            exit 2
        fi
        if [ "$EUID" == "0" ]; then npm config set unsafe-perm true &>/dev/null; fi

        # clean up the npm cache and node-gyp
        if [[ "$NUPG" == "$TICK" ]]; then
            if [[ "$GLOBAL" == "true" ]]; then
                $SUDO npm cache clean --force 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
            else
                npm cache clean --force 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
            fi
            if $SUDO rm -rf "$NODERED_HOME/.node-gyp" "$NODERED_HOME/.npm" /root/.node-gyp /root/.npm; then CHAR=$TICK; else CHAR=$CROSS; fi
        fi
        echo -ne "  Clean npm cache                     $CHAR\r\n"

        # and install Node-RED
        echo "Now install Node-RED $NODERED_VERSION" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null

        NODERED_VERSION_SELECTION=""
        if [ -z ${NODERED_VERSION} ]; then
            NODERED_VERSION_SELECTION="latest"
        else
            NODERED_VERSION_SELECTION=${NODERED_VERSION}
        fi

        if [[ "$GLOBAL" == "true" ]]; then
            $SUDO npm i -g --unsafe-perm --no-progress --no-update-notifier --no-audit --no-fund --loglevel=error node-red@"$NODERED_VERSION_SELECTION" 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null; nri=${PIPESTATUS[0]}
            if [[ $nri -eq 0 ]]; then CHAR=$TICK; else CHAR=$CROSS; fi
        else
            npm i -g --unsafe-perm --no-progress --no-update-notifier --no-audit --no-fund --loglevel=error node-red@"$NODERED_VERSION_SELECTION" 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null; nri=${PIPESTATUS[0]}
            if [[ $nri -eq 0 ]]; then CHAR=$TICK; else CHAR=$CROSS; fi
        fi
        nrv=$(npm -g --no-progress --no-update-notifier --no-audit --no-fund --loglevel=error ls node-red | grep node-red | cut -d '@' -f 2 | $SUDO tee -a /var/log/nodered-install.log) >>/dev/null 2>&1
        echo -ne "  Install Node-RED core               $CHAR   $nrv\r\n"

        # install any nodes, that were installed globally, as local instead
        echo "Now create basic package.json for the user and move any global nodes" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        mkdir -p "$NODERED_HOME/.node-red/node_modules"
        $SUDO chown $NODERED_USER:$NODERED_GROUP $NODERED_HOME/.node-red 2>&1 >>/dev/null
        $SUDO chown -Rf $NODERED_USER:$NODERED_GROUP $NODERED_HOME/.node-red/node_modules 2>&1 >>/dev/null
        # Make it more secure by making settings owned by root and removing nopasswd file for default user.
        # $SUDO chown -Rf 0:0 $NODERED_HOME/.node-red/settings.js 2>&1 >>/dev/null
        # $SUDO rm -f /etc/sudoers.d/010_pi-nopasswd
        pushd "$NODERED_HOME/.node-red" 2>&1 >>/dev/null
            npm config set update-notifier false 2>&1 >>/dev/null
            # npm config set color false 2>&1 >>/dev/null
            if [ ! -f "package.json" ]; then
                echo '{' > package.json
                echo '  "name": "node-red-project",' >> package.json
                echo '  "description": "initially created for you by Node-RED '$nrv'",' >> package.json
                echo '  "version": "0.0.1",' >> package.json
                echo '  "private": true,' >> package.json
                echo '  "dependencies": {' >> package.json
                echo '  }' >> package.json
                echo '}' >> package.json
            fi
            CHAR="-"
            if [[ $GLOBALNODES != " " ]]; then
                if npm i --unsafe-perm --save --no-progress --no-update-notifier --no-audit --no-fund $GLOBALNODES 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
            fi
            echo -ne "  Move global nodes to local          $CHAR\r\n"

            # try to rebuild any already installed nodes
            CHAR="-"
            if [[ "$NUPG" == "$TICK" ]]; then
                echo -ne "Running npm rebuild\r\n" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                if npm rebuild --no-progress --no-update-notifier --no-fund 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
                echo -ne "  Npm rebuild existing nodes          $CHAR\r"
            else
                echo -ne "  Leave existing nodes                -\r"
            fi
            if [[ "$UPDATENODES" == "y" ]]; then
                echo -ne "Running npm update\r\n" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                echo -ne "  Npm update existing nodes           "
                if npm update --no-progress --no-update-notifier --no-fund 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
                echo -ne "$CHAR\r"
            fi
            echo -ne "\n"

            CHAR="-"
            if [[ ! -z $EXTRANODES ]]; then
                echo "Installing extra nodes: $EXTRANODES :" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                if npm i --unsafe-perm --save --no-progress --no-update-notifier --no-audit --no-fund $EXTRANODES 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
            fi
            echo -ne "  Install extra Pi nodes              $CHAR\r\n"

            # If armv6 then remove the bcrypt binary to workaround illegal instruction error
            if uname -m | grep -q armv6l ; then
                $SUDO rm -rf /usr/lib/node_modules/node-red/node_modules/@node-rs | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
            fi

        popd 2>&1 >>/dev/null
        if [ -d "$NODERED_HOME/.npm" ]; then
            $SUDO chown -Rf $NODERED_USER:$NODERED_GROUP $NODERED_HOME/.npm 2>&1 >>/dev/null
        fi

        if [[ "$SYSTEMDOK" == "true" ]]; then
            # add the shortcut and start/stop/log scripts to the menu
            echo "Now add the shortcut and start/stop/log scripts to the menu" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
            $SUDO mkdir -p /usr/bin
            if $SUDO curl -m 60 -f https://raw.githubusercontent.com/node-red/linux-installers/master/resources/node-red-icon.svg >/dev/null 2>&1; then
                $SUDO curl -sL -m 60 -o /usr/bin/node-red-start https://raw.githubusercontent.com/node-red/linux-installers/master/resources/node-red-start 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                $SUDO curl -sL -m 60 -o /usr/bin/node-red-stop https://raw.githubusercontent.com/node-red/linux-installers/master/resources/node-red-stop 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                $SUDO curl -sL -m 60 -o /usr/bin/node-red-restart https://raw.githubusercontent.com/node-red/linux-installers/master/resources/node-red-restart 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                $SUDO curl -sL -m 60 -o /usr/bin/node-red-reload https://raw.githubusercontent.com/node-red/linux-installers/master/resources/node-red-reload 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                $SUDO curl -sL -m 60 -o /usr/bin/node-red-log https://raw.githubusercontent.com/node-red/linux-installers/master/resources/node-red-log 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                $SUDO curl -sL -m 60 -o /etc/logrotate.d/nodered https://raw.githubusercontent.com/node-red/linux-installers/master/resources/nodered.rotate 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                $SUDO chmod +x /usr/bin/node-red-start
                $SUDO chmod +x /usr/bin/node-red-stop
                $SUDO chmod +x /usr/bin/node-red-restart
                $SUDO chmod +x /usr/bin/node-red-reload
                $SUDO chmod +x /usr/bin/node-red-log
                $SUDO curl -sL -m 60 -o /usr/share/icons/hicolor/scalable/apps/node-red-icon.svg https://raw.githubusercontent.com/node-red/linux-installers/master/resources/node-red-icon.svg 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                $SUDO curl -sL -m 60 -o /usr/share/applications/Node-RED.desktop https://raw.githubusercontent.com/node-red/linux-installers/master/resources/Node-RED.desktop 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                echo -ne "  Add shortcut commands               $TICK\r\n"
            else
                echo -ne "  Add shortcut commands               $CROSS\r\n"
            fi

            # add systemd script and configure it for $NODERED_USER
            echo "Now add systemd script and configure it for $NODERED_USER:$NODERED_GROUP @ $NODERED_HOME" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null

            # check if systemd script already exists
            SYSTEMDFILE="/lib/systemd/system/nodered.service"

            if $SUDO curl -sL -m 60 -o ${SYSTEMDFILE}.temp https://raw.githubusercontent.com/node-red/linux-installers/master/resources/nodered.service 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null; then CHAR=$TICK; else CHAR=$CROSS; fi
            # set the memory, User Group and WorkingDirectory in nodered.service
            if [ $(cat /proc/meminfo | grep MemTotal | cut -d ":" -f 2 | cut -d "k" -f 1 | xargs) -lt 894000 ]; then mem="256"; else mem="512"; fi
            if [ $(cat /proc/meminfo | grep MemTotal | cut -d ":" -f 2 | cut -d "k" -f 1 | xargs) -gt 1894000 ]; then mem="1024"; fi
            if [ $(cat /proc/meminfo | grep MemTotal | cut -d ":" -f 2 | cut -d "k" -f 1 | xargs) -gt 3894000 ]; then mem="2048"; fi

            $SUDO sed -i 's#=512#='$mem'#;' ${SYSTEMDFILE}.temp
            $SUDO sed -i 's#^User=.*#User='$NODERED_USER'#;s#^Group=.*#Group='$NODERED_GROUP'#;s#^WorkingDirectory=.*#WorkingDirectory='$NODERED_HOME'#;s#^EnvironmentFile=-.*#EnvironmentFile=-'$NODERED_HOME'/.node-red/environment#;' ${SYSTEMDFILE}.temp

            if test -f "$SYSTEMDFILE"; then
                # there's already a systemd script
                EXISTING_FILE=$(md5sum $SYSTEMDFILE | awk '$1 "${SYSTEMDFILE}" {print $1}');
                TEMP_FILE=$(md5sum ${SYSTEMDFILE}.temp | awk '$1 "${SYSTEMDFILE}.temp" {print $1}');

                if [[ $EXISTING_FILE == $TEMP_FILE ]];
                then
                    : # silent procedure
                else
                    echo "Customized systemd script found @ $SYSTEMDFILE. To prevent loss of modifications, we'll not recreate the systemd script." | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                    echo "If you want the installer to recreate the systemd script, please delete or rename the current script & re-run the installer." | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                    CHAR="-   Skipped - existing script is customized."
                fi
                $SUDO rm ${SYSTEMDFILE}.temp
            else
                $SUDO mv ${SYSTEMDFILE}.temp $SYSTEMDFILE
            fi

            $SUDO systemctl daemon-reload 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
            echo -ne "  Update systemd script               $CHAR\r\n"
        else
            echo -ne "  Add shortcut commands               :   Skipped - systemd not found\r\n"
            echo -ne "  Update systemd script               :   Skipped - systemd not found\r\n"
        fi
        $SUDO ln -s $(which python3) /usr/bin/python 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null

        # remove unneeded large sentiment library to save space and load time
        $SUDO rm -f /usr/lib/node_modules/node-red/node_modules/multilang-sentiment/build/output/build-all.json 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        # on LXDE add launcher to top bar, refresh desktop menu
        pfile=/home/$NODERED_USER/.config/lxpanel/LXDE-pi/panels/panel
        if [ -e $pfile ]; then
            if ! grep -q "Node-RED" $pfile; then
                mat="lxterminal.desktop"
                ins="lxterminal.desktop\n    }\n    Button {\n      id=Node-RED.desktop"
                $SUDO sed -i "s|$mat|$ins|" $pfile 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                if xhost >& /dev/null ; then
                    export DISPLAY=:0 && lxpanelctl restart 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                fi
            fi
        fi

        # on Pi, add launcher to top bar, add cpu temp example, make sure ping works
        echo "Now add launcher to top bar, add cpu temp example, make sure ping works" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        if $SUDO grep -q Raspberry /proc/cpuinfo; then
            # $SUDO setcap cap_net_raw+eip $(eval readlink -f `which node`) 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
            $SUDO adduser $NODERED_USER gpio 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
            FAM=$(cat /etc/issue | cut -d ' ' -f 1)
            ISS=$(cat /etc/issue | cut -d '/' -f 2 | cut -d ' ' -f 2)
            if [[ "$FAM" == *"bian" ]]; then
                if (($ISS > 11)); then
                    echo "Replace old rpi.gpio with lgpio" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                    $SUDO apt purge -y python3-rpi.gpio 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                    $SUDO apt install -y python3-pip 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                    $SUDO pip3 install --break-system-packages rpi-lgpio 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                else
                    echo "Leaving old rpi.gpio" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                    $SUDO apt install -y python3-rpi.gpio 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
                fi
            fi
        fi
        $SUDO setcap cap_net_raw=ep /bin/ping 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null

        echo "Allow binding to low ports : $LOW_PORTS" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        if [[ "$LOW_PORTS" == "y" ]] ; then
            $SUDO setcap cap_net_bind_service=+ep $(eval readlink -f `which node`) 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        fi

        echo -ne "\r\n\r\n\r\n"
        echo -ne "All done.\r\n"
        if [[ "$RESTART" == "y" ]]; then
            echo -ne "\033[1mRestarting \033[38;5;88mNode-RED\033[0m service\r\n"
            $SUDO systemctl restart nodered
            echo -ne "\033[1mRestarted  \033[38;5;88mNode-RED\033[0m\r\n"
        else
            if [[ "$GLOBAL" == "true" ]] ; then
                if [[ "$SYSTEMDOK" == "true" ]]; then
                    echo -ne "You can now start Node-RED with the command  \033[0;36mnode-red-start\033[0m\r\n"
                    echo -ne "  or using the icon under   Menu / Programming / Node-RED\r\n"
                else
                    echo -ne "You can now start Node-RED with the command  \033[0;36mnode-red\033[0m\r\n"
                fi
            else
                echo -ne "You can now start Node-RED with the command  \033[0;36m./node-red\033[0m\r\n"
            fi
        fi
        echo -ne "Then point your browser to \033[0;36mlocalhost:1880\033[0m or \033[0;36mhttp://{your_pi_ip-address}:1880\033[0m\r\n"
        echo -ne "\r\n"
        if free -h -t >/dev/null 2>&1; then
            echo "Memory  : $(free -h -t | grep Total | awk '{print $2}' | cut -d i -f 1)" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        else
            echo "Mem     : $(free -m | grep Mem | awk '{print $2}' | cut -d i -f 1)Mb" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
            echo "Swap    : $(free -m | grep Swap | awk '{print $2}' | cut -d i -f 1)Mb" | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
        fi
        echo "Started :  $time1 " | $SUDO tee -a /var/log/nodered-install.log
        echo "Finished:  $(date)" | $SUDO tee -a /var/log/nodered-install.log

        file=/home/$NODERED_USER/.node-red/settings.js
        if [[ "$NODERED_USER" == "root" ]]; then
            file=/root/.node-red/settings.js
        fi
        if [ ! -f $file ]; then
            echo " "
        elif ! diff -q /usr/lib/node_modules/node-red/settings.js $file &>/dev/null 2>&1 ; then
            echo " "
            echo "Just FYI : Your settings.js file is different from the latest defaults."
            echo "You may wish to run"
            echo "   diff -y --suppress-common-lines /usr/lib/node_modules/node-red/settings.js $file"
            echo "to compare them and see what the latest options are."
            echo " "
        fi

        echo "**********************************************************************************"
        echo " ### WARNING ###"
        echo " DO NOT EXPOSE NODE-RED TO THE OPEN INTERNET WITHOUT SECURING IT FIRST"
        echo " "
        echo " Even if your Node-RED doesn't have anything valuable, (automated) attacks will"
        echo " happen and could provide a foothold in your local network"
        echo " "
        echo " Follow the guide at https://nodered.org/docs/user-guide/runtime/securing-node-red"
        echo " to setup security."
        echo " "
        echo " ### ADDITIONAL RECOMMENDATIONS ###"
        if [ -f /etc/sudoers.d/010_pi-nopasswd ]; then
            echo "  - Remove the /etc/sudoers.d/010_pi-nopasswd file to require entering your password"
            echo "    when performing any sudo/root commands:"
            echo " "
            echo "      sudo rm -f /etc/sudoers.d/010_pi-nopasswd"
            echo " "
        fi
        if [ ! -f $file ]; then
            echo "  - You can customise the initial settings by running:"
            echo " "
            echo "      node-red admin init"
            echo " "
            echo "  - After running Node-RED for the first time, change the ownership of the settings"
            echo "    file to 'root' to prevent unauthorised changes:"
            echo " "
            echo "      sudo chown root:root ~/.node-red/settings.js"
            echo " "
        elif ! [[ $(stat --format '%G' ~/.node-red/settings.js) = "root" ]]; then
            echo "  - Change the ownership of its settings file to 'root' to prevent unauthorised changes:"
            echo ""
            echo "      sudo chown root:root ~/.node-red/settings.js"
            echo " "
        fi
        if [ "$EUID" == "0" ]; then
            echo "  - Do not run Node-RED as root or an administraive account"
            echo " "
        fi
        echo "**********************************************************************************"
        echo " "
        if [ ! -f $file ]; then
            initset="${INITSET}"
            # [ ! "${INITSET}" ] && read -t 60 -p "  Would you like to customise the settings now (y/N) ? " initset
            case $initset in
                [Yy]* )
                export HOSTIP=`hostname -I | cut -d ' ' -f 1`
                $SUDO chown -Rf $NODERED_USER:$NODERED_GROUP $NODERED_HOME/.node-red 2>&1 >>/dev/null
                $SUDOU /usr/bin/node-red admin init
                $SUDO chown 0:0 $file
                ;;
                [Nn]* )
                echo "Settings not initialized."
                exit 0
                ;;
                * )
                # echo " "
                # exit 1
                $SUDO chown -Rf $NODERED_USER:$NODERED_GROUP $NODERED_HOME/.node-red/ 2>&1 >>/dev/null
                $SUDOU /usr/bin/node-red admin init
                $SUDO chown 0:0 $file
                ;;
            esac
        fi
    ;;
    * )
        echo " "
        exit 1
    ;;
esac
else
echo " "
echo "Sorry - cannot connect to internet - not going to touch anything."
echo "https://www.npmjs.com/package/node-red   is not reachable."
echo "Please ensure you have a working internet connection."
echo "Return code from curl is "$?
echo " "
exit 1
fi
else
echo " "
echo "Sorry - I'm not supposed to be run on a Mac."
echo "Please see the documentation at http://nodered.org/docs/getting-started/upgrading."
echo " "
exit 1
fi
fi

# Vor dem apt remove/autoremove
echo -ne "  Marking PT dependencies               \r"
$SUDO apt-mark manual pt-miniscreen pt-touchscreen pi-topd python3-pitop-display python3-pitop-core 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null
if [ $? -eq 0 ]; then CHAR=$TICK; else CHAR=$CROSS; fi
echo -ne "  Marking PT dependencies               $CHAR\r\n"

# Am Ende des Skripts
echo -ne '  Re-enabling PT-Miniscreen            \r'
if $SUDO apt install --reinstall -y pt-miniscreen pt-touchscreen pi-topd python3-pitop-display python3-pitop-core python3-pitop 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null && \
   $SUDO systemctl enable pt-miniscreen 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null && \
   $SUDO systemctl start pt-miniscreen 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null; then
    CHAR=$TICK
else
    CHAR=$CROSS
fi
echo -ne "  Re-enabling PT-Miniscreen            $CHAR\r\n"

echo -ne '  Installing PT device support          \r'
if $SUDO apt install -y pt-device-support 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null && \
   $SUDO apt install --reinstall -y pt-miniscreen pt-touchscreen pi-topd python3-pitop-display python3-pitop-core python3-pitop 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null && \
   $SUDO systemctl enable pt-miniscreen 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null && \
   $SUDO systemctl start pt-miniscreen 2>&1 | $SUDO tee -a /var/log/nodered-install.log >>/dev/null; then
    CHAR=$TICK
else
    CHAR=$CROSS
fi
echo -ne "  Installing PT device support          $CHAR\r\n"
