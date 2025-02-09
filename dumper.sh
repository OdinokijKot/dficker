#!/usr/bin/env bash

# Variables
work_device=()
output_folder=()
hash_algo=()
compress=0

# Internal variables
version="1.0.1"
name="Dumper v${version} (c) Odinokij_Kot"
full_name=$(readlink -f "${0}")
hash_whitelist=(b2sum md5sum shasum sha1sum sha224sum sha256sum sha384sum sha512sum)

intro_message ()
{
	line=$(printf -- "─%.0s" $(seq ${#name}))
	echo "┌─$line─┐"
	echo "│ ${name} │"
	echo "└─$line─┘"
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

error ()
{
	echo "`basename \"${full_name}\"`: $*" >&2
	exit 1
}

show_devs ()
{
	echo "Device in system:"
	if [ -x "$(command -v lsblk)" ]
		then
			sudo lsblk -ao NAME,PATH,SIZE,VENDOR,MODEL,SERIAL,MOUNTPOINT,TYPE 2> /dev/null
			[ "$?" -ne "0" ] && df -h
		else
			[ -x "$(command -v df)" ] && df -h
	fi
}

select_device ()
{
	read -r -p "Enter short or full device name: " 
	work_device=${REPLY}
	[ -b "${work_device}" ] && return
	[ -x "$(command -v lsblk)" ] && work_device=$(sudo lsblk -ao PATH 2> /dev/null | grep "${REPLY}" | head -1)
	[ ! -b "${work_device}" ] && error "Device ${REPLY} not found."
}

select_hash_algo ()
{
	list_hash=()
	for algo in "${hash_whitelist[@]}"
		do
			[ -x "$(command -v ${algo})" ] && list_hash=(${list_hash[@]} ${algo})
		done
	
	echo "Found hash algorithms:"
	
	ESC=$(printf "\e")
	PS3="${ESC}[KSelect hash algorithm or 0 to exit: "
	
	select hash in ${list_hash[@]}
	do
	  [ -z "${hash}" ] && break
	  [[ ! "${hash_algo[*]}" =~ "${hash}" ]] && hash_algo=(${hash_algo[@]} ${hash})
	  echo -e "Calculate: ${hash_algo[@]}\e[2F"
	done
	echo
}

select_folder ()
{
	_name_serial=$(lsblk -dno MODEL,SERIAL "${work_device}" | sed '/^ \{2,\}$/d')
	[ -n "${_name_serial}" ] && output_folder=$(echo "$_name_serial" | sed 's/ /_/g') || \
		output_folder="image_$(basename ${work_device})"

	read -r -p "Enter folder name (default: ${output_folder}): " 
	[ -n "${REPLY}" ] && output_folder="${REPLY}"
	output_folder="$(dirname "${full_name}")/${output_folder}.$(date +%F_%H.%M.%S)"
}

set_compress ()
{
	read -r -p "Create compressed image? [Y/n] (default: n): "
	[[ ("${REPLY}" = "Y") || ("${REPLY}" = "y") ]] && compress=1
}

warning ()
{
	echo "Warning! Let's check parameters:"
	echo "Device: ${work_device}"
	echo "Folder: ${output_folder}"
	echo -n "Hash algorithms: "; [ -z "${hash_algo[0]}" ] && echo "None" || echo "${hash_algo[@]}"
	echo -n "Compressed: "; [ "${compress}" -eq "0" ] && echo "No" || echo "Yes"
	read -r -p "All correct? [Y/n] (default: n): "
	[[ ("${REPLY}" != "Y") && ("${REPLY}" != "y") ]] && exit 0
}

dump ()
{
	echo "Start dd-ing!"
	_temp=$(pwd)
	mkdir -p "${output_folder}" &> /dev/null
	cd "${output_folder}"
	
	hash_string=""
	if [ ! -z "${hash_algo[0]}" ] 
		then
			hash_string+="| tee"
			for algo in "${hash_algo[@]}"
			do
				hash_string+=" >(${algo} > image.${algo}) "
			done
	fi
	
	[ ${compress} -eq "1" ] && output=" | gzip -c > image.dd.gz" || output=" > image.dd"
	
	eval "sudo dd if=${work_device} bs=1M conv=sync,noerror status=progress ${hash_string} ${output}"
	
	cd "${_temp}"
}

main ()
{
	intro_message
	echo
	sudo_check
	show_devs
	echo
	select_device
	select_folder
	select_hash_algo
	set_compress
	echo
	warning
	echo
	dump

	exit 0
}

main "$@"
echo "Out of main!"
exit 10
