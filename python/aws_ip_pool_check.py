import json
import requests
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
        return "Invalid IP address."

    # Check each prefix in the AWS IP ranges to see if the IP address falls within
    for prefix in ip_ranges['prefixes']:
        if ip_obj in ipaddress.ip_network(prefix['ip_prefix']):
            return f"IP address {ip_address} is in AWS IP range: {prefix['ip_prefix']}, Region: {prefix['region']}, Service: {prefix['service']}"
    
    return "IP address not found in AWS IP ranges."

# Request the user to enter an IP address
user_ip = input("Please enter an IP address to check: ")

# Use the function and print the result
result = find_ip_range(user_ip)
print(result)
