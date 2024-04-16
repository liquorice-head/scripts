import requests
import csv

# Request input for network ID and API token
network_id = input("Enter the ZeroTier network ID: ")
api_token = input("Enter your API token: ")

# URL for the API request to ZeroTier
url = f'https://my.zerotier.com/api/network/{network_id}/member'

# Headers for authorization
headers = {
    'Authorization': f'Bearer {api_token}'
}

# Send the request
response = requests.get(url, headers=headers)

# Check if the request was successful
if response.status_code == 200:
    members = response.json()
    
    # Check if there are members to write
    if members:
        # Determine all keys from the first member as column headers
        headers = members[0].keys()
        
        # Create a CSV file
        with open('zerotier_members.csv', 'w', newline='') as file:
            writer = csv.DictWriter(file, fieldnames=headers)
            # Write the headers
            writer.writeheader()
            # Write data for each member
            writer.writerows(members)
            
        print("Data successfully saved to 'zerotier_members.csv'.")
    else:
        print("No members found in the network.")
else:
    print("Error while making request to ZeroTier API:", response.status_code)
