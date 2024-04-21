import json
import requests
import subprocess
import ipaddress

# Download the AWS IP ranges data
response = requests.get('https://ip-ranges.amazonaws.com/ip-ranges.json')
ip_ranges = json.loads(response.text)

# Function to check if an IP address is in the AWS IP ranges
def find_ip_range(ip_address):
    try:
        # Convert the IP address to an IPv4Address object for comparison
        ip_obj = ipaddress.ip_address(ip_address)
    except ValueError:
        return f"Invalid IP address: {ip_address}."

    # Check each prefix in the AWS IP ranges to see if the IP address falls within
    for prefix in ip_ranges['prefixes']:
        if ip_obj in ipaddress.ip_network(prefix['ip_prefix']):
            return f"IP address {ip_address} is in AWS IP range: {prefix['ip_prefix']}, Region: {prefix['region']}, Service: {prefix['service']}"

    return f"IP address {ip_address} not found in AWS IP ranges."

# Request the user to enter a hostname
hostname = input("Please enter a hostname to check: ")

# Use the dig command to get IP addresses
try:
    result = subprocess.check_output(['dig', hostname, '+short'], text=True)
    ip_addresses = result.strip().split('\n')
except subprocess.CalledProcessError:
    print("Failed to retrieve IP addresses")
    ip_addresses = []

# Check each IP address in the AWS IP range and print the results
for ip in ip_addresses:
    if ip:
        print(find_ip_range(ip))
