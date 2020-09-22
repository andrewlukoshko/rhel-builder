#!/bin/bash
set -x

cleanup() {
	printf '%s\n' '--> Cleaning up...'
	sudo rm -fv /etc/rpm/platform
#	sudo rm -fv /etc/mock/default.cfg
	sudo rm -rf /var/lib/mock/*
	sudo rm -rf /var/cache/mock/*-${platform_arch}/yum_cache
	sudo rm -rf /var/cache/yum/*

	sudo rm -rf "${HOME}"/"${PACKAGE:?}"
}

# (tpg) Clean build environment
cleanup

# (tpg) remove these files
[ -e ~/build_fail_reason.log ] && rm -rf ~/build_fail_reason.log
[ -e "${HOME}"/output ] && rm -rf "${HOME}"/output

MOCK_BIN="/usr/bin/mock"
config_dir=/etc/mock/
# $PACKAGE same as project name
build_package="${HOME}"/"$PACKAGE"
OUTPUT_FOLDER="${HOME}"/output

GREP_PATTERN='error: (.*)$|Segmentation Fault|cannot find (.*)$|undefined reference (.*)$|cp: (.*)$|Hunk #1 FAILED|\(due to unsatisfied(.*)$'

filestore_url="http://file-store.rosalinux.ru/api/v1/file_stores"
platform_arch="$PLATFORM_ARCH"
platform_name=${PLATFORM_NAME:-"rosa-server75"}
uname="$UNAME"
email="$EMAIL"
git_repo="$GIT_PROJECT_ADDRESS"
project_version="$PROJECT_VERSION"
extra_build_rpm_options="$EXTRA_BUILD_RPM_OPTIONS"
extra_build_src_rpm_options="$EXTRA_BUILD_SRC_RPM_OPTIONS"
extra_cfg_options="$EXTRA_CFG_OPTIONS"
extra_cfg_urpm_options="$EXTRA_CFG_URPM_OPTIONS"
save_buildroot="$SAVE_BUILDROOT"
use_extra_tests="$USE_EXTRA_TESTS"
rerun_tests="$RERUN_TESTS"
use_mock_cache="$MOCK_CACHE"
# list of packages for tests relaunch
packages="$PACKAGES"
commit_hash="$COMMIT_HASH"

if [ "$(uname -m)" = 'x86_64' ] && printf '%s\n' "${arch}" | grep -qE 'i[0-9]86'; then
	# Change the kernel personality so build scripts don't think
	# we're building for 64-bit
	MOCK_BIN="/usr/bin/i386 $MOCK_BIN"
fi

generate_config() {
	# Change output format for mock
	sed '17c/format: %(message)s' "${config_dir}"/logging.ini > ~/logging.ini
	sudo mv -f ~/logging.ini "${config_dir}"/logging.ini
# (tpg) check how old is cache file to prevent generating cache while building rpms
	if [ -f "${HOME}"/"${platform_name}"-"${platform_arch}".cache.tar.xz ]; then
		[ $(( $(date '+%s') - $(stat -c '%Y' "${HOME}/${platform_name}-${platform_arch}".cache.tar.xz))) -lt 86400 ] && rebuild_cache='False'
		printf '%s\n' "Cache is not going to be rebuilt as it is not older than 24 hours."
	elif [ "$use_mock_cache" = 'True' ]; then
		rebuild_cache='True'
		printf '%s\n' "Cache is older than 24 hours. Trying to rebuild it."
	else
		rebuild_cache='False'
	fi
	EXTRA_CFG_OPTIONS="$extra_cfg_options" \
	EXTRA_CFG_URPM_OPTIONS="$extra_cfg_urpm_options" \
	UNAME="$uname" \
	EMAIL="$email" \
	PLATFORM_NAME="$platform_name" \
	PLATFORM_ARCH="$platform_arch" \
	REBUILD_CACHE="$rebuild_cache" \
	sudo -E /bin/sh "/rhel/config-generator.sh"
}

container_data() {
	# Generate data for container

	[ "$rerun_tests" = 'true' ] && return 0

	c_data="$OUTPUT_FOLDER"/container_data.json
	echo '[' > ${c_data}
	comma=0

	for rpm in "${OUTPUT_FOLDER}"/*.rpm; do
		nevr=(`rpm -qp --queryformat "%{NAME} %{EPOCH} %{VERSION} %{RELEASE}" ${rpm}`)
		name=${nevr[0]}
		if [ "${name}" != '' ] ; then
			if [ $comma -eq 1 ]; then
				echo -n "," >> ${c_data}
			fi
			if [ $comma -eq 0 ]; then
				comma=1
			fi
			fullname="$(basename $rpm)"
			epoch=${nevr[1]}
			version=${nevr[2]}
			release=${nevr[3]}

			dep_list=""
			[[ ! "${fullname}" =~ .*src.rpm$ ]] && dep_list=$(if [[ $(repoquery -q --qf "%{NAME}\\n" --whatrequires ${name} | wc -l ) -ne 0 ]];then repoquery -q --qf "%{NAME}\\n" --whatrequires ${name} | sort -u | xargs repoquery -q --qf "%{SOURCERPM}\\n" | rev | cut -f3- -d- | rev | sort -u | xargs echo; fi)
			sha1=$(sha1sum ${rpm} | awk '{ print $1 }')

			echo "--> dep_list for '${name}':"
			echo ${dep_list}

			echo '{' >> ${c_data}
			echo "\"dependent_packages\":\"${dep_list}\","    >> ${c_data}
			echo "\"fullname\":\"${fullname}\","              >> ${c_data}
			echo "\"sha1\":\"${sha1}\","                      >> ${c_data}
			echo "\"name\":\"${name}\","                      >> ${c_data}
			echo "\"epoch\":\"${epoch}\","                    >> ${c_data}
			echo "\"version\":\"${version}\","                >> ${c_data}
			echo "\"release\":\"${release}\""                 >> ${c_data}
			echo '}' >> ${c_data}
		fi
	done
	echo ']' >> ${c_data}
}

setup_cache() {
	if [ -f "${HOME}/${platform_name}-${platform_arch}".cache.tar.xz ] && [ $(( $(date '+%s') - $(stat -c '%Y' "${HOME}/${platform_name}-${platform_arch}".cache.tar.xz))) -ge 86400 ]; then
		sudo rm -rf "${HOME}"/"${platform_name:?}"-"${platform_arch:?}".cache.tar.xz
		printf '%s\n' "Cache is older than 24 hours. Removing cache ${platform_name}-${platform_arch}.cache.tar.xz"
	elif [ -f "${HOME}"/"${platform_name}"-"${platform_arch}".cache.tar.xz ] && [ "${use_mock_cache}" = 'True' ]; then
		printf '%s\n' "Found cache ${platform_name}-${platform_arch}.cache.tar.xz"
		[ ! -d /var/cache/mock/"${platform_name}"-"${platform_arch}"/root_cache ] && sudo mkdir -p /var/cache/mock/"${platform_name}"-"${platform_arch}"/root_cache
		sudo cp -f "${HOME}"/"${platform_name}"-"${platform_arch}".cache.tar.xz /var/cache/mock/"${platform_name}"-"${platform_arch}"/root_cache/cache.tar.xz
	elif [ -f "${HOME}"/"${platform_name}"-"${platform_arch}".cache.tar.xz ] && [ "${use_mock_cache}" != 'True' ]; then
		printf '%s\n' "Cached chroot is disabled."
		[ -f /var/cache/mock/"${platform_name}"-"${platform_arch}"/root_cache/cache.tar.xz ] && sudo rm -rf /var/cache/mock/"${platform_name:?}"-"${platform_arch:?}"/root_cache
	fi
}


arm_platform_detector(){
	probe_cpu() {
		# probe cpu type
		cpu="$(uname -m)"
		case "$cpu" in
		i386|i486|i586|i686|i86pc|znver1_32|BePC|x86_64|znver1)
			cpu="i386"
			;;
		armv[4-9]*)
			cpu="arm"
			;;
		aarch64)
			cpu="aarch64"
			;;
		esac

		if [ "$platform_arch" = 'aarch64' ]; then
			if [ "$cpu" != 'aarch64' ]; then
				# hack to copy qemu binary in non-existing path
				(while [ ! -e  /var/lib/mock/"${platform_name}"-"${platform_arch}"/root/usr/bin/ ]; do sleep 1; done
				# rebuild docker builder with qemu packages
				sudo cp /usr/bin/qemu-static-aarch64 /var/lib/mock/"${platform_name}"-"${platform_arch}"/root/usr/bin/) &
				subshellpid=$!
			fi
		elif echo "$platform_arch" |grep -qE '^arm'; then
			if [ "$cpu" != 'arm' ] && [ $cpu != "aarch64" ] ; then
				# hack to copy qemu binary in non-existing path
				(while [ ! -e  /var/lib/mock/"${platform_name}"-"${platform_arch}"/root/usr/bin/ ]; do sleep 1; done
				sudo cp /usr/bin/qemu-static-arm /var/lib/mock/"${platform_name}"-"${platform_arch}"/root/usr/bin/) &
				subshellpid=$!
			fi
		fi
	}
	probe_cpu
}

test_rpm() {
        # Rerun tests
        PACKAGES=${packages}
        use_extra_tests=$use_extra_tests

        test_code=0
        test_log="$OUTPUT_FOLDER"/tests.log
        printf '%s\n' '--> Starting RPM tests.' >> $test_log

        if [ "$rerun_tests" = 'true' ]; then
                [ "$packages" = '' ] && printf '%s\n' '--> No packages for testing. Something is wrong. Exiting. !!!' >> $test_log && exit 1

                [ ! -e "$OUTPUT_FOLDER" ] && mkdir -p "$OUTPUT_FOLDER"
                [ ! -e "$build_package" ] && mkdir -p "$build_package"

                test_log="${OUTPUT_FOLDER}"/tests-"$(printf '%(%F-%R)T')".log
                printf '%s\n' "--> Re-running tests on $(date -u)" >> $test_log
                arr=($packages)
                cd "$build_package"
                for package in ${arr[@]} ; do
                        printf '%s\n' "--> Downloading '$package'..." >> $test_log
                        wget http://file-store.openmandriva.org/api/v1/file_stores/"$package" --content-disposition --no-check-certificate
                        rc=$?
                        if [ "${rc}" != '0' ]; then
                                printf '%s\n' "--> Error on extracting package with sha1 '$package'!!!" >> $test_log
                                exit "${rc}"
                        fi
                done
                cd -
                if [ -f /var/cache/mock/"${platform_name}"-"${platform_arch}"/root_cache/cache.tar.xz ] && [ "$use_mock_cache" = 'True' ]; then
                        printf '%s\n' "--> Testing with cached chroot ..." >> $test_log
                        $MOCK_BIN --init --configdir $config_dir -v --no-cleanup-after --no-clean
                else
                        # useless logic
                        $MOCK_BIN --init --configdir $config_dir -v --no-cleanup-after
                fi
                OUTPUT_FOLDER="$build_package"
        fi

        printf '%s\n' '--> Checking if rpm packages can be installed.' >> $test_log

        sudo rm -rf /var/cache/yum/*
        sudo rm -rf /var/lib/mock/"${platform_name:?}"-"${platform_arch:?}"/
        # need to perfom repoquery with connected repos
	# and it's mean that need to disable tmpfs on mock
	# due to keep_mounted option not available
	# i think it's a kind of bug
        sudo sed -i '/.*tmpfs/d' /etc/mock/default.cfg
        mock --init --no-cleanup-after --no-clean -v --configdir /etc/mock/ --install $(ls "$OUTPUT_FOLDER"/*.rpm | grep -v .src.rpm) >> "${test_log}" 2>&1
        test_code=$?
        CHROOT_PATH="$(mock --print-root-path)"

        printf '%s\n' "--> Tests finished at $(date -u)" >> "$test_log"
        printf '%s\n' "Test code output: $test_code" >> "$test_log" 2>&1
        if [ "${test_code}" = '0' ] && [ "$use_extra_tests" = 'true' ]; then
                printf '%s\n' '--> Checking if same or older version of the package already exists in repositories' >> "${test_log}"

                for i in $(ls "${OUTPUT_FOLDER}" | grep .rpm | grep -v .src.rpm); do
                        RPM_NAME=$(rpm -qp --qf "%{NAME}" "${OUTPUT_FOLDER}"/"$i")
                        RPM_EPOCH=$(rpm -qp --qf "%{EPOCH}" "${OUTPUT_FOLDER}"/"$i")

                        [ "${RPM_EPOCH}" = '(none)' ] && RPM_EPOCH='0'
                        RPM_VERREL=$(rpm -qp --qf "%{VERSION}-%{RELEASE}" "${OUTPUT_FOLDER}"/"$i")
                        RPM_EVR="${RPM_EPOCH}:${RPM_VERREL}"
                        REPO_EVR=$(sudo repoquery -c ${CHROOT_PATH}/etc/yum.conf --installroot=${CHROOT_PATH} -q --qf "%{EPOCH}:%{VERSION}-%{RELEASE}" "${RPM_NAME}")
                        if [ ! -z "${REPO_EVR}" ]; then
                                rpmdev-vercmp "${RPM_EVR}" "${REPO_EVR}"
                                test_code="$?"
                                if [ "${test_code}" -eq 11 ]; then
                                        # Proposed rpm is newer than what's in the repo
                                        test_code='0'
                                        printf '%s\n' "Package $i is newer than what's in the repo. Extra tests passed: $test_code" >> "${test_log}"
                                else
                                        # Proposed rpm is either the same, older, or another problem
                                        test_code='5'
                                        printf '%s\n' "Package $i is either the same, older, or another problem. Extra tests failed: $test_code" >> "${test_log}"
                                        printf 'Compared %s %s (new) to %s (repo) for %s\n' "$RPM_NAME" "$RPM_EVR" "$REPO_EVR" "$i" >> "${test_log}"
                                        rpmdev-vercmp "${RPM_EVR}" "${REPO_EVR}" >> "${test_log}"
                                        # package exist in repo, let's fail tests
					container_data
					exit "${test_code}"
                                fi
                        else
                                # It does not exist in the repo, so it's okay to go in
                                test_code='0'
                                printf '%s\n' "Extra tests finished without errors: $test_code" >> "${test_log}"
                        fi
                done
        fi
        # Check exit code after testing
        if [ "${test_code}" != '0' ]; then
                printf '%s\n' '--> Test failed, see: tests.log'
                test_code=5
                [ "$rerun_tests" = '' ] && container_data
                [ "$rerun_tests" = 'true' ] && cleanup
                exit "${test_code}"
        else
                return "${test_code}"
        fi
}

build_rpm() {
	arm_platform_detector
	sudo touch -d "23 hours ago" $config_dir/default.cfg

	# We will rerun the build in case when repository is modified in the middle,
	# but for safety let's limit number of retest attempts
	# (since in case when repository metadata is really broken we can loop here forever)
	MAX_RETRIES=1
	WAIT_TIME=30
	RETRY_GREP_STR="Unable to find a match\|Error downloading packages\|All mirrors were already tried\|Cannot download\|Some packages could not be found"

	if [ "$rerun_tests" = 'true' ]; then
		test_rpm
		return 0
	fi

	printf '%s\n' '--> Build src.rpm'
	spec_name=`ls -1 $build_package | grep '\.spec$'`
	sed -i '/^[Uu][Rr][Ll]: /d' $build_package/${spec_name}
	sed -i '/^%changelog/q' $build_package/${spec_name}
	echo "* $(LANG=C date '+%a %b %d %Y') ROSA Build platform (ABF) <support@rosalinux.ru>" >> $build_package/$spec_name
	echo '- Собрано специалистами ООО "НТЦ ИТ РОСА" с использованием сборочной среды ABF' >> $build_package/$spec_name
	try_rebuild=true
	retry=0
	while $try_rebuild; do
		rm -rf "${OUTPUT_FOLDER:?}"
		sudo rm -rf /var/cache/yum/*
		sudo rm -rf /var/lib/mock/"${platform_name:?}"-"${platform_arch:?}"/root/var/cache/yum/*
		if [ -f /var/cache/mock/"${platform_name}"-"${platform_arch}"/root_cache/cache.tar.xz ] && [ "$use_mock_cache" = 'True' ]; then
			printf '%s\n' "--> Building with cached chroot ..."
			$MOCK_BIN -v --update --configdir=$config_dir --buildsrpm --spec=$build_package/${spec_name} --sources=$build_package --no-cleanup-after --no-clean $extra_build_src_rpm_options --resultdir="${OUTPUT_FOLDER}"
		else
			$MOCK_BIN -v --update --configdir=$config_dir --buildsrpm --spec=$build_package/${spec_name} --sources=$build_package --no-cleanup-after $extra_build_src_rpm_options --resultdir="${OUTPUT_FOLDER}"
		fi

		rc=${PIPESTATUS[0]}
		try_rebuild=false
		if [ "${rc}" != 0 ] && [ "${retry}" -lt "${MAX_RETRIES}" ]; then
			if grep -q "$RETRY_GREP_STR" "${OUTPUT_FOLDER}"/root.log; then
				try_rebuild=true
				(( retry=$retry+1 ))
				sudo rm -rf /var/lib/mock/"${platform_name}"-"${platform_arch}"/root/var/cache/yum/*
				printf '%s\n' "--> Repository was changed in the middle, will rerun the build. Next try (${retry} from ${MAX_RETRIES})..."
				printf '%s\n' "--> Delay ${WAIT_TIME} sec..."
				sleep "${WAIT_TIME}"
			fi
		fi
	done

	# Check exit code after build
	if [ "${rc}" != 0 ]; then
		printf '%s\n' '--> Build failed: mock encountered a problem.'
		# 99% of all build failures at src.rpm creation is broken deps
		# m1 show only first match -oP show only matching
		grep -m1 -oP "\(due to unsatisfied(.*)$" $OUTPUT_FOLDER/root.log >> ~/build_fail_reason.log
		[ -n "$subshellpid" ] && kill "$subshellpid"
		cleanup
		exit 1
	fi

	# Check if src.rpm file does exist
	for file in "${OUTPUT_FOLDER}"/*.src.rpm ; do
		if [ ! -e "$file" ]; then
			printf '%s\n' '--> Build failed: mock encountered a problem. src.rpm files is missing'
			# 99% of all build failures at src.rpm creation is broken deps
			# m1 show only first match -oP show only matching
			grep -m1 -oP "\(due to unsatisfied(.*)$" "${OUTPUT_FOLDER}"/root.log >> ~/build_fail_reason.log
			[ -n "$subshellpid" ] && kill "$subshellpid"
			cleanup
			exit 1
		fi
	done

	if [ -f /var/cache/mock/"${platform_name}"-"${platform_arch}"/root_cache/cache.tar.xz ] && [ "$use_mock_cache" = 'True' ]; then
		printf '%s\n' '--> Saving cached chroot for next builds.'
		cp -f /var/cache/mock/"${platform_name}"-"${platform_arch}"/root_cache/cache.tar.xz "${HOME}"/"${platform_name}"-"${platform_arch}".cache.tar.xz
	fi

	printf '%s\n' '--> src.rpm build has been done successfully.'
	printf '%s\n' '--> validate src.rpm for exclusive_arch spec'
	# validate src.rpm for exclusive_arch
	#python /rhel/check_arch.py "${OUTPUT_FOLDER}"/*.src.rpm ${platform_arch}
	#rc=$?; if [[ $rc != 0 ]]; then exit 6; fi
	printf '%s\n' '--> Building rpm.'
	try_rebuild=true
	retry=0
	while $try_rebuild; do
		sudo rm -rf /var/cache/yum/*
		sudo rm -rf /var/lib/mock/"${platform_name:?}"-"${platform_arch:?}"/root/var/cache/yum/*
		$MOCK_BIN -v --update --configdir=$config_dir --rebuild "${OUTPUT_FOLDER}"/*.src.rpm --no-cleanup-after --no-clean $extra_build_rpm_options --resultdir="${OUTPUT_FOLDER}" --nocheck
		rc=${PIPESTATUS[0]}
		try_rebuild=false
		if [ "${rc}" != 0 ] && [ "${retry}" -lt "${MAX_RETRIES}" ]; then
			if grep -q "$RETRY_GREP_STR" "${OUTPUT_FOLDER}"/root.log; then
				try_rebuild=true
				(( retry=$retry+1 ))
				sudo rm -rf /var/lib/mock/"${platform_name:?}"-"${platform_arch:?}"/root/var/cache/yum/*
				printf '%s\n' "--> Repository was changed in the middle, will rerun the build. Next try (${retry} from ${MAX_RETRIES})..."
				printf '%s\n' "--> Delay ${WAIT_TIME} sec..."
				sleep "${WAIT_TIME}"
			fi
		fi
	done

	# Check exit code after build
	if [ "${rc}" != '0' ]; then
		printf '%s\n' '--> Build failed: mock encountered a problem.'
		# clean all the rpm files because build was not completed
		grep -m1 -i -oP "$GREP_PATTERN" "${OUTPUT_FOLDER}"/root.log >> ~/build_fail_reason.log
		rm -rf "${OUTPUT_FOLDER}"/*.rpm
		[ -n "$subshellpid" ] && kill "$subshellpid"
		# (tpg) Save build chroot
		if [ "${save_buildroot}" = 'true' ]; then
		    printf '%s\n' '--> Saving buildroot...'
		    sudo tar --exclude=root/dev -zcvf "${OUTPUT_FOLDER}"/rpm-buildroot.tar.gz /var/lib/mock/"${platform_name}"-"${platform_arch}"/root/
		fi
		cleanup
		exit 1
	fi
	printf '%s\n' '--> Done.'

	# Extract rpmlint logs into separate file
	printf '%s\n' "--> Grepping rpmlint logs from $OUTPUT_FOLDER/build.log to $OUTPUT_FOLDER/rpmlint.log"
	sed -n "/Executing \"\/usr\/bin\/rpmlint/,/packages and.*specfiles checked/p" $OUTPUT_FOLDER/build.log > $OUTPUT_FOLDER/rpmlint.log
	# (tpg) Save build chroot
	if [ "${rc}" = '0' ] && [ "${save_buildroot}" = 'true' ]; then
		printf '%s\n' '--> Saving buildroot...'
		sudo tar --exclude=root/dev -zcvf "${OUTPUT_FOLDER}"/rpm-buildroot.tar.gz /var/lib/mock/"${platform_name}"-"${platform_arch}"/root/
	fi

	# Test RPM files
	if [ "$use_extra_tests" = 'true' ]; then
		test_rpm
	fi
	# End tests

	# check if RPM files are not vanished
	if [ -z "$(ls -A "${OUTPUT_FOLDER}"/*.rpm | grep -v .src.rpm)" ]; then
		printf '%s\n' "RPM files are missing. Something went terribly wrong. Exiting!"
		exit 1
	fi
}

find_spec() {
	[ "$rerun_tests" = 'true' ] && return 0

	# Check count of *.spec files (should be one)
	x=$(ls -1 | grep -c '\.spec$' | sed 's/^ *//' | sed 's/ *$//')
	if [ "$x" -eq "0" ]; then
		printf '%s\n' '--> There are no spec files in repository.'
		exit 1
	else
		if [ "$x" -ne "1" ] ; then
			printf '%s\n' '--> There are more than one spec file in repository.'
			exit 1
		fi
	fi
}

clone_repo() {
	[ "$rerun_tests" = 'true' ] && return 0

	MAX_RETRIES=5
	WAIT_TIME=60
	try_reclone=true
	retry=0
	while $try_reclone; do
		rm -rf "${HOME}"/"${PACKAGE:?}"
		# checkout specific branch/tag if defined
		if [ ! -z "$project_version" ]; then
			# (tpg) clone only history of 100 commits to reduce bandwith
			git clone -b "$project_version" "$git_repo" "${HOME}"/"${PACKAGE}"
			cd "${HOME}"/"${PACKAGE}"
			git rev-parse HEAD > "${HOME}"/commit_hash
			cd -
		else
			git clone "$git_repo" "${HOME}"/"${PACKAGE}"
			pushd ${HOME}/${PACKAGE}
				echo "${commit_hash}" > "${HOME}"/commit_hash
				git checkout $commit_hash
			popd
		fi
		rc=$?
		try_reclone=false
		if [ "${rc}" != 0 ] && [ "${retry}" -lt "${MAX_RETRIES}" ]; then
			try_reclone=true
			(( retry=$retry+1 ))
			printf '%s\n' "--> Something wrong with git repository, next try (${retry} from ${MAX_RETRIES})..."
			printf '%s\n' "--> Delay ${WAIT_TIME} sec..."
			sleep "${WAIT_TIME}"
		fi
	done

	cd "${HOME}"/"${PACKAGE}"
	# count number of specs (should be 1)
        find_spec
	# check for excludearch or exclusivearch
	# download sources from .abf.yml
        /bin/sh /rhel/download_sources.sh
	cd -
	# build package
}

generate_config
clone_repo
setup_cache
build_rpm
container_data
# wipe package
sudo rm -rf "${HOME}"/"${PACKAGE:?}"
