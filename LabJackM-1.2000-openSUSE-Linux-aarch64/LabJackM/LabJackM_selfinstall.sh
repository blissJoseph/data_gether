#! /bin/bash

set -e
set -u

VERSION=$1

# Get the major version number
MAJOR_V=${VERSION%%.*}
LIB_LJM=libLabJackM.so
LJM_REALNAME=$LIB_LJM.$VERSION
LJM_SONAME=$LIB_LJM.$MAJOR_V
LJM_LINKERNAME=$LIB_LJM
DESTINATION=/usr/local/lib
CONSTANTS_DESTINATION=/usr/local/share
HEADER_DESTINATION=/usr/local/include
HEADER="LabJackM.h"
LJM_TOP_DIRECTORY=LabJackM

# Rules
RULES=90-labjack.rules
OLD_RULES=10-labjack.rules
RULES_DEST_PRIMARY=/lib/udev/rules.d
RULES_DEST_ALTERNATE=/etc/udev/rules.d

LDCONFIG_FILE=/etc/ld.so.conf

SUPPORT_EMAIL=support@labjack.com

TRUE="true"
FALSE="false"

# Assume these are unneeded until otherwise
NEED_RECONNECT=$FALSE
NEED_RESTART=$FALSE
NO_RULES=$FALSE
NO_RULES_ERR=2

# Function declarations

success ()
{
	echo

	e=0
	echo "Install finished. Please check out the README for usage help."
	if [ $NEED_RECONNECT == $TRUE ]; then
		echo
		echo "If you have any LabJack devices connected, please disconnect and"
		echo "reconnect them now for device rule changes to take effect."
	fi
	if [ $NO_RULES == $TRUE ]; then
		echo
		echo "No udev rules directory found."
		echo "Searched for $RULES_DEST_PRIMARY, $RULES_DEST_ALTERNATE."
		echo "Please copy $RULES to your device rules directory and reload the rules"
		echo "or contact LabJack support for assistance: <$SUPPORT_EMAIL>"
		let e=e+$NO_RULES_ERR
	fi
	if [ $NEED_RESTART == $TRUE ]; then
		echo
		echo "Please manually restart the device rules or restart your computer now."
	fi
	exit $e
}

go ()
{
	$@
	ret=$?
	if [ $ret -ne 0 ]; then
		echo "Failure on command: $@"
		echo "Please contact LabJack at $SUPPORT_EMAIL"
		echo "Exiting"
		exit $ret
	fi
}

install_ljm_lib ()
{
	echo -n "Installing ${LJM_REALNAME} to ${DESTINATION}... "
	go install ${LJM_REALNAME} ${DESTINATION}
	if [ -f ${DESTINATION}/${LJM_LINKERNAME} ]; then
		go rm -f ${DESTINATION}/${LJM_LINKERNAME}
	fi
	if [ -f ${DESTINATION}/${LJM_SONAME} ]; then
		go rm -f ${DESTINATION}/${LJM_SONAME}
	fi

	# Link
	go ln -s -f ${DESTINATION}/${LJM_REALNAME} ${DESTINATION}/${LJM_SONAME}
	go ln -s -f ${DESTINATION}/${LJM_SONAME} ${DESTINATION}/${LJM_LINKERNAME}
	echo "done."
}

install_ljm_header ()
{
	echo -n "Installing ${HEADER} to ${HEADER_DESTINATION}... "
	go install ${HEADER} ${HEADER_DESTINATION}
	echo "done."
}

install_auto_ips_file ()
{
	AIPS_FILE="${CONSTANTS_DESTINATION}/LabJack/LJM/ljm_auto_ips.json"
	if [ ! -f ${AIPS_FILE} ]; then
		echo '{"autoIPs":[]}' > ${AIPS_FILE}
	fi
	chmod a+rw ${AIPS_FILE}
}

install_ljm_constants ()
{
	echo -n "Installing constants files to ${CONSTANTS_DESTINATION}... "
	if [ ! -d ${CONSTANTS_DESTINATION}/LabJackM/LJM ]; then
		go mkdir -p ${CONSTANTS_DESTINATION}/LabJack/LJM
	fi
	go install LabJack/LJM/ljm_constants.json -t ${CONSTANTS_DESTINATION}/LabJack/LJM
	go install LabJack/LJM/ljm_startup_configs.json -t ${CONSTANTS_DESTINATION}/LabJack/LJM
	go install --mode=666 LabJack/LJM/ljm.log -t ${CONSTANTS_DESTINATION}/LabJack/LJM

	install_auto_ips_file

	go chmod a+rw ${CONSTANTS_DESTINATION}/LabJack/LJM

	echo "done."
}

setup_ldconfig ()
{
	path_exists=$FALSE
	for line in `cat $LDCONFIG_FILE`; do
		if [ $line == $DESTINATION ]; then
			path_exists=$TRUE
		fi
	done

	if [ $path_exists != $TRUE ]; then
		echo "$DESTINATION >> $LDCONFIG_FILE"
		echo $DESTINATION >> $LDCONFIG_FILE
	fi
	go ldconfig
}

setup_labjack_device_rules ()
{
	# LabJack device rules
	if [ -d $RULES_DEST_PRIMARY ]; then
		RULES_DEST=$RULES_DEST_PRIMARY
	elif [ -d $RULES_DEST_ALTERNATE ]; then
		RULES_DEST=$RULES_DEST_ALTERNATE
	else
		NO_RULES=$TRUE
	fi

	echo -n "Adding LabJack device rules... "
	if [ $NO_RULES != $TRUE ]; then
		if [ -f $RULES_DEST_PRIMARY/$OLD_RULES ]; then
			echo -n "Removing old rules: $RULES_DEST_PRIMARY/$OLD_RULES... "
			go rm $RULES_DEST_PRIMARY/$OLD_RULES
		fi

		if [ -f $RULES_DEST_ALTERNATE/$OLD_RULES ]; then
			#echo "Removing old rules: $RULES_DEST_ALTERNATE/$OLD_RULES.."
			go rm $RULES_DEST_ALTERNATE/$OLD_RULES
		fi

		#echo "Adding $RULES to $RULES_DEST.."
		go cp -f $RULES $RULES_DEST
		NEED_RECONNECT=$TRUE
	fi
	echo "done."
}

restart_device_rules ()
{
	echo -n "Restarting the device rules... "
	udevadm control --reload-rules 2> /dev/null
	ret=$?
	if [ ! $ret ]; then
		udevadm control --reload_rules 2> /dev/null
		ret=$?
	fi
	if [ ! $ret ]; then
		/etc/init.d/udev-post reload 2> /dev/null
		ret=$?
	fi
	if [ ! $ret ]; then
		udevstart 2> /dev/null
		ret=$?
	fi
	if [ ! $ret ]; then
		NEED_RESTART=$TRUE
		echo " could not restart the rules."
	else
		echo "done."
	fi
}

setup_permissions ()
{
	chmod -R a+w ../$LJM_TOP_DIRECTORY/examples || true
	if [ $? -ne 0 ]; then
		echo "Non-critical error: Failed to chmod $LJM_TOP_DIRECTORY/examples"
		echo "You may want to manually set up permissions on $LJM_TOP_DIRECTORY/examples"
	fi
}


# Some setup

VERSION_REGEX="^[0-9]+\.[0-9]+\.[0-9]+$"
if [[ ! $VERSION =~ $VERSION_REGEX ]] ; then
	echo "Argument $1 does look like a version number, exiting."
	echo "Please contact LabJack at $SUPPORT_EMAIL"
	echo "Exiting"
	exit EINVAL
fi


# Begin installing/configuring

install_ljm_lib
install_ljm_header
install_ljm_constants

# ldconfig setup, now that LabJackM is installed
setup_ldconfig

setup_labjack_device_rules
restart_device_rules

setup_permissions

success
