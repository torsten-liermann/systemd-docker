# Introduction
This repository provides a wrapper that makes Docker containers truely compatible with `systemd`. One of `systemd`'s features is that it provides a process 
watch and failure restart policy handling but if the systemd unit for a Docker container is configured to execute `docker run` (unit file configuration 
`ExecStart=docker run ...`), **`systemd`** is actually going to **supervise** the Docker **client process instead of the container process**. This is how 
`docker run` works and it can lead to bunch of odd situations:
- the client can detach or crash while the container is fine and should hence not be restarted
- worse, the container crashed and should be restarted, but the client stalled and the problem goes unnoticed
- when a container is stopped using `docker stop`, attached client processes exit with an error code instead of 0 (success). This triggers systemd's 
  failure handling whereas in fact the container/service was properly shut down 

The **key thing that this wrapper does is** that it moves the container process from the cgroups setup by Docker to the service unit's cgroup **to make 
systemd supervise the docker container process**. It's written in Golang and allows to leverage all the cgroup functionality of systemd and systemd-notify.

# Repository history and credits
- the code was written by [@ibuildthecloud](https://github.com/ibuildthecloud) and his co-contributors in this [repository](https://github.com/ibuildthecloud/systemd-docker). 
The motivation is explained in this [Docker Issue #6791](https://github.com/docker/docker/issues/6791) and this [mailing list thread](https://groups.google.com/d/topic/coreos-dev/wf7G6rA7Bf4/discussion).
- [@agend07](https://github.com/agend07) and co-contributors fixed outdated dependancies and clean-up a bit
- I removed all outdated and broken elements and created a new compilation docker container which can be found [here]()

# Installation
Download/compile with `go get github.com/dontsetse/systemd-docker`. The executable can then be found in the Go binary directory, usually `/go/bin`. 
It can also be build using a stand-alone docker image, see [here]()

# Usage
Both
- `systemctl` to manage systemd services, and
- the `docker` CLI
can be used and everything should stay in sync.

Basically, the command is `systemd-docker run` instead of `docker run`.  Here's an unit file example to run a nginx container

```ini
[Unit]
Description=Nginx
After=docker.service
Requires=docker.service

[Service]
ExecStart=/opt/bin/systemd-docker run --rm --name %n nginx
Restart=always
RestartSec=10s
Type=notify
NotifyAccess=all
TimeoutStartSec=120
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
```
Note: `Type=notify` and `NotifyAccess=all` are important

## Named Containers
Container names are compulsory to make sure that the systemd services always relate to/act upon the same container(s). 
While it may seem as if that could be omitted as long as the `--rm` flag is passed to `docker run` or rather 
`systemd-docker run`, that's misleading: the deletion process triggered by this flag is actually part of the Docker client 
logic and if the client detaches for whatever reason from the running container, the information is lost (even if another 
client is re-attached later) and the container will not be deleted. 
`systemd-docker` looks for the named container on start.  If it exists and is stopped, it will be deleted.
It's even better to put `--name %n --rm` in the unit file's `ExecStart`; the container name will match the name of the service unit.

# Options
## Logging
By default the container's stdout/stderr will be piped to the journal.  If you do not want to use the journal, add `--logs=false` to the beginning of the command.  For example:

`ExecStart=/opt/bin/systemd-docker --logs=false run --rm --name %n nginx`

## Environment Variables
Using `Environment=` and `EnvironmentFile=`, systemd can set up environment variables for you, but then unfortunately you have to do `run -e ABC=${ABC} -e XYZ=${XYZ}` in your unit file.  You can have the systemd environment variables automatically transfered to your docker container by adding `--env`.  This will essentially read all the current environment variables and add the appropriate `-e ...` flags to your docker run command.  For example:

```
EnvironmentFile=/etc/environment
ExecStart=/opt/bin/systemd-docker --env run --rm --name %n nginx
```

The contents of `/etc/environment` will be added to your docker run command

## Cgroups
The main magic of how this works is that the container processes are moved from the Docker cgroups to the system unit cgroups.  By default all application cgroups will be moved.  This means by default you can't use `--cpuset` or `-m` in Docker.  If you don't want to use the systemd cgroups, but instead use the Docker cgroups, you can control which cgroups are transfered using the `--cgroups` option.  **Minimally you must set `name=systemd`; otherwise, systemd will lose track of the container**.  For example

`ExecStart=/opt/bin/systemd-docker --cgroups name=systemd --cgroups=cpu run --rm --name %n nginx`

The above command will use the `name=systemd` and `cpu` cgroups of systemd but then use Docker's cgroups for all the others, like the freezer cgroup.

## Pid File
If for whatever reason you want to create a pid file for the container PID, you can.  Just add `--pid-file` as below

`ExecStart=/opt/bin/systemd-docker --pid-file=/var/run/%n.pid --env run --rm --name %n nginx`

#5 systemd-notify support

By default `systemd-docker` will send READY=1 to the systemd notification socket.  You can instead delegate the READY=1 call to the container itself.  This is done by adding `--notify`.  For example

`ExecStart=/opt/bin/systemd-docker --notify run --rm --name %n nginx`

What this will do is set up a bind mount for the notification socket and then set the NOTIFY_SOCKET environment variable.  If you are going to use this feature of systemd, take some time to understand the quirks of it.  More info in this [mailing list thread](http://comments.gmane.org/gmane.comp.sysutils.systemd.devel/18649).  In short, systemd-notify is not reliable because often the child dies before systemd has time to determine which cgroup it is a member of

##Detaching the client
The `-d` argument to docker has no effect under `systemd-docker`. To cause the `systemd-docker` client to detach after the container is running, use `--logs=false --rm=false`. If either `--logs` or `--rm` is true, the `systemd-docker` client will stay alive until it is killed or the container exits.

# Known issues
## Inconsistent cgroup
CentOS 7 is inconsistent in the way it handles some cgroups. 
It has `3:cpuacct,cpu:/user.slice` in `/proc/[pid]/cgroups` which is inconsistent with the cgroup path `/sys/fs/cgroup/cpu,cpuacct/` that systemd-docker is trying to move pids to.

This will cause `systemd-docker` to fail unless run with`systemd-docker --cgroups name=systemd run`

See https://github.com/ibuildthecloud/systemd-docker/issues/15 for details.

# License
[Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0)
