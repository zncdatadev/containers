# Kerberos 5

Install krb5 service using rockylinux9 and automatically initialize krb5kdc and kadmin services when running the container for the first time, then run the services using systemd.

Unlike other containers, containers running as systemd services may not capture stop signals such as `CTRL+C` correctly and may require manual stopping in certain cases.

## Usage

Since the container manages multiple services using systemd, when running a systemd-based container, you may need to pass additional parameters to your runtime or use a specific runtime.

### podman

In a podman environment, you can simply run it using `podman run` without any additional settings.

### rootless docker

When using [rootless docker](https://docs.docker.com/engine/security/rootless/) with cgroups v2 support, you need to add the following parameters:

```bash
--cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw
```

> Check if cgroup v2 is supported: `docker info --format '{{ json .CgroupVersion }}'`

### rootful docker

In a docker environment running with root privileges, you need to enable [user namespace remapping](https://docs.docker.com/engine/security/userns-remap/) to start systemd services with read-write access.

Add the following to `/etc/docker/daemon.json`:

```json
{ "userns-remap": "default" }
```

Then restart the docker service.

**Note:** After modification, resources previously run as root will be lost and need to be recreated.

### cgroups v1 docker

In a docker environment that does not support cgroups v2, you need to add the following parameter:

```bash
-v /sys/fs/cgroup/unified:/sys/fs/cgroup:rw
```

## Inspiration

- [freeipa-container](https://github.com/freeipa/freeipa-container)
