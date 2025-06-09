# Modifying Global Proxy Settings via MDM for Traffic Capture

> ## DISCLAIMER: EDUCATIONAL PURPOSE ONLY
>
> This article is provided strictly for educational purposes. Modifying system configurations or tampering with corporate security measures without explicit permission is prohibited and may violate organizational policies, employment agreements, and applicable laws.
>
> This content demonstrates how corporate network defenses might be circumvented, specifically to educate security professionals about potential vulnerabilities. Organizations should implement a defense-in-depth approach with multiple layers of security to protect traffic sent and received from endpoints, including protection against threats from internal users (staff/insiders).
>
> Always obtain proper authorization before implementing any techniques described in this article.

## Table of Contents
- [Introduction](#introduction)
- [What is Charles Proxy?](#what-is-charles-proxy)
- [Understanding Proxy Auto-Configuration (PAC)](#understanding-proxy-auto-configuration-pac)
- [Current vs. Desired Traffic Flow](#current-vs-desired-traffic-flow)
- [Step-by-Step Implementation](#step-by-step-implementation)
- [Troubleshooting](#troubleshooting)
- [Conclusion](#conclusion)

## Introduction

In corporate environments, security teams often need to inspect network traffic for troubleshooting, security analysis, or development purposes. While many organizations implement enterprise-wide proxy solutions, there are scenarios where security professionals need to capture and analyze all traffic from a specific workstation, including system-level communications that might bypass standard proxy configurations.

This article explains how to modify global proxy settings managed by Mobile Device Management (MDM) solutions to route all workstation traffic through Charles Proxy, a popular HTTP debugging proxy application. By understanding this process, security professionals can better implement defense-in-depth strategies to protect corporate networks.

## What is Charles Proxy?

Charles is an HTTP proxy, HTTP monitor, and reverse proxy that enables developers and security professionals to view HTTP and SSL/HTTPS traffic between their machine and the Internet. It allows for inspection and modification of requests and responses, making it valuable for debugging, testing, and security analysis.

## Understanding Proxy Auto-Configuration (PAC)

A Proxy Auto-Configuration (PAC) file is a JavaScript function that determines whether web browser requests go directly to the destination or through a proxy server. In corporate environments, these PAC files are often centrally managed through MDM solutions and cannot be easily modified by end-users.

## Current vs. Desired Traffic Flow

### Current Traffic Flow:

In a typical corporate environment with MDM-enforced proxy settings, traffic flows as follows:

> **GUI & System Applications**: The traffic goes to the Enterprise Proxy or connects directly based on rules in the Enterprise PAC File, this is enforced by a MDM Profile (JAMF) or GPO
> Those settings are typically immutable and taking precedences over any other settings.
> The traffic cannot be "manually" changed, <sub>or at least, it isn't meant to be changed…</sub>

> **Command Line (CLI) Applications**: Traffic can be manually configured to go through Charles → Alpaca → Enterprise Proxy or Direct based on Enterprise PAC File

> **Firefox Browser**: Traffic can be manually configured to go through Charles → Alpaca → Enterprise Proxy or Direct based on Enterprise PAC File

### Desired Traffic Flow:

Our goal is to modify the system to route ALL traffic through Charles for inspection:

> **ALL Traffic (GUI, System, CLI, Browsers)**: Charles → Alpaca → Enterprise Proxy or Direct based on Enterprise PAC File

> **IMPORTANT NOTE**: This configuration will break applications that do not support or tolerate SSL interception, such as those using Mutual TLS (M-TLS), Expect-CT, or Certificate Pinning. If such connections fail, you'll need to exclude the problematic domains in Charles Proxy settings.

## Step-by-Step Implementation

### Step 1: Create a Simple PAC File

First, we need to create a PAC file that directs all traffic to the local Charles proxy:

```javascript
function FindProxyForURL(url, host) {
    return "PROXY localhost:8888";
}
```

This simple PAC file instructs the system to route all traffic through the Charles proxy running on localhost port 8888.

### Step 2: Set Up a local web server hosting the PAC File

Since the MDM expects a URL for the PAC file (not a file:// path), we need to serve our PAC file via HTTP. We'll create a Node.js server for this purpose:

```javascript
const http = require('http');
const fs = require('fs');
const path = require('path');

// Define the path to the proxy.pac file
const homeDir = process.env.HOME || process.env.HOMEPATH || process.env.USERPROFILE;
const proxyPacPath = path.join(homeDir, '.config', 'charles', 'proxy.pac');

// Create the HTTP server
const server = http.createServer((req, res) => {
  // Check if the request is for /proxy.pac
  if (req.url === '/proxy.pac') {
    // Read the file and serve its content
    fs.readFile(proxyPacPath, (err, data) => {
      if (err) {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('File not found');
      } else {
        res.writeHead(200, { 'Content-Type': 'application/x-ns-proxy-autoconfig' });
        res.end(data);
      }
    });
  } else {
    // Handle any other route
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not found');
  }
});

// Have the server listen on port 80
server.listen(80, () => {
  console.log('Server is listening on port 80');
});
```

Save this as `node_pac_server.js` and run it in the background:
You can create a `KeepAlive` LaunchAgent or Daemon if you want this to always be available.

```bash
nohup node $HOME/.config/charles/node_pac_server.js > server.log 2>&1 &
```

You can verify the server is working by checking:
```bash
sudo lsof -i :80 -P -n | grep LISTEN
```
# or
```bash
curl -i http://localhost/proxy.pac
```

![Local PAC file verification](./Proxy-Override_files/local%20pac.png)

### Step 3: Locate the MDM-Managed Proxy Settings

To modify the global proxy settings, we first need to find where the PAC URL is defined in the MDM configuration:

```bash
sudo su -
cd "/Library/Managed Preferences/"
grep -r "pac.internal.company/company.pac" .
```

This will show you which files contain references to the enterprise PAC file.
Typically with JAMF, these will be in: `/Library/Managed Preferences/com.apple.SystemConfiguration.plist`

### Step 4: Modify the System Configuration Files

#### Before making changes, back up the original files:
```bash
ditto com.apple.SystemConfiguration.plist com.apple.SystemConfiguration.plist.bak
ditto ./$(stat -f "%Su" /dev/console)/com.apple.SystemConfiguration.plist ./$(stat -f "%Su" /dev/console)/com.apple.SystemConfiguration.plist.bak
```

#### Convert the binary plist files to XML format for editing:
```bash
plutil -convert xml1 com.apple.SystemConfiguration.plist
plutil -convert xml1 ./$(stat -f "%Su" /dev/console)/com.apple.SystemConfiguration.plist
```

#### Edit the files to replace the enterprise PAC URL with your local one:
```bash
vim com.apple.SystemConfiguration.plist
vim ./$(stat -f "%Su" /dev/console)/com.apple.SystemConfiguration.plist
```

![Profile Edit screenshot](./Proxy-Override_files/Profile%20Edit.png)

#### Replace ProxyAutoConfigURLString value from the enterprise PAC URL to:
`http://localhost/proxy.pac`

#### Convert the files back to binary format:
```bash
plutil -convert binary1 com.apple.SystemConfiguration.plist
plutil -convert binary1 ./$(stat -f "%Su" /dev/console)/com.apple.SystemConfiguration.plist
```

#### Verify the changes (this will not perform any conversion…):
```bash
plutil -convert xml1 -o - com.apple.SystemConfiguration.plist
plutil -convert xml1 -o - ./$(stat -f "%Su" /dev/console)/com.apple.SystemConfiguration.plist
```

### Step 5: Protect Changes from Being Overwritten

To prevent the MDM from overwriting our changes, we can set system immutable flags on the files:

```bash
chflags schg com.apple.SystemConfiguration.plist
chflags schg ./$(stat -f "%Su" /dev/console)/com.apple.SystemConfiguration.plist
```

Reboot the system for changes to take effect: `sudo reboot`

### Step 6: Verify the Configuration

After rebooting, check that the proxy settings are correctly applied: `scutil --proxy`

This should show that the system is using your local PAC file.

You should now see tons of traffic going through Charles
(all the MacOS system web queries essentially…)

![Charles Proxy output showing traffic](./Proxy-Override_files/output.gif)

## Troubleshooting

### SSL Interception Issues:

Some applications and services use certificate pinning or other security measures that prevent SSL interception. If you encounter connection issues with specific applications, you'll need to exclude their domains from SSL interception in Charles:

1. Open Charles Proxy
2. Go to Proxy > SSL Proxying Settings
3. Add the problematic domains to the "Exclude" list

### Reverting Changes:

If you need to revert the changes or make further modifications:

Remove the system immutable flags:

```bash
chflags noschg /Library/Managed\ Preferences/com.apple.SystemConfiguration.plist
chflags noschg /Library/Managed\ Preferences/$(stat -f "%Su" /dev/console)/com.apple.SystemConfiguration.plist
```

Either restore from backup or edit the files again to revert the changes.

## Conclusion

By modifying the MDM-managed proxy settings, we can route all system traffic through Charles Proxy for inspection and analysis. This technique provides valuable insights for security professionals, developers, and system administrators who need to troubleshoot or analyse network traffic in corporate environments.

### Security Implications:

Understanding this technique is crucial for security teams to:

1. Recognise potential vulnerabilities in their proxy configuration
2. Implement additional security measures to prevent unauthorized modifications
3. Consider defense-in-depth approaches that don't rely solely on proxy settings
4. Monitor for unauthorized changes to system configuration files

By implementing proper security controls and monitoring, organisations can better protect their networks while still allowing legitimate traffic inspection when necessary.
