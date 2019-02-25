FROM rosalab/rosa2016.1

RUN urpmi --auto --auto-update --no-verify-rpm \
 && rm -f /etc/localtime \
 && ln -s /usr/share/zoneinfo/UTC /etc/localtime \
 && urpmi.addmedia builder http://abf-downloads.rosalinux.ru/import_personal/container/2963165/x86_64/main/release/ \
 && urpmi --no-suggests --no-verify-rpm --auto mock-urpm git curl sudo builder-c xz \
 && sed -i 's!openmandriva.org!rosalinux.ru!g' /etc/builder-c/filestore_upload.sh \
 && sed -i 's!file-store!abf-n-file-store!g' /etc/builder-c/filestore_upload.sh \
 && sed -i -e "s/Defaults    requiretty.*/ #Defaults    requiretty/g" /etc/sudoers \
 && groupadd mock \
 && echo "%mock ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers \
 && adduser omv \
 && usermod -a -G mock omv \
 && chown -R omv:mock /etc/mock-urpm \
 && rm -rf /var/cache/urpmi/rpms/* \
 && rm -rf /usr/share/man/ /usr/share/cracklib /usr/share/doc

COPY builder.conf /etc/builder-c/
ENTRYPOINT ["/usr/bin/builder"]
