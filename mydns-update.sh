#!/bin/bash

# --- Load configuration ---
CONF_FILE="/etc/mydns/mydns.conf"
[[ ! -f "$CONF_FILE" ]] && echo "Error: $CONF_FILE not found." >&2 && exit 1
source "$CONF_FILE"

# Prepare cache directory
mkdir -p "$CACHE_DIR"

log_message() {
    local target_log="${LOG_FILE:-/var/log/mydns_update.log}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$target_log"
}

# Function to get the current public IP address
get_current_ip() {
    local url=$1
    curl -s -m "$TIMEOUT" --connect-timeout "$CONN_TIMEOUT" "$url" | tr -d '[:space:]'
}

update_dns() {
    local cred=$1
    local url=$2
    local mode=$3
    local current_ip=$4
    local id_only="${cred%%:*}"
    local cache_file="${CACHE_DIR}/${id_only}_${mode}.lastip"

    # Read the previously cached IP
    local last_ip=""
    [[ -f "$cache_file" ]] && last_ip=$(cat "$cache_file")

    # Skip if the IP is the same as last time
    if [[ "$current_ip" == "$last_ip" ]]; then
        return 0
    fi

    # Execute the update
    response=$(curl -s -u "${cred}" -A "${USER_AGENT}" -m "${TIMEOUT}" \
        --connect-timeout "${CONN_TIMEOUT}" --fail --globoff "$url" 2>&1)
    
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_message "[$mode] IP Changed: ${last_ip:-None} -> ${current_ip}. ID $id_only updated."
        echo "$current_ip" > "$cache_file"
    elif [[ $exit_code -eq 22 ]]; then
        log_message "[$mode] Auth Error (401): ID $id_only."
    else
        log_message "[$mode] Error (Code: $exit_code): ID $id_only."
    fi
}

# --- Main process ---

# 1. First, obtain the current global IP (do this outside the loop for efficiency)
[[ "$ENABLE_IPV4" == "yes" ]] && CURRENT_IPV4=$(get_current_ip "$CHECK_IPV4_URL")
[[ "$ENABLE_IPV6" == "yes" ]] && CURRENT_IPV6=$(get_current_ip "$CHECK_IPV6_URL")

# 2. For each ID, compare and notify if necessary
for entry in "${MYDNS_CREDENTIALS[@]}"; do
    if [[ "$ENABLE_IPV4" == "yes" && -n "$CURRENT_IPV4" ]]; then
        update_dns "$entry" "$IPV4_URL" "IPv4" "$CURRENT_IPV4"
    fi

    if [[ "$ENABLE_IPV6" == "yes" && -n "$CURRENT_IPV6" ]]; then
        update_dns "$entry" "$IPV6_URL" "IPv6" "$CURRENT_IPV6"
    fi
done

exit 0
