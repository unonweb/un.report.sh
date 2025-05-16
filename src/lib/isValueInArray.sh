function isValueInArray() { # "${value}" "${array[@]}"
	local element="${1}"
	shift
	local array=("${@}")

	for item in "${array[@]}"; do
		if [[ "${item}" == "${element}" ]]; then
			return 0 # Found
		fi
	done

	return 1 # Not found
}