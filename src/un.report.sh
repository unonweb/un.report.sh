#!/bin/bash

# ARGS
# ---
# --ssh-logins
# --admin-activity
# --errors
# --disk-space

set -e # stop execution on error
set -u # throw error if unknown variable is encountered

# Ensure the script is run as root
if [ "${EUID}" -ne 0 ]; then
	echo "This script must be run as root. Exiting."
	exit 1
fi

# BOILERPLATE
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE}")"
SCRIPT_DIR=$(dirname -- "$(readlink -f "${BASH_SOURCE}")")
SCRIPT_NAME=$(basename -- "$(readlink -f "${BASH_SOURCE}")")

ESC=$(printf "\e")
BOLD="${ESC}[1m"
RESET="${ESC}[0m"
RED="${ESC}[31m"
GREEN="${ESC}[32m"
BLUE="${ESC}[34m"
UNDERLINE="${ESC}[4m"

# FUNCTIONS
source "${SCRIPT_DIR}/lib/readFileToMap.sh"
source "${SCRIPT_DIR}/lib/isValueInArray.sh"
source "${SCRIPT_DIR}/lib/logMapItems.sh"

# CONSTANTS
CONFIG_PATH="${SCRIPT_DIR}/config.ini"
declare -A CONFIG

# read config from file
readFileToMap CONFIG ${CONFIG_PATH}
#logMapItems CONFIG

function main() {
	# config
	local mailDest=${CONFIG[EMAIL]}
	local mailSubj=${CONFIG[SUBJECT]}
	local timeFrame=${CONFIG[TIME_FRAME]}
	local sendReport=${CONFIG[SEND_REPORT]}
	local logEnabled=${CONFIG[LOG_ENABLED]}
	local logDir=${CONFIG[LOG_DIR]:-"${SCRIPT_DIR}/log"}
	local errorPriority=${CONFIG[ERROR_PRIORITY]}
	local spaceThreshold=${CONFIG[SPACE_THRESHOLD]}
	# args flags
	local enableSSHReport=${CONFIG[REPORT_SSH]:-0}
	local enableAdminReport=${CONFIG[REPORT_ADMIN]:-0}
	local enableErrorReport=${CONFIG[REPORT_ERRORS]:-0}
	local enableAlertSpace=${CONFIG[REPORT_SPACE]:-0}
	# constants
	local host=$(hostname)
	local timeStamp=$(date +%y-%m-%d_%R)                # 25-04-14_14:28
	local logFileName="${host}_report_${timeStamp}.log" # fk-mobil25_report_25-04-14_14:28.log
	#local logFileTmp="${SCRIPT_NAME%.sh}.log"
	#local logFileDst="${SCRIPT_NAME%.sh}-${timeStamp}.log"
	local logPath="${logDir}/${logFileName}"
	local logPathFallback="{SCRIPT_DIR}/${logFileName}"
	local report=
	local alerts=
	local contentLines=0
	local hasContent=0
	local hasAlerts=0
	# --ssh-logins
	local sshLogins=()

	mailSubj+=${host}

	# parse args flags
	for arg in "${@}"; do
		case ${arg} in
		--disk-space)
			enableAlertSpace=1
			;;
		--ssh-logins)
			enableSSHReport=1
			;;
		--admin-activity)
			enableAdminReport=1
			;;
		--errors)
			enableErrorReport=1
			;;
		esac
	done

	# report header
	report+="REPORT\n"
	report+="------\n"
	report+="SINCE: ${timeFrame}\n"
	report+="HOST: $(hostname)\n"
	report+="DATE: $(date)\n"

	# error report
	if ((enableErrorReport)); then
		reportErrors report ${errorPriority} &&
			hasContent=1
	fi

	# admin activity report
	if ((enableAdminReport)); then
		reportRootLogins report &&
			hasContent=1
		reportSudoUsage report &&
			hasContent=1
	fi

	# ssh report
	if ((enableSSHReport)); then
		reportSSHLogins report &&
			hasContent=1
	fi

	# space alerts
	if ((enableAlertSpace)); then
		alertDiskSpace alerts ${spaceThreshold} &&
			hasAlerts=1
	fi

	# has content?
	if !((hasContent)); then
		echo -e "Nothing to report"
		exit 0
	fi

	# report + alert
	if ((hasAlerts)); then
		report+=${alerts}
	fi

	# log report
	if ((logEnabled)); then
		if [[ -w "${logDir}" ]]; then
			printf "%b\n" "${report}" >${logPath} &&
				echo "Successfully written report to ${logPath}"
		else
			echo "ERROR: Path not writable: ${GREEN}${logDir}${RESET}"
		fi
	fi

	# send report
	if ((sendReport)); then
		echo -e ${report} | mail -s "${mailSubj}" "${mailDest}" &&
			echo "Successfully sent mail report to ${mailDest}"
	fi
}

function alertDiskSpace() { # alerts ${threshold}
	local -n _alerts=${1}
	local threshold=${2}
	local tmp=()
	local diskUsage=()
	local usage
	local mountPoint

	mapfile -t diskUsage < <(df -h --output=pcent,target | tail -n +2)

	for line in "${diskUsage[@]}"; do
		# Extract the usage percentage and mount point
		usage=$(echo "${line}" | awk '{print $1}' | tr -d '%')
		mountPoint=$(echo "${line}" | awk '{print $2}')
		# Check if usage exceeds threshold
		if [[ "${line}" == *"/media/"* ]]; then
			continue
		elif ((100 - usage < threshold)); then
			tmp+=("${mountPoint} has less than ${threshold}% free space!")
		fi
	done

	if [[ ${#tmp[@]} -gt 0 ]]; then
		_alerts+="\n"
		_alerts+="DISK SPACE\n"
		_alerts+="----------\n"
		for item in "${tmp[@]}"; do
			_alerts+="${item}\n"
		done
		return 0
	else
		return 1
	fi
}

function reportErrors() { # report ${priority}
	local -n _report=${1}
	local priority=${2:-"2"}
	local timeFrame="today"
	local bootID=-0
	local errorLogs=()

	mapfile -t errorLogs < <(journalctl --quiet --boot "${bootID}" --since "${timeFrame}" --priority "${priority}")

	if [[ ${#errorLogs[@]} -gt 0 ]]; then
		_report+="\n"
		_report+="ERRORS\n"
		_report+="------\n"
		for item in "${errorLogs[@]}"; do
			if [[ "${item}" == *"watchdog did not stop!"* ]]; then continue; fi # ignore
			_report+="${item}\n"
		done
		return 0
	else
		return 1
	fi
}

function reportRootLogins() { # report
	local -n _report=${1}
	local timeFrame="today"
	local rootLogins=()

	# get data
	mapfile -t rootLogins < <(journalctl --quiet --since ${timeFrame} _UID=0 --grep 'session opened for user root')

	if [[ ${#rootLogins[@]} -gt 0 ]]; then
		_report+="\n"
		_report+="ROOT LOGINS\n"
		_report+="-----------\n"
		for item in "${rootLogins[@]}"; do
			_report+="${item}\n"
		done
		return 0
	else
		return 1
	fi

}

function reportSudoUsage() { # report
	local -n _report=${1}
	local timeFrame="today"
	local sudoUsage=()
	
	# sudo usage
	mapfile -t sudoUsage < <(journalctl --quiet --since "${timeFrame}" --identifier sudo --grep 'COMMAND=')

	if [[ ${#sudoUsage[@]} -gt 0 ]]; then
		_report+="\n"
		_report+="SUDO USAGE\n"
		_report+="----------\n"
		for item in "${sudoUsage[@]}"; do
			_report+="${item}\n"
		done
		return 0
	else
		return 1
	fi

}

function reportSSHLogins() { # _report
	local -n _report=${1}
	local timeFrame="today"
	
	# ssh logins
	mapfile -t sshLogins < <(journalctl --quiet --since "${timeFrame}" --identifier sshd)

	if [[ ${#sshLogins[@]} -gt 0 ]]; then
		_report+="\n"
		_report+="SSH LOGINS\n"
		_report+="-----------\n"

		for item in "${sshLogins[@]}"; do
			if [[ "${item}" == *"Server listening on"* ]]; then continue; fi # ignore
			_report+="${item}\n"
		done

		return 0
	else
		return 1
	fi
}

main ${@}
