function logMapItems() { # map
	local -n _map=${1}
	# log
	for key in ${!_map[@]}; do
	    echo -e "${key}=${_map[${key}]}"
	done
}
