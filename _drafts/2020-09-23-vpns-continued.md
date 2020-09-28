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

Now on the server, we will introduce an _iptable_ rule to forward all incoming packets from our _tun0_ device to _eth0_, or whatever our physical device is.
Furthermore, we will set the target to _MASQUERADE_.

_MASQUERADE_
: Masks requests from LAN nodes with the IP address of the physical device; it is used in conjunction with NAT.

```bash
# The -j MASQUERADE target is specified to mask the private IP address of a node with the external IP address of the firewall/gateway
# POSTROUTING allows packets to be altered as they are leaving the device
# The -t nat creates the rule on the NAT table for address translation
sudo iptables -t nat -A POSTROUTING -o eth0 -s 172.31.255.7 -j MASQUERADE
```

The reason why the NAT is necessary?

Well if the packets destined for the Internet were sent off with the _source IP_ of our new private CIDR (i.e. 172.31.255.7 for tun0), how would they ever route back to the machine?

> It's not clear yet to me whether you can fake or respond to ARP requests to have the other private IP route back. I'd love to hear [from you](mailto:farid.m.zakaria@gmail.com) if you think it can!

### Routing Rules

Now that our server is setup to forward all traffic to _eth0_ using the _iptable rule_, our remaining action is to make sure our public traffic flows through our _tun0_ device.

We will use Linux's support for multiple routing tables,[^2] to accomplish this goal. We will create a new routing table _lametun_, which is referred to when the _source IP_ of the packet is that of our _tun0_ device.

The route table _lametun_, only needs a **single** entry. Route everything through the TUN device!

```bash
❯ sudo ip rule add from 172.31.255.7 lookup lametun

❯ sudo ip rule show table lametun
5209:   from 172.31.255.7 lookup lametun

❯ sudo ip route add default via 172.31.255.7 dev tun0 table lametun

❯ sudo ip route show table lametun
default via 172.31.255.7 dev tun0

```

Now let's try to use `ping` but have it select the _source IP_ to that of our _tun0_ device; let's ping 8.8.8.8.

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

### network namespace

Routing tables work great, however they rely on the ability to tell the desired process what _source IP_ to use when opening the socket; that is not always plausible.

Consider an application like Chrome or Firefox, it does not expose a method in which to control which _source IP_ it uses.

For such cases, we will rely on a more thorough setup using _network namespaces_.

> A network namespace is logically another copy of the network stack,
> with its own routes, firewall rules, and network devices.

```bash
# Create a new network namespace
❯ sudo ip netns add lametun

# Move the tun0 interface to our new network namespace
❯ sudo ip link set tun0 netns lametun

# Now let's enter the network namespace
❯ sudo ip netns lametun $SHELL

# We have to recreate our IP annoyingly on tun0
❯ ip link set dev tun0 up
❯ ip addr add 172.31.255.7/24 dev tun0

# Create the route rule
❯ ip route add default via 172.31.255.7 dev tun0
```

[^1]: <https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt>
[^2]: <http://linux-ip.net/html/routing-tables.html>