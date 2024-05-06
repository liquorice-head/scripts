import os

# Reading credentials from the 'credentials' file
print("Reading credentials...")
with open('credentials', 'r') as f:
    credentials = f.readline().strip().split(':')
username = credentials[0]
password = credentials[1]
print("Username:", username)

# Displaying the contents of the 'ips' file
print("Contents of the ips file:")
with open('ips', 'r') as f:
    print(f.read())
print("End of file")

# Ensure the backups directory exists
if not os.path.exists("backups"):
    os.makedirs("backups")

# Starting to process each IP from the 'ips' file
print("Starting to process each IP...")
with open('ips', 'r') as f:
    for ip in f:
        ip = ip.strip()  # Remove leading/trailing whitespace
        if not ip:
            continue  # Skip empty lines

        print("Attempting to connect to", ip + "...")

        # Connect to MikroTik and execute the 'system identity print' command using sshpass
        os.system(f'sshpass -p "{password}" ssh -o StrictHostKeyChecking=no {username}@{ip} \'/system identity print\' > output.txt')

        # Extract the system name
        with open('output.txt', 'r') as output_file:
            for line in output_file:
                if 'name:' in line:
                    name = line.split(':')[1].strip()
                    break

        print("Extracted name:", name)

        # Execute the export command on the MikroTik device using sshpass
        os.system(f'sshpass -p "{password}" ssh -o StrictHostKeyChecking=no {username}@{ip} "/export file={name}"')
        print("Export command executed for", name)

        # Delay to ensure file is created
        import time
        time.sleep(5)

        # List files to verify existence
        os.system(f'sshpass -p "{password}" ssh -o StrictHostKeyChecking=no {username}@{ip} "/file print"')

        # Download the file to the local machine using sshpass
        print("Attempting to download", name + ".rsc" + "...")
        return_code = os.system(f'sshpass -p "{password}" scp -o StrictHostKeyChecking=no {username}@{ip}:/{name}.rsc ./backups/{name}.rsc')
        if return_code == 0:
            print("File", name + ".rsc", "successfully downloaded to backups folder")
        else:
            print("Failed to download", name + ".rsc")

print("All devices processed.")
