---
layout: post
title: Containers from first principles
date: 2020-05-31 12:38 -0700
excerpt_separator: <!--more-->
---

You've likely heard everyone at the office or online proclaim that "K8s has eaten everyone's lunch!" or that "everything should be in a docker container!".

While there are advantages to the above methodologies; it's very easy to have cargo-culted their adoption; especially for Kubernetes (K8s). I find the biggest problem however that there is a fundamental lacking of what is a **container*. 

There s a 1000 other posts online explaining containers and I'm adding my own to the pool. Perhaps this 1001th explanation will do so in such a way that it groks.

<!--more-->

> Any commands written were done in a Linux environment; if you try to follow along in OSX; it may be more challenging since Docker is running within a hypervisor or virtual machine.

## What's a Docker Image ?
Let's start by first grabbing one of the simplest Docker images around, [Alpine Linux](https://hub.docker.com/_/alpine).

> Alpine Linux is a Linux distribution based on musl and BusyBox, designed for security, simplicity, and resource efficiency. 

Let's grab the image & save it
```bash
# download the image locally
docker pull alpine:3.12.0
3.12.0: Pulling from library/alpine
Digest: sha256:185518070891758909c9f839cf4ca393ee977ac378609f700f60a771a2dfe321
Status: Downloaded newer image for alpine:3.12.0

# save the image
docker save alpine:3.12.0 > alpine-3.12.0.tar
```

If we inspect the image; we can see a few interesting files
```bash
tar --list --file=alpine-3.12.0.tar
a24bb4013296f61e89ba57005a7b3e52274d8edd3ae2077d04395f806b63d83e.json
fa27ccac46e9a5b7ff1d188e99763db1a5fb45adb34a917c1c482dfde99ad432/
fa27ccac46e9a5b7ff1d188e99763db1a5fb45adb34a917c1c482dfde99ad432/VERSION
fa27ccac46e9a5b7ff1d188e99763db1a5fb45adb34a917c1c482dfde99ad432/json
fa27ccac46e9a5b7ff1d188e99763db1a5fb45adb34a917c1c482dfde99ad432/layer.tar
manifest.json
repositories
```

*manifest.json*
    : Describes Container properties

*...faec1b8045e42.json*
    : The SHA256 of the image.

*...4395f806b63d83e/*
    : One of the "layers" that comprise the image

In fact, when we see what's inside that *layer.tar*; it's a full Linux filesystem layout.

```bash
tar -xOf alpine-3.12.0.tar fa27ccac46e9a5b7ff1d188e99763db1a5fb45adb34a917c1c482dfde99ad432/layer.tar | tar -tf - | shuf | head
var/lib/apk/
usr/bin/getent
bin/lzop
usr/bin/openvt
dev/
bin/tar
sbin/rmmod
usr/lib/libtls-standalone.so.1.0.0
usr/bin/[[
sbin/ifconfig
```

Feel free to dig into the concept of an [overlay filesystem](https://www.kernel.org/doc/Documentation/filesystems/overlayfs.txt); however at a minimum these layers represent individual steps made during the *Dockerfile*.

> If an image that more than *1* image; they contents are superimposed to create the final filesystem view.

## What's a container?

Many people might think the word "container" has a specific meaning within the Linux kernel; however the kernel has no notion of a "container". The word has been synonymous with a variety of Linux tooling which when applied give the resemblance of what we expect a container to be.

To be put it simply; a container should resemble somewhat as a *separate* machine (or virtual machine) although many of them run with a single kernel.

Each container should have _at least_ the following isolated:
1. network stack
2. filesystem
3. processes

Linux achieves these isolations via, **Namespaces**. Let's rebuild together the isolation using simple bash commands.

## Virtual Machine Setup
The following commands were executed on a Debian machine running in GCP
```bash
gcloud compute instances create containers-demystified --image-family debian-10 --image-project debian-cloud --zone us-west1-a
gcloud compute ssh containers-demystified

# kernel version
uname -r
4.19.0-9-cloud-amd64

# install docker
sudo apt-get install apt-transport-https ca-certificates curl gnupg2 software-properties-common
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian buster stable"
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io
sudo groupadd docker
sudo usermod -aG docker $USER
```

## Containers from scratch

First lets grab the Alpine Linux filesystem and place it in a _container/_ directory.
```bash
mkdir container
tar -xOf alpine-3.12.0.tar fa27ccac46e9a5b7ff1d188e99763db1a5fb45adb34a917c1c482dfde99ad432/layer.tar | tar -C container/ -xf -

ls container/ | head
bin
dev
etc
home
root
tmp
usr
var

```
Great! Now let's try creating a new mount namespace using **unshare**

>  unshare - run program with some namespaces unshared from parent

```bash
sudo unshare --fork --mount bash

# we need to bind mount itself --
# this is just a pre-requisite for pivot_root which is the next step
mount --bind container/ container/
# create a location to store the pivot of the filesystem
pivot_root container/ container/_old
# check that we have pivoted
ls -l /_old/ | head
total 128
drwxr-xr-x    1 root     root          4096 May 28 01:21 bin
drwxr-xr-x    2 root     root          4096 Feb  1 17:09 boot
drwxr-xr-x   10 root     root          1400 Jun  1 00:31 dev
drwxr-xr-x    1 root     root          4096 Jun  1 00:31 etc
drwxr-xr-x    1 root     root          4096 May 28 00:11 google
drwxr-xr-x    4 root     root          4096 Jun  1 00:31 home

# great now un mount it; for security reasons so the process can't escape the jail
cd /
umount -l /_old
```
> pivot_root moves the root file system of the calling process to the directory of the second argument and makes first argument the new root file system of the calling process.

Great! It looks like we are in a separate filesystem environment.
Let's re-add the _proc_ filesystem
```
mount -t proc /proc /proc

ps aux  | head
PID   USER     TIME  COMMAND
    1 root      0:00 /bin/bash /google/scripts/onrun.sh sleep infinity
    8 root      0:00 /usr/sbin/rsyslogd
  573 root      0:00 /usr/sbin/sshd -p 22 -o AuthorizedKeysFile=/etc/ssh/keys/authorized_keys
  647 root      0:20 /usr/bin/dockerd -p /var/run/docker.pid --mtu=1460 --registry-mirror=https://us-mirror.gcr.io
  675 root      0:16 containerd --config /var/run/docker/containerd/containerd.toml --log-level info
```

Hmmmm.. that's not isolated from the outside. Let's fix it!

```
# add a `--pid` now
sudo unshare --fork --pid --mount bash
# do all the same commands as above

mount --bind container/ container/
pivot_root container/ container/_old
umount -l /_old

mount -t proc /proc /proc

ps aux
PID   USER     TIME  COMMAND
    1 root      0:00 bash
  104 root      0:00 ps aux
```

Much better! 
Let's checkout the network configuration
```bash
ip link list

1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
2: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue
    link/ether 02:42:c2:8a:54:22 brd ff:ff:ff:ff:ff:ff
12: eth0@if13: <BROADCAST,MULTICAST,UP,LOWER_UP,M-DOWN> mtu 1500 qdisc noqueue
    link/ether 02:42:ac:11:00:04 brd ff:ff:ff:ff:ff:ff
```

Looks like we still have access to the physical ethernet device; that's not isolated... let's fix that!

```bash
# we run the following command in the background
sudo unshare --fork --pid --mount --uts --net bash

# in a separate window (host namespace)
# grab the PID of unshare
CPID=$(pidof unshare)
# This will use the PID of the process to pick the correct netns
sudo ip link add h$CPID type veth peer name c$CPID netns $CPID
# turn on the device & attach it to the docker0 bridge
sudo ip link set h$CPID up master docker0


# in the original window (new namespace)
# filesystem
mount --bind container/ container/
pivot_root container/ container/_old
umount -l /_old
mount -t proc /proc /proc

# network
# let's change hostname
hostname container
# bring up the loopback address
ip link set lo up
# bring the veth device up
ip link set c$CPID up
# lets give the veth a IP address
ip addr add 172.17.42.3/16 dev c$CPID
# set the veth as the default gateway
ip route add default via 172.17.0.1

# This should work!
# note: DNS don't work due to /etc/resolv.conf being missing
ping 8.8.8.8
```

The above kind of _cheats_ by using the Docker bridge setup. This was done because setting up a bridge on a cloud instance is non-trivial; moving the physical ethernet device temporarily makes the instance unroutable.
Docker uses a myriad of _iptables_ rules to setup a NAT.

## What next?

The above is _pretty close_; to what something like Docker does.
The big missing piece is starting the "container" on an _overlay_ filesystem such that changes within the new _pivot_root_ don't affect the base image.

## Useful links
1. [http://ifeanyi.co/posts/linux-namespaces-part-3/](http://ifeanyi.co/posts/linux-namespaces-part-3/)
2. [https://blog.nicolasmesa.co/posts/2018/08/container-creation-using-namespaces-and-bash/](https://blog.nicolasmesa.co/posts/2018/08/container-creation-using-namespaces-and-bash/)
3. [https://wvi.cz/diyC/](https://wvi.cz/diyC/)
4. [https://linux-blog.anracom.com/2017/11/14/fun-with-veth-devices-linux-bridges-and-vlans-in-unnamed-linux-network-namespaces-iii/](https://linux-blog.anracom.com/2017/11/14/fun-with-veth-devices-linux-bridges-and-vlans-in-unnamed-linux-network-namespaces-iii/)