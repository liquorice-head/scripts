#!/bin/bash

# Install ZeroTier
curl -s https://install.zerotier.com | sudo bash

# Prompt for network ID
echo "Enter network ID: "
read network_id

# Join the ZeroTier network
sudo zerotier-cli join $network_id

# Enable IP forwarding
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Display IP forwarding status
sudo sysctl net.ipv4.ip_forward

# Find WAN interface name
WAN_IF=$(ip route show default | awk '/default/ {print $5}')

# Find ZeroTier interface name
ZT_IF=$(ip link show | grep 'zt' | awk '{print $2}' | sed 's/://')

# Setup NAT
sudo iptables -t nat -A POSTROUTING -o $WAN_IF -j MASQUERADE

# Setup iptables rules for forwarding
sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i $ZT_IF -o $WAN_IF -j ACCEPT

# Install iptables-persistent and save rules
sudo apt-get install -y iptables-persistent
sudo netfilter-persistent save

# Display current iptables rules
sudo iptables-save

echo "ZeroTier exit node setup complete."
