function readFileToMap() { # result ${filePath} ${separator}
	# Reads the contents of a file and separates them by "=" or another given separator
	# Stores the results as key-value-pairs into a map

	local -n result=${1}
	local filePath=${2}
	local separator=${3:-"="}
	local ignoreComments=true

	if [[ ! -e "${filePath}" ]]; then
		echo -e "${RED}ERROR: File not found: ${filePath}${RESET}"
		return 1
  	fi

	# Read the file line by line
	while IFS="${separator}" read -r key value; do
		if [[ ${ignoreComments} == true ]] && [[ "${key}" == \#* ]]; then
        	continue
		fi
		# Trim leading and trailing whitespace from key and value
		key="${key#"${key%%[![:space:]]*}"}"  # Trim leading whitespace
		key="${key%"${key##*[![:space:]]}"}"  # Trim trailing whitespace
		value="${value#"${value%%[![:space:]]*}"}"  # Trim leading whitespace
		value="${value%"${value##*[![:space:]]}"}"  # Trim trailing whitespace

		# Store the key-value pair in the associative array
		result["${key}"]="${value}"
	done <"${filePath}"
}