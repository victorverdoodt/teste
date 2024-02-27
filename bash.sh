#!/bin/bash
set -x
# set up install and uninstall directives
A=-A
I=-I
if [[ "$1" == "down" ]]; then
  A=-D
  I=-D
fi

ip4_localip=10.0.0.122
ip4_wg_subnet=10.8.0
ip4_source=$ip4_wg_subnet.10
ip4_dest=$ip4_wg_subnet.11

# SET PUBLIC IP INTERFACE NAME
ni=enp0s3
# SET WIREGUARD INTERFACE NAME
wg=wg0
# SET FORWARDED PORTS
TCP_PORTS="25 110 143 465 587 993 995 4190"

# Accept it all.
# Per docker manual, Docker requires forwards to be on its chain
# use DOCKER-USER instead of FORWARD
sudo iptables $I DOCKER-USER -s $ip4_wg_subnet.0/24 -j ACCEPT
sudo iptables $I DOCKER-USER -m state --state RELATED,ESTABLISHED -j ACCEPT
# Source nat.
sudo iptables -t nat $A POSTROUTING -s $ip4_wg_subnet.0/24 ! -d $ip4_wg_subnet.0/24 -j SNAT --to $ip4_localip
# Masquerade.
sudo iptables -t nat $A POSTROUTING -o $wg -j MASQUERADE

for p in $TCP_PORTS
do
    # Allow traffic on specified ports.
    sudo iptables $A DOCKER-USER -i $ni -o $wg -p tcp --syn --dport $p -m conntrack --ctstate NEW -j ACCEPT
    # Forward traffic from public network to wireguard on specified ports
    sudo iptables -t nat $A PREROUTING -i $ni -p tcp --dport $p -j DNAT --to-destination $ip4_dest
    # Forward traffic from wireguard back to public network on specified ports
    sudo iptables -t nat $A POSTROUTING -o $wg -p tcp --dport $p -d $ip4_dest -j SNAT --to-source $ip4_source
done
