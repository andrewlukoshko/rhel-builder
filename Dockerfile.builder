FROM centos:8

RUN rm -f /etc/localtime \
 && ln -s /usr/share/zoneinfo/UTC /etc/localtime \
 && yum install -y epel-release \
 && yum install -y mock git curl sudo yum-utils rpmdevtools \
 && yum install -y http://abf-downloads.rosalinux.ru/rosa-server80/repository/x86_64/build/release/builder-c-1.4.1-1.x86_64.rpm \
 && sed -i 's!openmandriva.org!rosalinux.ru!g' /etc/builder-c/filestore_upload.sh \
 && sed -i -e "s/Defaults    requiretty.*/ #Defaults    requiretty/g" /etc/sudoers \
 && echo "%mock ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers \
 && adduser omv \
 && usermod -a -G mock omv \
 && rm -rf /var/cache/* \
 && rm -rf /usr/share/man/ /usr/share/cracklib /usr/share/doc

COPY builder.conf /etc/builder-c/
ENTRYPOINT ["/usr/bin/builder"]
