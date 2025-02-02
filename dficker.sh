#!/usr/bin/env bash

# Variables
temp_dir=()
output_file=()
verbose=0

# Internal variables
version="1.5.1"
name="Digital Forensics and Incident response artifacts piCKER v${version} (c) Odinokij_Kot"
current_datetime=()
tempfs=0
full_name=$(readlink -f "${0}")
machine_name=()

# Functions
intro_message ()
{
	line=$(printf -- "─%.0s" $(seq ${#name}))
	echo "┌─$line─┐"
	echo "│ ${name} │"
	echo "└─$line─┘"
}

usage_message () 
{
	echo "Usage: `basename \"${full_name}\"` [flags]"
	echo "      Flags:"
	echo "       [-o|--output]   -- Set output archive file name"
	echo "       [-t|--tempdir]  -- Set temporary work directory"
	echo "       [-h|--help]     -- Print this help message and exit"
    echo "       [-V|--version]  -- Print version information and exit"
	echo "       [-v|--verbose]  -- Print more details"
	echo
}

# Checking for required utilities
dependencies_check ()
{
	command -v gzip &> /dev/null
	[ "$?" -ne "0" ] && error "Gzip not found. Please install it."
}

# External config file loading
load_config ()
{
	config_file=$(dirname "${full_name}")"/dficker.cfg"
	if [ -e "${config_file}" ]
	  then
			source "${config_file}"
			echo "Configuration file ${config_file} loaded"
	fi
}

error()
{
    echo "`basename \"${full_name}\"`: $*" >&2
    exit 1
}

parse_flags()
{
    while [[ $# -gt 0 ]]; do
        case "$1" in
        (-t|--tempdir)
			shift
            [ $# = 0 ] && error "-t" "No temporary directory specified"
			[ "${1:0:1}" = "-" ] && error "-t" "Temporary directory name \"${1}\" error"
			temp_dir=$1
			shift
			;;
        (-o|--output)
			shift
            [ $# = 0 ] && error "-o" "No output file specified"
			[ "${1:0:1}" = "-" ] && error "-o" "Output file name name \"${1}\" error"
			output_file=${1}
			shift
			;;
        (-h|--help)
            usage_message
			exit 0
			;;
        (-V|--version)
            echo ${version}
			exit 0
			;;
        (-v|--verbose)
            shift
			verbose=1
			;;
		(-*|--*)
			echo "Unknown option: ${1}"
			exit 1
			;;
        (*)
			positional_args+=("$1") # save positional arg
			shift
			;;
        esac
    done
}

sudo_check ()
{
	echo "Warning! You must have Superuser's rights via sudo for using this tool."
	echo "Trying sudo. If prompted for a password, enter it."
	sudo echo "Sudo seems to work well."
	if [ "$?" -ne "0" ]
		then
			echo "Trying sudo fail. Goodbye."
			exit 2
	fi
	echo
}

setting_variables ()
{
	[ "${verbose}" -ne "0" ] && echo "Preparing variables"
	machine_name=`uname -n`
	current_datetime=`date +%F_%H.%M.%S`
	
	# Output file name preparation
	[ -z "$output_file" ] && output_file=$(pwd)"/dficker.${version}.report"
	output_file+=".${machine_name}.${current_datetime}.tar.gz"
	mkdir -p "$(dirname "${output_file}")" &> /dev/null
	[ "$?" -ne "0" ] && error "Output file directory \"${output_file}\" creating error" 
	output_file=$(readlink -f "${output_file}")
	
	[ "${verbose}" -ne "0" ] && echo "Output report file: ${output_file}"
}

# Garbage collection
cleaning ()
{
	[ "${verbose}" -ne "0" ] && echo "Cleaning temporary directory"
	[ "$tempfs" -eq "1" ] && sudo umount "${temp_dir}" &> /dev/null
	rm -R "${temp_dir}" &> /dev/null
}

# Prepare a temporary directory
create_tempdir ()
{
	[ -z "$temp_dir" ] && temp_dir="/tmp/dficker_temp" && tempfs=1
	[ -d "$temp_dir" ] && temp_dir+="/dficker_temp"
	mkdir -p "${temp_dir}" 2> /dev/null
	if [ "$?" -eq "0" ]
		then
			temp_dir=$(readlink -f "${temp_dir}")
			if [ "$tempfs" -eq "1" ]
				then
					sudo mount -t tmpfs dficker_tempfs "${temp_dir}" 2> /dev/null
					[ "$?" -ne "0" ] && error "Tempfs directory ${temp_dir} mount error"
			fi
		else
			error "Temporary directory \"${temp_dir}\" creating error" 
	fi
	
	sudo chmod -R a=rw,a+X "${temp_dir}" 2> /dev/null
	[ "${verbose}" -ne "0" ] && echo "Temporary directory: ${temp_dir} created"
}

# Creating archive with artifacts
create_report ()
{
	[ "${verbose}" -ne "0" ] && echo "Creating a report archive"
	_temp=$(pwd)
	sudo chmod -R a=rw,a+X "${temp_dir}" &> /dev/null
	cd "${temp_dir}"
	tar -czf "${output_file}" *
	cd "${_temp}"
	echo "Report \"${output_file}\" created"
}

# Picking general host info
get_general_info ()
{
	[ "${verbose}" -ne "0" ] && echo "Getting general info"
	_file="${temp_dir}/general_info.txt"
	touch "${_file}"
	
	echo "uname -a:" >>  "${_file}"
	uname -a >> "${_file}"
	echo >> "${_file}"
	
	echo "dmesg:" >>  "${_file}"
	sudo dmesg >> "${_file}"
	echo >> "${_file}"
}

# Picking filesystem info
get_fs_info ()
{
	[ "${verbose}" -ne "0" ] && echo "Getting filesystems info"
	_file="${temp_dir}/fs_info.txt"
	touch "${_file}"
	
	if [ -x "$(command -v mount)" ]
		then
			echo "mount -l:" >> "${_file}"
			sudo mount -l &>> "${_file}"
			echo >> "${_file}"
	fi
	
	if [ -x "$(command -v lsblk)" ]
		then
			echo "lsblk -O:" >> "${_file}"
			sudo lsblk -O &>> "${_file}"
			echo >> "${_file}"
	
			echo "lsblk -f:" >> "${_file}"
			sudo lsblk -f &>> "${_file}"
			echo >> "${_file}"
	fi
	
	if [ -x "$(command -v findmnt)" ]
		then
			echo "findmnt:" >> "${_file}"
			sudo findmnt &>> "${_file}"
			echo >> "${_file}"
	fi
}

# Picking passwd, shadow and group files
copy_users_credentials ()
{
	[ "${verbose}" -ne "0" ] && echo "Passwd, shadow and group files picked"
	mkdir -p "${temp_dir}/users" &> /dev/null
	sudo cp -L /etc/passwd /etc/shadow /etc/group "${temp_dir}/users" &> /dev/null
}

# Picking process info
get_process_info ()
{
	[ "${verbose}" -ne "0" ] && echo "Getting process info"
	_file="${temp_dir}/ps_info.txt"
	touch "${_file}"
	
	if [ -x "$(command -v ps)" ]
		then
			echo "ps auxf:" >> "${_file}"
			sudo ps auxf &>> "${_file}"
			echo >> "${_file}"
	fi
	
	if [ -x "$(command -v pstree)" ]
		then
			echo "pstree -p -a -c:" >> "${_file}"
			sudo pstree -p -a -c &>> "${_file}"
			echo >> "${_file}"
	fi
}

# Picking network info
get_network_info ()
{
	[ "${verbose}" -ne "0" ] && echo "Getting network info"
	_file="${temp_dir}/network_info.txt"
	touch "${_file}"
	
	if [ -x "$(command -v ifconfig)" ]
		then
			echo "ifconfig -a:" >> "${_file}"
			sudo ifconfig -a &>> "${_file}"
			echo >> "${_file}"
	fi
	
	if [ -x "$(command -v ip)" ]
		then
			echo "ip addr show:" >> "${_file}"
			sudo ip addr show &>> "${_file}"
			echo >> "${_file}"
			
			echo "ip stats:" >> "${_file}"
			sudo ip stats &>> "${_file}"
			echo >> "${_file}"

			echo "ip route show:" >> "${_file}"
			sudo ip route show &>> "${_file}"
			echo >> "${_file}"
	fi
	
	mkdir -p "${temp_dir}/network" &> /dev/null
	sudo cp -L /etc/host* "${temp_dir}/network" &> /dev/null
	[ -d "/etc/netplan" ] && sudo cp -Lr /etc/netplan "${temp_dir}/network" &> /dev/null
	[ -d "/etc/NetworkManager" ] && sudo cp -Lr /etc/NetworkManager "${temp_dir}/network" &> /dev/null
	[ -d "/etc/netctl" ] && sudo cp -Lr /etc/netctl "${temp_dir}/network" &> /dev/null
	
}

# Picking package managers info
get_package_managers_info ()
{
	# +DPKG +APT +-RPM YUM Pacman Zypper Portage +-Snap Flatpack aptitude 
	
	[ "${verbose}" -ne "0" ] && echo "Getting package managers info"
	
	# APT package manager
	if [ -x "$(command -v apt)" ]
		then
			[ "${verbose}" -ne "0" ] && echo "APT package manager found"
			_file="${temp_dir}/apt_info.txt"
			touch "${_file}"
			
			echo "List of used repositories:" >> "${_file}"
			sudo grep -rhE ^deb /etc/apt/sources.list* &>> "${_file}"
			echo >> "${_file}"
			sudo apt-cache policy  &>> "${_file}"
			echo >> "${_file}"
			
			echo "apt list --installed:" >> "${_file}"
			sudo sudo apt list --installed &>> "${_file}"
			echo >> "${_file}"
			
			echo "apt-mark showmanual:" >> "${_file}"
			sudo sudo apt-mark showmanual &>> "${_file}"
			echo >> "${_file}"
			
			mkdir -p "${temp_dir}/apt" &> /dev/null
			sudo cp -Lr /etc/apt "${temp_dir}/apt/config" &> /dev/null
			sudo cp -Lr /var/lib/apt "${temp_dir}/apt/lib" &> /dev/null
			sudo cp -Lr /var/log/apt "${temp_dir}/apt/logs" &> /dev/null
	fi

	# DPKG package manager
	if [ -x "$(command -v dpkg)" ]
		then
			[ "${verbose}" -ne "0" ] && echo "DPKG package manager found"
			_file="${temp_dir}/dpkg_info.txt"
			touch "${_file}"
			
			echo "dpkg-query -l:" >> "${_file}"
			sudo dpkg-query -l &>> "${_file}"
			echo >> "${_file}"
			
			echo "dpkg --get-selections:" >> "${_file}"
			sudo dpkg --get-selections | grep -v "deinstall" &>> "${_file}"
			echo >> "${_file}"
			
			mkdir -p "${temp_dir}/dpkg" &> /dev/null
			sudo cp -Lr /etc/dpkg "${temp_dir}/dpkg/config" &> /dev/null
			sudo cp -Lr /var/lib/dpkg "${temp_dir}/dpkg/lib" &> /dev/null
			sudo cp -Lr /var/log/dpkg.log* "${temp_dir}/dpkg/logs" &> /dev/null
	fi
	
	# SNAP package manager
	if [ -x "$(command -v snap)" ]
		then
			[ "${verbose}" -ne "0" ] && echo "SNAP package manager found"
			_file="${temp_dir}/snap_info.txt"
			touch "${_file}"
			
			echo "snap list:" >> "${_file}"
			sudo snap list &>> "${_file}"
			echo >> "${_file}"
			
			echo "snap changes:" >> "${_file}"
			sudo snap changes &>> "${_file}"
			echo >> "${_file}"
			
			echo "snap saved:" >> "${_file}"
			sudo snap saved &>> "${_file}"
			echo >> "${_file}"
	fi
	
	# RPM package manager
	if [ -x "$(command -v rpm)" ]
		then
			# [ "${verbose}" -ne "0" ] && echo "RPM package manager found"
			# _file="${temp_dir}/rpm_info.txt"
			# touch "${_file}"
			
			# echo "dpkg-query -l:" >> "${_file}"
			# sudo dpkg-query -l &>> "${_file}"
			# echo >> "${_file}"
			
			# echo "dpkg --get-selections:" >> "${_file}"
			# sudo dpkg --get-selections | grep -v "deinstall" &>> "${_file}"
			# echo >> "${_file}"
			
			mkdir -p "${temp_dir}/rpm" &> /dev/null
			sudo cp -Lr /etc/rpm "${temp_dir}/rpm/config" &> /dev/null
			sudo cp -Lr /var/lib/rpm "${temp_dir}/rpm/lib" &> /dev/null
			sudo cp -Lr /var/log/rpmpkgs "${temp_dir}/rpm/logs" &> /dev/null
	fi
	
}

# Main function
main ()
{
	# Show intro and load config from file dficker.cfg
	intro_message
	dependencies_check
	load_config
	echo
	
	# Processing input parameters
	positional_args=()
	parse_flags "$@"
	# Restore positional arguments
	set -- "${positional_args[@]}"

	sudo_check
	
	# Setting variables and prepare temporary directory
	setting_variables "$@"
	create_tempdir
	[ "${verbose}" -ne "0" ] && echo 
	
	# Picking artifacts
	echo "Start picking artifacts"
	get_general_info
	get_fs_info
	copy_users_credentials
	get_process_info
	get_network_info
	get_package_managers_info
	[ "${verbose}" -ne "0" ] && echo 
	
	# Saving report and cleanup work directory
	create_report
	cleaning
	exit 0
}
main "$@"

echo "Out of main!!!"
exit 100

# End of script






curl_path=`whereis -b curl | awk '{print $2}'`

if [ -z "$curl_path" ]
then
  echo "Утилита curl в системе не обнаружена. Установите её и попробуйте опять."
  exit 3
fi






aptitude search '~i!~M'

declare -A osInfo;
osInfo[/etc/redhat-release]=yum
osInfo[/etc/arch-release]=pacman
osInfo[/etc/gentoo-release]=emerge
osInfo[/etc/SuSE-release]=zypp
osInfo[/etc/debian_version]=apt-get
osInfo[/etc/alpine-release]=apk
for f in ${!osInfo[@]}
do
    if [[ -f $f ]];then
        echo Package manager: ${osInfo[$f]}
    fi
done

- packagesNeeded='curl jq'
 - if [ -x "$(command -v apk)" ];       then sudo apk add --no-cache $packagesNeeded
 - elif [ -x "$(command -v apt-get)" ]; then sudo apt-get install $packagesNeeded
 - elif [ -x "$(command -v dnf)" ];     then sudo dnf install $packagesNeeded
 - elif [ -x "$(command -v zypper)" ];  then sudo zypper install $packagesNeeded
 - else echo "FAILED TO INSTALL PACKAGE: Package manager not found. You must manually install: $packagesNeeded">&2; fi