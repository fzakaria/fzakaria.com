---
layout: post
title: VPNs from first principles
date: 2020-09-20 10:17 -0700
excerpt_separator: <!--more-->
---

> If you enjoy the _from first principles_ theme, consider reading the one
> on [containers]({% post_url 2020-05-31-containers-from-first-principles %}).

Networking can seem like _voodoo_; many of us take for granted how data transmits from one computer to the next. Recently, [wireguard](https://www.wireguard.com/), has attracted a lot of publicity for it's inclusion into the Linux kernel & for it's stated goal of making setting up VPNs simpler.

Behind all the magic, is a very simple premise. Let's shed some of the complexity and break it down to _first principles_.

<!--more-->

> A virtual private network extends a private network across a public network and enables users to send and receive data across shared or public networks as if their computing devices were directly connected to the private network. [^1] [^2]

![VPN graphic](/assets/images/VPN_overview-en.svg)

The definition seems _simple_ enough. Bridge two discrete private networks & make them look like they are **one**.

We will accomplish this task with a _tunnel_.

<!--more-->

### Network Reachability

Let's consider a very simple example with two distinct private networks: _home_ & _office_.

**Home Network**: A 192.168.1.0/24 subnet and has a laptop with the _private IP address_ of 192.168.1.192.

**Office Network**: A 172.31.0.1/20 subnet and has a server with _private IP address_ of 172.31.9.116 & a _public IP address_ of 54.219.126.112.

![VPN graphic](/assets/images/vpn_simple_drawing.png)

> I did not include the routers or gateways in the figure.

This is pretty common to what most people might experience with their home setup.

_private_ IP addresses are those that can only be reached from other machines within the subnet.

_public_ IP addresses are those that are broadcasted to neighboring routers and exchanged via the BGP protocol.

The goal of the tunnel will be to join these two _distinct_ subnets into a _virtual_ one; a _virtual private network_ (VPN).

![VPN graphic](/assets/images/vpn_simple_drawing_merge.png)

Let's choose a VPN CIDR range of 172.31.255.0/24. I don't need a subnet so large, so let's set a mask of /24 which gives us ~254 hosts.

We will then assign two IP addresses within that subnet to the two hosts.

**Server**: 172.31.255.13

**Laptop**: 172.31.255.7

> The private network address range is 172.16.0.0/12 according to <https://www.arin.net/reference/research/statistics/address_filters/>

### TUN network interface device

The first step in setting up our tunnel will be to create a _tun_ network interface device[^3]. A _tun_ device is a kernel virtual network device, they are not backed by a physical device.

Packets sent by the operating system via the _tun_ device are delivered to a user space program which attaches itself to the device. A userspace program may also pass packets into a _tun_ device. In this case the device delivers these packets to the operating-system network stack thus emulating as if it has arrived from an external source.[^4]

> _tun_ devices operate at the L3 layer (IP). There is an analogous _tap_ device that operates at the L2 layer (Ethernet).

```bash
# on server & laptop run the following
# adding the user will allow userspace programs running as that user
# to attach to it without needing `sudo`
> sudo ip tuntap add dev tun0 mode tun user $USER
> sudo ip link set dev tun0 up

> ip -d link show tun0
9: tun0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP mode DEFAULT group default qlen 500
    link/none  promiscuity 0 minmtu 68 maxmtu 65535
    tun type tun pi on vnet_hdr off persist on user youruser addrgenmode random numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535
```

We then need to assign the new _private IP addresses_ for our new subnet.

```bash
# on the laptop run the following
> sudo ip addr add 172.31.255.7/24 dev tun0
# on the server run the following
> sudo ip addr add 172.31.255.13/24 dev tun0
```

Now let's create a general routing rule so that anything destined for that subnet routes to the desired _tun_ device.

```bash
# run the following on both laptop & server
> sudo ip route add 172.16.0.0/12 dev tun0

# Let's validate our route. Pick a machine and
# test the route for the other one.
> ip route get 172.31.255.8
172.31.255.8 dev tun0 src 172.31.255.7 uid 780412
    cache
```

> We make sure to test the route with an IP address not present on either machine, otherwise it will match to the _lo_ (loopback) device.

Great! We have setup some network interfaces and routing rules, but what is actually transmitting the packets to give the _illusion_ of a single network?

Our **tunneling** software.

### lametun

The _heart_ to setting up VPN is the software bridging the packets across the two networks. In our case, we will be using a userspace program and the _tun_ device; however [wireguard](https://www.wireguard.com/) has included this capability within the kernel itself.

Since this will be a _toy_ example, I've named the program **lametun**. It will be a single _golang_ file with minimal dependencies to demonstrate how simple it is.

![VPN graphic](/assets/images/vpn_lametun_simple.png)

**lametun** will read all incoming packets at a particular UDP port (i.e. _1234_) and write it to the _tun_ device.

**lametun** will read all outgoing packets from the _tun_ device and write it back out the physical network device.

Both the _server_ & _laptop_ will run **lametun** on UDP port _1234_, listening on the physical network device.

> Make sure your firewall allows whatever port we are using for **lametun**.
I was using an EC2 host and had to also allow the UDP port through the SecurityGroup as well.

The TUN device however emits raw L3 packets (IP packets), and the IP address of the device is not-routable. Simply copying the packet to the physical device is not enough; it must be routable.

We will _encapsulate_ the packet with a routable IP & UDP header destined for the VPN peer.

> UDP is chosen since there is a lot of literature how TCP over TCP is a bad idea; TCP Meltdown.[^6]

### Encapsulation

Encapsulation as a concept is straightforward. It is the act of embedding a protocol within the data/payload of another. Here we see an example of embedding TCP-IP within the payload of a UDP packet.[^5]

![VPN graphic](/assets/images/foo-encap.png)

Using encapsulation, we can now have non-routable packets traverse the Internet. Once they arrive at the **lametun** destination, the inner packet is forwarded onto the _tun_ device to continue routing.

### MTU

Typically, in order to guarantee delivery across the Internet, network devices restrict the _maximum transmission unit_ (MTU), which is the size of the Ethernet frame, to _1500_ bytes.

> Although IP protocol supports fragmentation, there is no guarantee that every link along the way does. It's best to stay within the 1500 byte limit.

Given that we are embedding our transmission protocol within a IP-UDP datagram, we must account for this reserved headroom accordingly or risk breaking the 1500 byte boundary.

Given that the IP header is 20 bytes (minimum) and the UDP header is 8 bytes, our new MTU is _1472_ bytes.

A simple demonstration will help.

```bash
# Upper limit MTU is 1500 safely across the Internet
# IPv4 header is 20 bytes (minimum)
# UDP header is 8 bytes
# ICMP header is 8 bytes
#
# 1500 - 20 (IP) - 8 (UDP) =  1472 new maximum MTU
#
# 1472 - 20 (IP) - 8 (ICMP) = 1444 maximum payload for ICMP payload
# (We actually remove another 4 bytes due to metadata the TUN device includes)
# = 1440 maximum payload

# We will run the following on the laptop
> ping -M do -s 1440 172.31.255.13

# Use wireshark to check the packet
> tshark udp port 1234
1 0.000000000 76.242.91.200 → 172.31.9.116 UDP 1514 1234 → 1234 Len=1472

# If we bump the ICMP payload by a single byte, it will fragment
> ping -M do -s 1441 172.31.255.13

> sudo tshark udp port 1234
1 0.000000000 76.242.91.200 → 172.31.9.116 IPv4 1514 Fragmented IP protocol (proto=UDP 17, off=0, ID=3136)
```

So we simply need to adjust the MTU on our TUN device accordingly.

```bash
# run the following on both laptop and server
> sudo ip link set dev tun0 mtu 1472
```

### Code

Sweet! Enough theory, show me the code!

I've kept the code to a single-file for demonstration purposes but you can also find it on GitHub <https://github.com/fzakaria/lametun>. It is heavily commented for learning purposes.

> I tried to make the code somewhat Go-idiomatic without being too pedantic as a learning exercise. If you feel the code can be improved, please [reach out](mailto:farid.m.zakaria@gmail.com) or open a pull-request.

```go
package main

import (
    "flag"
    "fmt"
    "golang.org/x/sys/unix"
    "net"
    "os"
    "unsafe"
)

const (
    // sizeof(struct ifreq)
    IfReqSize = 40
)

// let's open the TUN device
// A tun device is a bit wonky in that you have to first open "/dev/net/tun"
// then run a IOCTL syscall to turn the fd returned for the desired network tun device.
// This code makes use of some unsafe golang code, this is merely to avoid pulling in
// dependencies since this is for demonstration
func openTunDevice(dev string) (*os.File, error) {
    fd, err := unix.Open("/dev/net/tun", os.O_RDWR, 0)
    if err != nil {
        return nil, err
    }

    // IOCTL for TUN requires the ifreq struct
    // https://elixir.bootlin.com/linux/v5.8.10/source/include/uapi/linux/if.h#L234
    // we fill in the required struct members such as the device name & that it is a TUN
    var ifr [IfReqSize]byte
    copy(ifr[:], dev)
    *(*uint16)(unsafe.Pointer(&ifr[unix.IFNAMSIZ])) = unix.IFF_TUN

    _, _, errno := unix.Syscall(
        unix.SYS_IOCTL,
        uintptr(fd),
        uintptr(unix.TUNSETIFF),
        uintptr(unsafe.Pointer(&ifr[0])),
    )

    if errno != 0 {
        return nil, fmt.Errorf("error syscall.Ioctl(): %v\n", errno)
    }

    unix.SetNonblock(fd, true)
    return os.NewFile(uintptr(fd), "/dev/net/tun"), nil
}

func main() {
    port := flag.Int("port", 1234, "The protocol port for lametun")
    dev := flag.String("device", "tun0", "The TUN device name")
    listen := flag.Bool("listen", false, "Whether to designate this machine as the server")
    server := flag.String("server", "", "The server to connect to")
    flag.Parse()

    fmt.Printf("listen:%v server:%v dev:%v port:%v\n", *listen, *server, *dev, *port)

    if *listen && *server != "" {
        fmt.Fprintf(os.Stderr, "Cannot listen and set server flag\n")
        os.Exit(1)
    }

    if !*listen && *server == "" {
        fmt.Fprintf(os.Stderr, "You must specify the server or mark this host to listen\n")
        os.Exit(1)
    }

    tun, err := openTunDevice(*dev)
    if err != nil {
        panic(err)
    }

    conn, err := net.ListenUDP("udp4", &net.UDPAddr{Port: *port})
    if err != nil {
        panic(err)
    }
    defer conn.Close()

    var raddr net.Addr
    quit := make(chan struct{})

    if *server != "" {
        raddr, err = net.ResolveUDPAddr("udp", fmt.Sprintf("%s:%d", *server, *port))
        if err != nil {
            panic(err)
        }
    }

    go func() {
        // we make sure to pick a buffer size at least greater than our MTU
        // 2048 is much larger :)
        buffer := make([]byte, 2048)
        for {
            bytes, addr, err := conn.ReadFromUDP(buffer)
            if err != nil {
                fmt.Fprintf(os.Stderr, "error reading from UDP connection: %v\n", err)
                break
            }

            fmt.Printf("Writing %d bytes to the tun device.\n", bytes)
            raddr = addr

            // write to the tun device
            _, err = tun.Write(buffer[:bytes])
            if err != nil {
                fmt.Fprintf(os.Stderr, "error writing to tun: %v\n", err)
                break
            }
        }

        // signal to terminate
        quit <- struct{}{}
    }()

    go func() {
        for {
            // we make sure to pick a buffer size at least greater than our MTU
            // 2048 is much larger :)
            buffer := make([]byte, 2048)

            bytes, err := tun.Read(buffer)
            if err != nil {
                fmt.Fprintf(os.Stderr, "error reading from tun: %v\n", err)
                break
            }

            fmt.Printf("Read %d bytes from the tun device.\n", bytes)

            if raddr == nil {
                fmt.Printf("UDP connection to server has not been established yet.\n")
                continue
            }

            // at this point the buffer is a complete UDP packet; let's forward it to our UDP peer
            _, err = conn.WriteTo(buffer[:bytes], raddr)
            if err != nil {
                fmt.Fprintf(os.Stderr, "error writing to UDP connection: %v\n", err)
                break
            }
        }

        // signal to terminate
        quit <- struct{}{}
    }()

    // wait until an error is given
    <-quit
}
```

Running the code is quite simple.
```bash
# the server runs it in listen mode
> ./lametun -listen

# the client needs to provide the server's IP
> ./lametun -server 54.219.126.112

# We can now ping the server from our laptop through the private IP!
> ping 172.31.255.13
PING 172.31.255.13 (172.31.255.13) 56(84) bytes of data.
64 bytes from 172.31.255.13: icmp_seq=1 ttl=64 time=6.42 ms
64 bytes from 172.31.255.13: icmp_seq=2 ttl=64 time=6.33 ms

```

### Encryption & NAT

In order to simplify the tunneling code & avoid having to solve cases where both machines are behind a NAT, **lametun** requires that one peer acts as the "server"; it must have a publicly accessible IP.

When a UDP packet arrives to the "server", it will store the remote address which it will use when sending back encapsulated responses. This is how the server can _learn_ about the NAT address of the _laptop_.

There are solutions to where both machines are behind a NAT such as using [STUN](https://en.wikipedia.org/wiki/STUN); however it adds quite a bit of complexity.

The inner protocol is unencrypted, which can be a problem if it's also in cleartext like _HTTP_. More robust solutions like _wireguard_, encrypt the encapsulated packet. The equivalent would be to extend **lametun** such that the UDP payloads are encrypted. That part is straightforward, key management is difficult :)

Consider these remaining gaps _homework assignment_ or now you can use the mature product offerings with a better conceptual understanding and appreciation.

[^1]: <https://en.wikipedia.org/wiki/Virtual_private_network>
[^2]: By Michel Bakni - Derived from files [1], [2] and [3].Dulaney, Emmett (2009) CompTIA Security+ Deluxe Study Guide, Wiley Publishing, Inc., p. 124 ISBN: 9780470372968., CC BY-SA 4.0
[^3]: <https://www.kernel.org/doc/Documentation/networking/tuntap.txt>
[^4]: <https://en.wikipedia.org/wiki/TUN/TAP>
[^5]: Foo over UDP <https://lwn.net/Articles/614348/>
[^6]: Why TCP Over TCP Is A Bad Idea <http://sites.inka.de/bigred/devel/tcp-tcp.html>