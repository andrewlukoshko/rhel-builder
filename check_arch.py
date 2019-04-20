#!/usr/bin/python2

#
# Check if a package can be built for the given architecture
# (i.e., arch is not forbidden by ExcludeArch or included
#  in ExclusiveArch set if the latter is defined)
#

import sys
import glob
import os.path
import rpm

if len(sys.argv) < 3:
    sys.exit('Usage: %s srpm arch' % sys.argv[0])

srpm = sys.argv[1]
platform_arch = sys.argv[2]

ts = rpm.TransactionSet()
ts.setVSFlags(~(rpm.RPMVSF_NEEDPAYLOAD))

fdno = os.open(srpm, os.O_RDONLY)
hdr = ts.hdrFromFdno(fdno)

if hdr['excludearch']:
    for a in hdr['excludearch']:
        if a == platform_arch:
            print("Architecture is excluded per package spec file (ExcludeArch tag)")
            sys.exit(1)

exit_code = 0

if hdr['exclusivearch']:
    exit_code = 1
    for a in hdr['exclusivearch']:
        print(a)
        if a == platform_arch:
            exit_code = 0
            break

if exit_code == 1:
    print("The package has ExclusiveArch tag set, but the current architecture is not mentioned there")

sys.exit(exit_code)

