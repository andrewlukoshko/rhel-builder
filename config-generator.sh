#!/bin/bash
set -x
printf '%s\n' '--> ROSA Server platform config generator.'

extra_cfg_options="$EXTRA_CFG_OPTIONS"
uname="$UNAME"
email="$EMAIL"
platform_arch="$PLATFORM_ARCH"
platform_name=${PLATFORM_NAME:-"rosa-server75"}
repo_url="$REPO_URL"
repo_names="$REPO_NAMES"
rebuild_cache="$REBUILD_CACHE"
default_cfg=/etc/mock/default.cfg

gen_included_repos() {

    names_arr=($repo_names)
    urls_arr=($repo_url)

    for (( i=0; i<${#names_arr[@]}; i++ ));
	do
	    printf "[${names_arr[i]}]\nname=${names_arr[i]}\nbaseurl=${urls_arr[i]}\ngpgcheck=0\nenabled=1\n\n" >> "${default_cfg}"
    done

    # close dnf repos section
    printf '%s\n' '"""' >> "${default_cfg}"
}

if [ "${platform_arch}" = 'i586' ]; then
cat <<EOF> $default_cfg
config_opts['target_arch'] = 'i686'
EOF
else
cat <<EOF> $default_cfg
config_opts['target_arch'] = '$platform_arch'
EOF
fi

if [ "${platform_name}" = 'rosa-server80' ]; then
cat <<EOF>> $default_cfg
config_opts['chroot_setup_cmd'] = 'install tar gcc-c++ redhat-rpm-config redhat-release which xz sed make bzip2 gzip gcc coreutils unzip shadow-utils diffutils cpio bash gawk rpm-build info patch util-linux findutils grep rpm-build buildsys-macros-res8'
EOF
else
cat <<EOF>> $default_cfg
config_opts['chroot_setup_cmd'] = 'install @buildsys-build'
EOF
fi

cat <<EOF>> $default_cfg
config_opts['legal_host_arches'] = ('i586', 'i686', 'x86_64')
config_opts['root'] = '$platform_name-$platform_arch'
config_opts['package_manager'] = 'yum'
config_opts['rpmbuild_networking'] = True
config_opts['useradd'] = '/usr/sbin/useradd -o -m -u %(uid)s -g %(gid)s -d %(home)s %(user)s'
config_opts['releasever'] = '7' # at some point, this should be set by ABF
config_opts['use_nspawn'] = False
config_opts['basedir'] = '/var/lib/mock/'
config_opts['use_host_resolv'] = True
config_opts['cache_topdir'] = '/var/cache/mock/'
config_opts['plugin_conf']['root_cache_enable'] = False
config_opts['plugin_conf']['root_cache_opts']['age_check'] = True
config_opts['plugin_conf']['root_cache_opts']['max_age_days'] = 15

config_opts['plugin_conf']['tmpfs_enable'] = True
config_opts['plugin_conf']['tmpfs_opts']['required_ram_mb'] = 64000
config_opts['plugin_conf']['tmpfs_opts']['max_fs_size'] = '80%'

config_opts['plugin_conf']['package_state_enable'] = True
config_opts['plugin_conf']['package_state_opts'] = {}
config_opts['plugin_conf']['package_state_opts']['available_pkgs'] = False
config_opts['plugin_conf']['package_state_opts']['installed_pkgs'] = True

config_opts['dist'] = '${platform_name}'  # only useful for --resultdir variable subst
config_opts['macros']['%packager'] = '$uname <$email>'
config_opts['macros']['%_topdir'] = '%s/build' % config_opts['chroothome']
config_opts['macros']['%cross_compiling'] = '0' # ABF should generally be considered native builds
config_opts['plugin_conf']['ccache_enable'] = False
config_opts['yum.conf'] = """
[main]
keepcache=1
debuglevel=2
reposdir=/dev/null
retries=20
obsoletes=1
gpgcheck=0
assumeyes=1
syslog_ident=mock
syslog_device=
install_weak_deps=0
metadata_expire=0
best=1

EOF

gen_included_repos
