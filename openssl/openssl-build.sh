#!/bin/bash

# This script downlaods and builds the Mac, iOS and tvOS openSSL libraries with Bitcode enabled

# Credits:
#
# Stefan Arentz
#   https://github.com/st3fan/ios-openssl
# Felix Schulze
#   https://github.com/x2on/OpenSSL-for-iPhone/blob/master/build-libssl.sh
# James Moore
#   https://gist.github.com/foozmeat/5154962
# Peter Steinberger, PSPDFKit GmbH, @steipete.
#   https://gist.github.com/felix-schwarz/c61c0f7d9ab60f53ebb0
# Jason Cox, @jasonacox
#   https://github.com/jasonacox/Build-OpenSSL-cURL

set -e

# Custom build options
CUSTOMCONFIG="enable-ssl-trace enable-tls1_3"

# Formatting
default="\033[39m"
wihte="\033[97m"
green="\033[32m"
red="\033[91m"
yellow="\033[33m"

bold="\033[0m${green}\033[1m"
subbold="\033[0m${green}"
archbold="\033[0m${yellow}\033[1m"
normal="${white}\033[0m"
dim="\033[0m${white}\033[2m"
alert="\033[0m${red}\033[1m"
alertdim="\033[0m${red}\033[2m"

# set trap to help debug build errors
trap 'echo -e "${alert}** ERROR with Build - Check /tmp/openssl*.log${alertdim}"; tail -3 /tmp/openssl*.log' INT TERM EXIT

IOS_MIN_SDK_VERSION="7.1"
IOS_SDK_VERSION=""
TVOS_MIN_SDK_VERSION="9.0"
TVOS_SDK_VERSION=""

usage ()
{
	echo
	echo -e "${bold}Usage:${normal}"
	echo
	echo -e "  ${subbold}$0${normal} [-s ${dim}<iOS SDK version>${normal}] [-t ${dim}<tvOS SDK version>${normal}] [-e] [-x] [-h]"
	echo
	echo "         -s   iOS SDK version (default $IOS_MIN_SDK_VERSION)"
	echo "         -t   tvOS SDK version (default $TVOS_MIN_SDK_VERSION)"
	echo "         -e   compile with engine support"
	echo "         -x   disable color output"
	echo "         -h   show usage"
	echo
	trap - INT TERM EXIT
	exit 127
}

engine=0

while getopts "s:t:exh\?" o; do
    case "${o}" in
        s)
            IOS_SDK_VERSION="${OPTARG}"
            ;;
        t)
	    	TVOS_SDK_VERSION="${OPTARG}"
            ;;
		e)
            engine=1
	    	;;
		x)
			bold=""
			subbold=""
			normal=""
			dim=""
			alert=""
			alertdim=""
			archbold=""
			;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

DEVELOPER=`xcode-select -print-path`

buildMac()
{
	ARCH=$1

	echo -e "${subbold}Building openssl for ${archbold}${ARCH}${dim}"

	TARGET="darwin-i386-cc"

	if [[ $ARCH == "x86_64" ]]; then
		TARGET="darwin64-x86_64-cc"
	fi

	export CC="${BUILD_TOOLS}/usr/bin/clang"

	pushd . > /dev/null
	cd openssl
	./Configure no-asm ${TARGET} -no-shared --prefix="/tmp/openssl-${ARCH}" --openssldir="/tmp/openssl-${ARCH}" $CUSTOMCONFIG &> "/tmp/openssl-${ARCH}.log"
	make -j8 >> "/tmp/openssl-${ARCH}.log" 2>&1
	make install_sw -j8 >> "/tmp/openssl-${ARCH}.log" 2>&1
	# Keep openssl binary for Mac version
	cp "/tmp/openssl-${ARCH}/bin/openssl" "/tmp/openssl"
	cp -r "/tmp/openssl-${ARCH}" "/tmp/openssl-${ARCH}-archived"
	make clean >> "/tmp/openssl-${ARCH}.log" 2>&1
	mv "/tmp/openssl-${ARCH}-archived" "/tmp/openssl-${ARCH}"
	popd > /dev/null
}

buildIOS()
{
	ARCH=$1

	pushd . > /dev/null
	cd openssl

	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="iPhoneSimulator"
	else
		PLATFORM="iPhoneOS"
		#sed -ie "s!static volatile sig_atomic_t intr_signal;!static volatile intr_signal;!" "crypto/ui/ui_openssl.c"
	fi

	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc -fembed-bitcode -arch ${ARCH}"

	echo -e "${subbold}Building openssl for ${PLATFORM} ${IOS_SDK_VERSION} ${archbold}${ARCH}${dim}"

	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		TARGET="darwin-i386-cc"
		if [[ $ARCH == "x86_64" ]]; then
			TARGET="darwin64-x86_64-cc"
		fi
		./Configure no-asm ${TARGET} -no-shared --prefix="/tmp/openssl-iOS-${ARCH}" --openssldir="/tmp/openssl-iOS-${ARCH}" $CUSTOMCONFIG &> "/tmp/openssl-iOS-${ARCH}.log"
	else
		./Configure iphoneos-cross DSO_LDFLAGS=-fembed-bitcode --prefix="/tmp/openssl-iOS-${ARCH}" -no-shared --openssldir="/tmp/openssl-iOS-${ARCH}" $CUSTOMCONFIG &> "/tmp/openssl-iOS-${ARCH}.log"
	fi
	# add -isysroot to CC=
	sed -ie "s!^CFLAGS=!CFLAGS=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${IOS_MIN_SDK_VERSION} !" "Makefile"

	make -j8 >> "/tmp/openssl-iOS-${ARCH}.log" 2>&1
	make install_sw -j8 >> "/tmp/openssl-iOS-${ARCH}.log" 2>&1
	cp -r "/tmp/openssl-iOS-${ARCH}" "/tmp/openssl-iOS-${ARCH}-archived"
	make clean >> "/tmp/openssl-iOS-${ARCH}.log" 2>&1
	mv "/tmp/openssl-iOS-${ARCH}-archived" "/tmp/openssl-iOS-${ARCH}"
	popd > /dev/null
}

buildTVOS()
{
	ARCH=$1

	pushd . > /dev/null
	cd openssl

	if [[ "${ARCH}" == "x86_64" ]]; then
		PLATFORM="AppleTVSimulator"
	else
		PLATFORM="AppleTVOS"
		sed -ie "s!static volatile sig_atomic_t intr_signal;!static volatile intr_signal;!" "crypto/ui/ui_openssl.c"
	fi

	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${TVOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc -fembed-bitcode -arch ${ARCH}"
	export LC_CTYPE=C

	echo -e "${subbold}Building openssl for ${PLATFORM} ${TVOS_SDK_VERSION} ${archbold}${ARCH}${dim}"

	# Patch apps/speed.c to not use fork() since it's not available on tvOS
	LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "./apps/speed.c"
	LANG=C sed -i -- 's/!defined(OPENSSL_NO_POSIX_IO)/defined(HAVE_FORK)/' "./apps/ocsp.c"
	LANG=C sed -i -- 's/fork()/-1/' "./apps/ocsp.c"
    LANG=C sed -i -- 's/fork()/-1/' "./test/drbgtest.c"
	LANG=C sed -i -- 's/!defined(OPENSSL_NO_ASYNC)/defined(HAVE_FORK)/' "./crypto/async/arch/async_posix.h"

	# Patch Configure to build for tvOS, not iOS
	LANG=C sed -i -- 's/D\_REENTRANT\:iOS/D\_REENTRANT\:tvOS/' "./Configure"
	chmod u+x ./Configure

	if [[ "${ARCH}" == "x86_64" ]]; then
		./Configure no-asm darwin64-x86_64-cc -no-shared --prefix="/tmp/openssl-tvOS-${ARCH}" --openssldir="/tmp/openssl-tvOS-${ARCH}" $CUSTOMCONFIG &> "/tmp/openssl-tvOS-${ARCH}.log"
	else
		export CC="${BUILD_TOOLS}/usr/bin/gcc -fembed-bitcode -arch ${ARCH}"
		./Configure iphoneos-cross DSO_LDFLAGS=-fembed-bitcode --prefix="/tmp/openssl-tvOS-${ARCH}" -no-shared --openssldir="/tmp/openssl-tvOS-${ARCH}" $CUSTOMCONFIG &> "/tmp/openssl-tvOS-${ARCH}.log"
	fi
	# add -isysroot to CC=
	sed -ie "s!^CFLAGS=!CFLAGS=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} !" "Makefile"

	make -j8 >> "/tmp/openssl-tvOS-${ARCH}.log" 2>&1
	make install_sw -j8 >> "/tmp/openssl-tvOS-${ARCH}.log" 2>&1
	cp -r "/tmp/openssl-tvOS-${ARCH}" "/tmp/openssl-tvOS-${ARCH}-archived"
	make clean >> "/tmp/openssl-tvOS-${ARCH}.log" 2>&1
	mv "/tmp/openssl-tvOS-${ARCH}-archived" "/tmp/openssl-tvOS-${ARCH}"
	popd > /dev/null
}


echo -e "${bold}Cleaning up${dim}"
rm -rf include/openssl/* lib/*
rm -rf /tmp/openssl-*

mkdir -p Mac/lib
mkdir -p iOS/lib
mkdir -p tvOS/lib
mkdir -p Mac/include/openssl/
mkdir -p iOS/include/openssl/
mkdir -p tvOS/include/openssl/

rm -rf "/tmp/openssl-*"
rm -rf "/tmp/openssl-*.log"

rm -rf "openssl"

echo "Cloning openssl"
git clone --depth 1 -b OpenSSL_1_1_1d-quic-draft-27 https://github.com/tatsuhiro-t/openssl.git

echo "** Building OpenSSL 1.1.1 **"

if [ "$engine" == "1" ]; then
	echo "+ Activate Static Engine"
	sed -ie 's/\"engine/\"dynamic-engine/' openssl/Configurations/15-ios.conf
fi

echo -e "${bold}Building Mac libraries${dim}"
buildMac "x86_64"

echo "  Copying headers and libraries"
cp /tmp/openssl-x86_64/include/openssl/* Mac/include/openssl/

lipo \
	"/tmp/openssl-x86_64/lib/libcrypto.a" \
	-create -output Mac/lib/libcrypto.a

lipo \
	"/tmp/openssl-x86_64/lib/libssl.a" \
	-create -output Mac/lib/libssl.a

echo -e "${bold}Building iOS libraries${dim}"
buildIOS "armv7"
buildIOS "armv7s"
buildIOS "arm64"
buildIOS "arm64e"
buildIOS "i386"
buildIOS "x86_64"

echo "  Copying headers and libraries"
cp /tmp/openssl-iOS-arm64/include/openssl/* iOS/include/openssl/

lipo \
	"/tmp/openssl-iOS-armv7/lib/libcrypto.a" \
	"/tmp/openssl-iOS-armv7s/lib/libcrypto.a" \
	"/tmp/openssl-iOS-i386/lib/libcrypto.a" \
	"/tmp/openssl-iOS-arm64/lib/libcrypto.a" \
	"/tmp/openssl-iOS-arm64e/lib/libcrypto.a" \
	"/tmp/openssl-iOS-x86_64/lib/libcrypto.a" \
	-create -output iOS/lib/libcrypto.a

lipo \
	"/tmp/openssl-iOS-armv7/lib/libssl.a" \
	"/tmp/openssl-iOS-armv7s/lib/libssl.a" \
	"/tmp/openssl-iOS-i386/lib/libssl.a" \
	"/tmp/openssl-iOS-arm64/lib/libssl.a" \
	"/tmp/openssl-iOS-arm64e/lib/libssl.a" \
	"/tmp/openssl-iOS-x86_64/lib/libssl.a" \
	-create -output iOS/lib/libssl.a


echo -e "${bold}Building tvOS libraries${dim}"
buildTVOS "arm64"
buildTVOS "x86_64"
echo "  Copying headers and libraries"
cp /tmp/openssl-tvOS-arm64/include/openssl/* tvOS/include/openssl/

lipo \
	"/tmp/openssl-tvOS-arm64/lib/libcrypto.a" \
	"/tmp/openssl-tvOS-x86_64/lib/libcrypto.a" \
	-create -output tvOS/lib/libcrypto.a

lipo \
	"/tmp/openssl-tvOS-arm64/lib/libssl.a" \
	"/tmp/openssl-tvOS-x86_64/lib/libssl.a" \
	-create -output tvOS/lib/libssl.a

#reset trap
trap - INT TERM EXIT

echo -e "${normal}Done"
