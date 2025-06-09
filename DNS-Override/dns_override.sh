#!/bin/zsh

###################################### VARIABLES ##########################################
PINK='\033[38;5;206m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

scriptname=$(basename $(realpath $0))
current_dir=$(dirname $(realpath $0))
logged_user=$(stat -f "%Su" /dev/console)
HOME_DIR=$(dscl . -read /Users/$logged_user NFSHomeDirectory | awk '{print $2}')
DNSCRYPT_DIR="$HOME_DIR/Applications/dnscrypt-proxy"
DNSCRYPT_VERSION="2.1.12"
DNSCRYPT_DOWNLOAD_URL="https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/$DNSCRYPT_VERSION/dnscrypt-proxy-macos_arm64-$DNSCRYPT_VERSION.zip"
ORIGINAL_DNS_SETTINGS=()
MODIFIED_INTERFACES=()
LOG_FILE="$current_dir/dns_override.log"

###################################### SPINNER FUNCTION ##########################################

function spinner() {
    local pid=$1
    local delay=0.5
    local spin='-\|/'
    local i=0
    while [ "$(ps -p $pid -o pid=)" ]; do
        i=$(( (i+1) % 4 ))
        printf "\r[%c] Waiting..." "${spin:$i:1}"
        sleep $delay
    done
}

###################################### LOGGING FUNCTIONS ##########################################

function log_to_file() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" >> "$LOG_FILE"
}

function logI() {
    echo -e "${GREEN}[INFO]${NC}    $1"
    log_to_file "[INFO] $1"
}

function logW() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log_to_file "[WARNING] $1"
}

function logE() {
    echo -e "${RED}[ERROR]${NC}   $1"
    log_to_file "[ERROR] $1"
}

function logS() {
    echo -e "${PINK}[SUCCESS]${NC} $1"
    log_to_file "[SUCCESS] $1"
}

###################################### PREREQUISITE CHECKS ##########################################

function check_prerequisites() {
    # Check if running on macOS
    if [[ $(uname) != "Darwin" ]]; then
        logE "This script is intended to run only on macOS."
        exit 1
    fi

    # Check if running with elevated privileges
    if [[ $EUID -ne 0 ]]; then
        logE "This script must be run with sudo privileges."
        exit 1
    fi

    # Check if anything is already listening on port 53
    if [[ $(lsof -i UDP:53 -i TCP:53 2>/dev/null) ]]; then
        logE "Something is already listening on port 53. This will interfere with dnscrypt-proxy."
        logE "Please stop any services using port 53 before running this script."
        exit 1
    fi
}

###################################### DNSCRYPT FUNCTIONS ##########################################

function install_dnscrypt_proxy() {
    logI "Checking for dnscrypt-proxy installation..."
    
    # Check if dnscrypt-proxy is already installed
    if [[ -f "$DNSCRYPT_DIR/dnscrypt-proxy" ]]; then
        logI "dnscrypt-proxy is already installed."
        return 0
    fi
    
    logI "Installing dnscrypt-proxy..."
    
    # Create directory if it doesn't exist
    mkdir -p "$DNSCRYPT_DIR"
    
    # Download dnscrypt-proxy
    logI "Downloading dnscrypt-proxy from $DNSCRYPT_DOWNLOAD_URL"
    curl -L "$DNSCRYPT_DOWNLOAD_URL" -o "/tmp/dnscrypt-proxy.zip"
    
    if [[ $? -ne 0 ]]; then
        logE "Failed to download dnscrypt-proxy."
        exit 1
    fi
    
    # Extract the zip file
    logI "Extracting dnscrypt-proxy..."
    unzip -o "/tmp/dnscrypt-proxy.zip" -d "/tmp/dnscrypt-proxy"
    
    if [[ $? -ne 0 ]]; then
        logE "Failed to extract dnscrypt-proxy."
        exit 1
    fi
    
    # Move files to installation directory
    cp -R /tmp/dnscrypt-proxy/* "$DNSCRYPT_DIR/"
    
    # Make dnscrypt-proxy executable
    chmod +x "$DNSCRYPT_DIR/dnscrypt-proxy"
    
    # Copy example config if needed
    if [[ ! -f "$DNSCRYPT_DIR/dnscrypt-proxy.toml" ]]; then
        cp "$DNSCRYPT_DIR/example-dnscrypt-proxy.toml" "$DNSCRYPT_DIR/dnscrypt-proxy.toml"
    fi
    
    # Clean up temporary files
    rm -rf "/tmp/dnscrypt-proxy" "/tmp/dnscrypt-proxy.zip"
    
    logS "dnscrypt-proxy has been installed successfully."
}

function run_dnscrypt_proxy() {
    logI "Starting dnscrypt-proxy (elevated)..."
    
    # Check if dnscrypt-proxy is already running
    if pgrep -x "dnscrypt-proxy" > /dev/null; then
        logW "dnscrypt-proxy is already running."
        return 0
    fi
    
    # Change to the dnscrypt-proxy directory
    cd "$DNSCRYPT_DIR"
    
    # Run dnscrypt-proxy in the background
    nohup ./dnscrypt-proxy > /dev/null 2>&1 &
    
    # Check if dnscrypt-proxy started successfully
    sleep 2
    if pgrep -x "dnscrypt-proxy" > /dev/null; then
        logS "dnscrypt-proxy is now running."
    else
        logE "Failed to start dnscrypt-proxy."
        exit 1
    fi
}

###################################### NETWORK FUNCTIONS ##########################################

function get_active_NICs() {
    # Fetch all network services, excluding the first line
    interfaces=$(networksetup -listallnetworkservices | tail -n +2)
    active_interfaces=()

    # Iterate over each network service and fetch HTTP proxy settings
    logI "Inspecting NICs..."
    while IFS= read -r service; do
        IPAddr=$(networksetup -getinfo "$service" | grep -E '^IP address: ((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$')
        if [[ -n $IPAddr ]]; then
            logS "$service is active  //  $IPAddr"
            active_interfaces+=("$service")
            
            # Store original DNS settings
            original_dns=$(networksetup -getdnsservers "$service")
            ORIGINAL_DNS_SETTINGS+=("$service:$original_dns")
        else
            logW "$service is inactive, it doesn't have an IP address or a valid one..."
            echo -en "\r\033[2K\033[F\033[2K\033[F\033[2K\033[F\033[2K"
        fi    
    done <<< "$interfaces"
    
    if [[ ${#active_interfaces[@]} -eq 0 ]]; then
        logE "No active network interfaces found."
        exit 1
    fi
    
    return 0
}

function override_DNS_on_interfaces() {
    logI "Overriding DNS settings on active interfaces..."
    
    for service in "${active_interfaces[@]}"; do
        logI "Setting DNS to 127.0.0.1 on $service"
        networksetup -setdnsservers "$service" 127.0.0.1
        
        if [[ $? -eq 0 ]]; then
            logS "DNS override successful for $service"
            MODIFIED_INTERFACES+=("$service")
        else
            logE "Failed to override DNS for $service"
        fi
    done
    
    logI "DNS override complete."
}

function reset_DNS_on_interfaces() {
    logI "Resetting DNS settings on all modified interfaces..."
    
    # If we have stored original settings, use them
    if [[ ${#ORIGINAL_DNS_SETTINGS[@]} -gt 0 ]]; then
        for entry in "${ORIGINAL_DNS_SETTINGS[@]}"; do
            service=${entry%%:*}
            dns_settings=${entry#*:}
            
            # If dns_settings contains "There aren't any DNS Servers", set to empty
            if [[ "$dns_settings" == *"There aren't any DNS Servers"* ]]; then
                logI "Resetting DNS settings to empty for $service"
                networksetup -setdnsservers "$service" empty
            else
                # Otherwise set to the original values
                logI "Restoring original DNS settings for $service: $dns_settings"
                networksetup -setdnsservers "$service" $dns_settings
            fi
            
            if [[ $? -eq 0 ]]; then
                logS "DNS reset successful for $service"
            else
                logE "Failed to reset DNS for $service"
            fi
        done
    else
        # If we don't have stored settings, reset all interfaces to empty
        interfaces=$(networksetup -listallnetworkservices | tail -n +2)
        
        while IFS= read -r service; do
            logI "Resetting DNS settings to empty for $service"
            networksetup -setdnsservers "$service" empty
            
            if [[ $? -eq 0 ]]; then
                logS "DNS reset successful for $service"
            else
                logE "Failed to reset DNS for $service"
            fi
        done <<< "$interfaces"
    fi
    
    logI "DNS reset complete."
}

function stop_dnscrypt_proxy() {
    logI "Stopping dnscrypt-proxy..."
    
    # Check if dnscrypt-proxy is running
    if pgrep -x "dnscrypt-proxy" > /dev/null; then
        # Kill dnscrypt-proxy
        pkill -x "dnscrypt-proxy"
        
        # Check if it was killed successfully
        sleep 1
        if pgrep -x "dnscrypt-proxy" > /dev/null; then
            logE "Failed to stop dnscrypt-proxy."
        else
            logS "dnscrypt-proxy has been stopped."
        fi
    else
        logI "dnscrypt-proxy is not running."
    fi
}

function test_dns_resolution() {
    logI "Testing DNS resolution using nslookup for example.com..."
    
    # Wait a bit to ensure dnscrypt-proxy is fully operational
    logI "Waiting for dnscrypt-proxy to initialize..."
    (
        i=0
        while [ $i -lt 10 ]; do
            sleep 1
            i=$((i+1))
        done
    ) &
    spinner $!
    
    # Test DNS resolution
    local dns_test=$(nslookup example.com 127.0.0.1 2>&1)
    
    # Log the DNS query
    log_to_file "[DNS TEST] Query: example.com"
    log_to_file "[DNS TEST] Result: $dns_test"
    
    # Check if the test was successful
    if echo "$dns_test" | grep -q "Address: "; then
        logS "DNS resolution test successful!"
        
        # Collect all addresses in a single string
        local addresses=$(echo "$dns_test" | grep "Address: " | tr '\n' ' ')
        logI "Resolved: $addresses"
        
        return 0
    else
        logE "DNS resolution test failed."
        logE "nslookup output: $dns_test"
        return 1
    fi
}

###################################### SIGNAL HANDLING ##########################################

function cleanup() {
    logI "Received termination signal. Cleaning up..."
    reset_DNS_on_interfaces
    stop_dnscrypt_proxy
    logI "Cleanup complete. Exiting."
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

###################################### COMMAND LINE ARGUMENTS ##########################################

function show_help() {
    echo -e "${PINK}DNS Override Script${NC}"
    echo "Usage: $scriptname [OPTION]"
    echo ""
    echo "Options:"
    echo "  --help      Display this help message"
    echo "  --version   Display version information"
    echo "  --revert    Remove DNS overrides and restore original settings"
    echo ""
    echo "This script installs and configures dnscrypt-proxy to override DNS settings"
    echo "on all active network interfaces."
}

function show_version() {
    echo -e "${PINK}DNS Override Script${NC} v1.0"
    echo "Author: Florian Bidabe (PhotonSec)"
    echo "A tool to override DNS settings using dnscrypt-proxy."
}

###################################### MAIN EXECUTION ##########################################

# Main function
function main() {
    logI "---   ${PINK}SCRIPT: $current_dir/$scriptname${NC}   ---"
    logI "${PINK}This script is intended to override DNS settings using dnscrypt-proxy${NC}"
    
    # Process command line arguments
    if [[ $# -gt 0 ]]; then
        case "$1" in
            --help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            --revert)
                check_prerequisites
                reset_DNS_on_interfaces
                stop_dnscrypt_proxy
                exit 0
                ;;
            *)
                logE "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    fi
    
    # Initialize log file with script start timestamp
    log_to_file "=== Script execution started ==="
    
    # Run the main script
    check_prerequisites
    install_dnscrypt_proxy
    get_active_NICs
    run_dnscrypt_proxy
    override_DNS_on_interfaces
    
    # Test DNS resolution
    test_dns_resolution
    
    logS "DNS override setup complete. Your DNS queries are now being handled by dnscrypt-proxy."
    logI "To revert changes, press Ctrl+C or run: sudo $scriptname --revert"
    
    # Keep the script running to allow for Ctrl+C to trigger cleanup
    logI "Script is running in the foreground. Press Ctrl+C to stop and revert changes."
    while true; do
        sleep 60
    done
}

# Execute main function
main "$@"
