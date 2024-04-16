import paramiko

# Load the list of IP addresses
with open('ip_list.txt') as f:
    ip_list = f.read().splitlines()

# Load the credentials
with open('credentials.txt') as f:
    username, password = f.read().splitlines()

# Commands to be executed
commands = [
    'grep serialno /proc/ubnthal/system.info',
    'uname -n'
]

# Output file for the results
output_file = 'output.txt'

with open(output_file, 'w') as f_out:
    for ip in ip_list:
        # Create an SSH client
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        
        try:
            # Connect to the device
            client.connect(ip, username=username, password=password)
            results = []

            for command in commands:
                stdin, stdout, stderr = client.exec_command(command)
                # Strip newlines and add output to the results list
                result = stdout.read().decode().strip()
                results.append(result)
            
            # Join the results into one line and write to the file
            f_out.write(f"{ip}: {' | '.join(results)}\n")
        except Exception as e:
            f_out.write(f'{ip}: Error in connection or command execution - {e}\n')
        finally:
            client.close()
