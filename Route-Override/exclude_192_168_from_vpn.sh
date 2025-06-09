#!/bin/bash

# Script to exclude 192.168.0.0/16 traffic from GlobalProtect VPN
# This will route 192.168.0.0/16 traffic through your local network interface
# instead of through the VPN tunnel (utun4)

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo)"
  exit 1
fi

echo "Excluding 192.168.0.0/16 from GlobalProtect VPN routing..."

# Get the default physical interface (likely en0 for Wi-Fi or en5 for Ethernet)
# This command finds the interface that has the default route that's not utun4
DEFAULT_INTERFACE=$(netstat -rn | grep default | grep -v utun | head -1 | awk '{print $NF}')

if [ -z "$DEFAULT_INTERFACE" ]; then
  echo "Error: Could not determine default physical interface"
  exit 1
fi

echo "Using $DEFAULT_INTERFACE as the default physical interface"

# Get the gateway for the default interface
DEFAULT_GATEWAY=$(netstat -rn | grep default | grep "$DEFAULT_INTERFACE" | head -1 | awk '{print $2}')

if [ -z "$DEFAULT_GATEWAY" ]; then
  echo "Error: Could not determine default gateway"
  exit 1
fi

echo "Using $DEFAULT_GATEWAY as the default gateway"

# Delete the existing route for 192.168.0.0/16 through the VPN
echo "Deleting existing route for 192.168.0.0/16..."
/sbin/route delete -net 192.168.0.0/16 > /dev/null 2>&1

# Add a new route for 192.168.0.0/16 through the physical interface
echo "Adding new route for 192.168.0.0/16 through $DEFAULT_INTERFACE..."
/sbin/route add -net 192.168.0.0/16 $DEFAULT_GATEWAY -ifp $DEFAULT_INTERFACE

# Verify the route was added
echo "Verifying route..."
netstat -rn | grep 192.168

echo "Done! 192.168.0.0/16 traffic should now bypass the VPN."
echo "To make this change permanent, you'll need to run this script after each VPN connection."
echo "You can automate this by creating a launch agent or daemon."
