FROM docker.io/rockylinux/rockylinux:9

RUN groupadd -g 288 kdcproxy ; useradd -u 288 -g 288 -c 'IPA KDC Proxy User' -r -d / -s '/sbin/nologin' kdcproxy

RUN ln -s /bin/false /usr/sbin/systemd-machine-id-setup
RUN dnf -y install --setopt=install_weak_deps=False \
    patch \
    vim \
    krb5-server \
    krb5-server-ldap \
    krb5-workstation \
    krb5-libs \
    procps \
    net-tools && \
    dnf clean all

RUN systemctl mask rpc-gssd.service

ENV container=oci

RUN echo "DefaultLimitNOFILE=4096" >> /etc/systemd/system.conf

STOPSIGNAL RTMIN+3

RUN find /etc/systemd/system /usr/lib/systemd/system/{basic,multi-user,sysinit}.target.wants -type l \! -lname /dev/null | xargs rm -v \
    && systemctl mask systemd-logind.service && mv /usr/lib/systemd/system/systemd-logind.service /usr/lib/systemd/system/systemd-logind.service-disable-dbus

COPY minimal-fedora-37.patch /root/
RUN patch --verbose -p0 --fuzz=0 < /root/minimal-fedora-37.patch \
    && ln -s /usr/lib/systemd/system/dbus-broker.service /usr/lib/systemd/system/dbus.service

COPY container-krb5.target /usr/lib/systemd/system/

RUN systemctl set-default container-krb5.target \
    && rmdir -v /etc/systemd/system/multi-user.target.wants \
    && mkdir /etc/systemd/system/container-krb5.target.wants \
	&& ln -s /etc/systemd/system/container-krb5.target.wants /etc/systemd/system/multi-user.target.wants \
    && mkdir /var/log/journal \
    && systemd-tmpfiles --remove --create

COPY krb5-setup /usr/sbin/krb5-setup

RUN echo 2.0 > /etc/volume-version
VOLUME [ "/tmp", "/run", "/data" ]

COPY krb5-setup /usr/local/sbin/init
ENTRYPOINT [ "/usr/local/sbin/init" ]

EXPOSE 88 464 88/udp 464/udp
