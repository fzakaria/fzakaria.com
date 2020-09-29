---
layout: post
title: VPNs continued
date: 2020-09-23 21:46 -0700
excerpt_separator: <!--more-->
---

> This is _part 2_ of a post regarding VPNs. Please see [here]({% post_url 2020-09-20-vpns-from-first-principles %}) for part 1.

In the [previous post]({% post_url 2020-09-20-vpns-from-first-principles %}), we discussed the basics of setting up a virtual private network; the goal of which was bridging two distinct private subnets.

This gave us the alluring property of treating separate networks as they were colocated and can be accessed easily. However most people are first introduced into VPNs for other features such as: _anonymity_, _secrecy_ & _privacy_.

> A common example may be to tunnel traffic through a host in another country to disguise the origin. For instance, maybe you are in Canada but want to browse the American Netflix catalog.

_How can we extend [lametun](https://github.com/fzakaria/lametun) to do this?_

I'll present a few alternatives. The main goal however will to forward all traffic, including ones destined for the Internet, through the tunnel.

<!--more-->
### Common Setup

In both alternatives, we will want to make some adjustments to our server. We will want to **enable** _ip_forward_ & **disable** _rp_filter_. [^1] We also want to create an _iptable_ rule to setup a NAT.

_ip_forward_
: IP forwarding is the ability for an operating system to accept incoming network packets on one interface, recognize that it is not meant for the system itself, but that it should be passed on to another network, and then forwards it accordingly.

_rp_filter_
: Reverse Path filtering is a mechanism to check whether a receiving packet source address is routable. The machine will first check whether the source of the received packet is reachable through the interface it came in. If it is not routable, it will *drop the packet.

```bash
sysctl -w "net.ipv4.conf.all.rp_filter=0"
sysctl -w "net.ipv4.ip_forward=1"
```

Now on **the server**, we will introduce an _iptable_ rule to forward all incoming packets from our _tun0_ device to _eth0_, or whatever our physical device is.
Furthermore, we will set the target to _MASQUERADE_.

_MASQUERADE_
: Masks requests from LAN nodes with the IP address of the physical device; it is used in conjunction with NAT.

```bash
# The -j MASQUERADE target is specified to mask the private IP address of a node
# with the external IP address of the firewall/gateway
# POSTROUTING allows packets to be altered as they are leaving the device
# The -t nat creates the rule on the NAT table for address translation
sudo iptables -t nat -A POSTROUTING -o eth0 -s 172.31.255.7 -j MASQUERADE
```

_The reason why the NAT is necessary?_

Well if the packets destined for the Internet were sent off with the _source IP_ of our new private CIDR (i.e. 172.31.255.7 for tun0), how would they ever route back to the machine?

> It's not clear yet to me whether you can fake or respond to ARP requests to have the other private IP route back. I'd love to hear [from you](mailto:farid.m.zakaria@gmail.com) if you think it can!

### Approach #1: routing rules

Now that our server is setup to forward all traffic to _eth0_ using the _iptable rule_, our remaining action is to make sure our public traffic flows through our _tun0_ device.

We will use Linux's support for multiple routing tables,[^2] to accomplish this goal. We will create a new routing table _lametun_, which is referred to when the _source IP_ of the packet is that of our _tun0_ device.

The route table _lametun_, only needs a **single** entry. Route everything through the _tun0_ device!

```bash
# Add the rule if the src address is our tun0 addr then
# lookup the lametun routing table
❯ sudo ip rule add from 172.31.255.7 lookup lametun

❯ sudo ip rule show table lametun
5209:   from 172.31.255.7 lookup lametun

# Add the single route to send all traffic to our "gateway" (the tunnel)
❯ sudo ip route add default via 172.31.255.7 dev tun0 table lametun

❯ sudo ip route show table lametun
default via 172.31.255.7 dev tun0

```

Now let's try to use _ping_ but have it select the _source IP_ to that of our _tun0_ device; let's `ping 8.8.8.8`.

```bash
❯ ping -I tun0 8.8.8.8
PING 8.8.8.8 (8.8.8.8) from 172.31.255.7 tun0: 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=112 time=9.09 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=112 time=9.03 ms
```

Let's prove though that this traffic is going through our tunnel by using [tshark](https://www.wireshark.org/docs/man-pages/tshark.html).

```bash
# Running this on the laptop
❯ sudo tshark -i tun0 icmp
Running as user "root" and group "root". This could be dangerous.
Capturing on 'tun0'
    1 0.000000000 172.31.255.7 ? 8.8.8.8      ICMP 84 Echo (ping) request  id=0x3f0d, seq=17/4352, ttl=64
    2 0.008801187      8.8.8.8 ? 172.31.255.7 ICMP 84 Echo (ping) reply    id=0x3f0d, seq=17/4352, ttl=112 (request in 1)
    3 1.000493576 172.31.255.7 ? 8.8.8.8      ICMP 84 Echo (ping) request  id=0x3f0d, seq=18/4608, ttl=64
    4 1.009073436      8.8.8.8 ? 172.31.255.7 ICMP 84 Echo (ping) reply    id=0x3f0d, seq=18/4608, ttl=112 (request in 3)

# Running this on the server
❯ sudo tshark -i tun0 icmp
Running as user "root" and group "root". This could be dangerous.
Capturing on 'tun0'
    1 0.000000000 172.31.255.7 → 8.8.8.8      ICMP 84 Echo (ping) request  id=0x3f0d, seq=88/22528, ttl=64
    2 0.002077891      8.8.8.8 → 172.31.255.7 ICMP 84 Echo (ping) reply    id=0x3f0d, seq=88/22528, ttl=112 (request in 1)
❯ sudo tshark icmp
Running as user "root" and group "root". This could be dangerous.
Capturing on 'eth0'
    1 0.000000000 172.31.9.116 → 8.8.8.8      ICMP 98 Echo (ping) request  id=0x3f0d, seq=110/28160, ttl=63
    2 0.002246902      8.8.8.8 → 172.31.9.116 ICMP 98 Echo (ping) reply    id=0x3f0d, seq=110/28160, ttl=113 (request in 1)
```

Sweet! _Validated_.

We even can see the IP being _masqueraded_ from _172.31.255.7_ -> _172.31.9.116_ as it leaves the server.

Since my server is in AWS, ultimately the _public IP_ seen by the Internet will be that attached to my server. With this setup, we now can conceal our source physical location by having a server masquerade as us :)

### Approach #2: network namespace

Routing tables work great, however they rely on the ability to tell the desired process what _source IP_ to use when opening the socket; that is not always plausible.

Consider an application like Chrome or Firefox, it does not expose a method in which to control which _source IP_ it uses.

For such cases, we will rely on a more thorough setup using _network namespaces_.

> A network namespace is logically another copy of the network stack,
> with its own routes, firewall rules, and network devices.

First let's setup the network namespace using a _virtual ethernet device_ that we will use to bridge the network namespace & the host namespace.
```bash
# Create a new network namespace
❯ sudo ip netns add lametun

# Create a virtual ethernet device which will help move traffic
# from the netns to the host namespace
# Consider this like a wire connecting our network namespcae &
# the host namespace.
❯ sudo ip link add veth0 type veth peer name veth1
❯ sudo ip link set up dev veth0
# Let's give it it's own subnet for simplicity
❯ sudo ip addr add 10.0.0.7/24 dev veth0

# Move the veth1 to the lametun network namespace
❯ sudo ip link set veth1 netns lametun
# Make sure to give it in an address in the same subnet
# and set all the devices up!
❯ sudo ip netns exec lametun ip addr add 10.0.0.3/24 dev veth1
❯ sudo ip netns exec lametun ip link set up dev veth1

# Let's verify we can ping our virtual ethernet devices!
❯ sudo ip netns exec lametun ping 10.0.0.7
PING 10.0.0.7 (10.0.0.7) 56(84) bytes of data.
64 bytes from 10.0.0.7: icmp_seq=1 ttl=64 time=0.070 ms
64 bytes from 10.0.0.7: icmp_seq=2 ttl=64 time=0.147 ms
```

Now let's add Internet access!

> If there is a simpler approach using bridges, macvlan or ipvlan [let me know](mailto:farid.m.zakaria@gmail.com). I didn't want to move the IP address from my main ethernet device to the bridge, so this approach seemed easy enough but it needs _iptables_.

```bash
# Let's add our default route to go the other veth which will act
# as our router
sudo ip netns exec lametun ip route add default via 10.0.0.7

# It's not 100% clear this is needed since we have enabled ip_forward,
# however for now it's enabled to help send the packets up/down the physical
# device
❯ sudo iptables -A FORWARD -o eth0 -i veth0 -j ACCEPT
❯ sudo iptables -A FORWARD -i eth0 -o veth0 -j ACCEPT

# We then need to NAT the veth IP similar to how we did in the server.
# Here however we make sure we just set the source to be the whole subnet.
❯ sudo iptables -t nat -A POSTROUTING -o eth0 -s 10.0.0.0/24 -j MASQUERADE

# Test out we can ping from inside the namespace
❯ sudo ip netns exec lametun ping 8.8.8.8
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=115 time=6.28 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=115 time=5.77 ms
```

Great! We have Internet traffic but it's just going through the typical flow.

We can now start **lametun** inside this network namespace and all _default traffic_ will go through our VPN!

```bash
# Create the TUN device in the namespace & set it up
sudo ip netns exec lametun ip tuntap add dev tun0 mode tun user $USER
sudo ip netns exec lametun ip link set dev tun0 up
sudo ip netns exec lametun ip addr add 172.31.255.7/24 dev tun0
# Set the default route to be sending all traffic to the tun0 device
sudo ip netns exec lametun ip route add default via 172.31.255.7

# This is super important so we don't create a closed loop.
# We need to make sure to send the tunnel not through itself.
# We route the VPN IP route directly to our veth1 address
sudo ip netns exec lametun ip route add 54.219.126.112 via 10.0.0.7

# Start the tunnel and enjoy!
sudo ip netns exec lametun ./lametun -server 54.219.126.112
listen:false server:54.219.126.112 dev:tun0 port:1234
```

The final _cherry on top_, is to make sure DNS works inside the namespace.
For that let's create a file **/etc/netns/lametun/resolv.conf** with the following contents:

```bash
❯ cat /etc/netns/lametun/resolv.conf
nameserver 8.8.8.8
```

We now have a _really lame_ VPN that you can use to try and add some level of indirection to your requests. Just make sure to star the desired process within the network namespace.

[^1]: <https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt>
[^2]: <http://linux-ip.net/html/routing-tables.html>