# Excluding 192.168.0.0/16 Traffic from GlobalProtect VPN

This solution allows you to route 192.168.0.0/16 traffic through your local network interface instead of through the GlobalProtect VPN tunnel. This is useful for accessing local network resources while connected to the VPN.

## Files

1. `exclude_192_168_from_vpn.sh` - Script that modifies routing tables to exclude 192.168.0.0/16 from VPN
2. `setup_vpn_exclusion.sh` - Setup script that installs everything and creates an alias for easy use

## Quick Setup

Run the setup script with sudo:

```bash
sudo ./setup_vpn_exclusion.sh
```

This will:
1. Install the exclusion script to `/usr/local/bin/`
2. Set up sudo permissions so you can run it without a password
3. Create an alias `exclude192` for easy execution
4. Ask if you want to run it immediately

## Manual Usage

After setup, you can exclude 192.168.0.0/16 from the VPN by simply running:

```bash
exclude192
```

Or you can run it directly:

```bash
sudo /usr/local/bin/exclude_192_168_from_vpn.sh
```

## Testing the Solution

1. Connect to the GlobalProtect VPN
2. Run the exclusion command: `exclude192`
3. Check the routing table:
   ```bash
   netstat -rn | grep 192.168
   ```
4. The output should show that 192.168.0.0/16 is routed through your local network interface, not through the VPN

## How It Works

The script:
1. Identifies your default physical network interface and gateway
2. Deletes the existing route for 192.168.0.0/16 through the VPN
3. Adds a new route for 192.168.0.0/16 through your local network interface
4. Verifies that the route was added correctly

This ensures that traffic to 192.168.0.0/16 networks bypasses the VPN and goes through your local network interface instead.

## Why This Approach?

We initially tried to create an automatic solution using a LaunchAgent, but encountered issues with permissions and reliability. The current approach is simpler and more reliable - just run the command after connecting to the VPN.

## Customization

If you want to exclude different IP ranges, you can modify the `exclude_192_168_from_vpn.sh` script. Look for the lines that mention `192.168.0.0/16` and replace them with your desired IP range.
