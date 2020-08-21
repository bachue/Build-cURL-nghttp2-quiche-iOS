#!/bin/bash

# This script downloads and builds the Mac, iOS and tvOS libcurl libraries with Bitcode enabled

# Credits:
#
# Felix Schwarz, IOSPIRIT GmbH, @@felix_schwarz.
#   https://gist.github.com/c61c0f7d9ab60f53ebb0.git
# Bochun Bai
#   https://github.com/sinofool/build-libcurl-ios
# Jason Cox, @jasonacox
#   https://github.com/jasonacox/Build-OpenSSL-cURL
# Preston Jennings
#   https://github.com/prestonj/Build-OpenSSL-cURL

set -e

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

# set trap to help debug any build errors
trap 'echo -e "${alert}** ERROR with Build - Check /tmp/curl*.log${alertdim}"; tail -3 /tmp/curl*.log' INT TERM EXIT

CURL_VERSION="curl-7.72.0"
IOS_SDK_VERSION=""
IOS_MIN_SDK_VERSION="7.1"
TVOS_SDK_VERSION=""
TVOS_MIN_SDK_VERSION="9.0"
IPHONEOS_DEPLOYMENT_TARGET="6.0"
nohttp2="0"
nohttp3="0"

usage ()
{
	echo
	echo -e "${bold}Usage:${normal}"
	echo
	echo -e "  ${subbold}$0${normal} [-v ${dim}<curl version>${normal}] [-s ${dim}<iOS SDK version>${normal}] [-t ${dim}<tvOS SDK version>${normal}] [-i ${dim}<iPhone target version>${normal}] [-b] [-x] [-2] [-3] [-h]"
    echo
	echo "         -v   version of curl (default $CURL_VERSION)"
	echo "         -s   iOS SDK version (default $IOS_MIN_SDK_VERSION)"
	echo "         -t   tvOS SDK version (default $TVOS_MIN_SDK_VERSION)"
	echo "         -i   iPhone target version (default $IPHONEOS_DEPLOYMENT_TARGET)"
	echo "         -b   compile without bitcode"
	echo "         -2   compile with nghttp2"
	echo "         -3   compile with nghttp3"
	echo "         -x   disable color output"
	echo "         -h   show usage"
	echo
	trap - INT TERM EXIT
	exit 127
}

while getopts "v:s:t:i:nbxh\?" o; do
    case "${o}" in
        v)
			CURL_VERSION="curl-${OPTARG}"
            ;;
        s)
            IOS_SDK_VERSION="${OPTARG}"
            ;;
        t)
	    	TVOS_SDK_VERSION="${OPTARG}"
            ;;
        i)
	    	IPHONEOS_DEPLOYMENT_TARGET="${OPTARG}"
            ;;
		2)
			nohttp2="1"
			;;
		3)
			nohttp3="1"
			;;
		b)
			NOBITCODE="yes"
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

# HTTP2 support
if [ $nohttp2 == "1" ]; then
	NGHTTP2="${PWD}/../nghttp2"
	echo "Building with HTTP2 Support (nghttp2)"
else
	echo "Building without HTTP2 Support (nghttp2)"
	NGHTTP2CFG=""
	NGHTTP2LIB=""
fi

# HTTP3 support
if [ $nohttp3 == "1" ]; then
	NGHTTP3="${PWD}/../nghttp3"
	NGTCP2="${PWD}/../ngtcp2"
	echo "Building with HTTP3 Support (ngtcp2)"
else
	echo "Building without HTTP3 Support (ngtcp2)"
	NGHTTP3CFG=""
	NGHTTP3LIB=""
	NGTCP2CFG=""
	NGTCP2LIB=""
fi

checkTool()
{
    TOOL=$1
    PKG=$2

    if (type "$1" > /dev/null) ; then
        echo "  $2 already installed"
    else
        echo -e "${alertdim}** WARNING: $2 not installed... attempting to install.${dim}"

        # Check to see if Brew is installed
        if ! type "brew" > /dev/null; then
            echo -e "${alert}** FATAL ERROR: brew not installed - unable to install $2 - exiting.${normal}"
            exit
        else
            echo "  brew installed - using to install $2"
            brew install "$2"
        fi

        # Check to see if installation worked
        if (type "$1" > /dev/null) ; then
            echo "  SUCCESS: $2 installed"
        else
            echo -e "${alert}** FATAL ERROR: $2 failed to install - exiting.${normal}"
            exit
        fi
    fi
}

checkTool autoreconf autoconf
checkTool aclocal automake
checkTool libtool libtool

buildMac()
{
	ARCH=$1
	HOST="x86_64-apple-darwin"

	echo -e "${subbold}Building ${CURL_VERSION} for ${archbold}${ARCH}${dim}"

	TARGET="darwin-i386-cc"

	if [[ $ARCH == "x86_64" ]]; then
		TARGET="darwin64-x86_64-cc"
	fi

	if [ $nohttp2 == "1" ]; then
		NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/Mac/${ARCH}"
		NGHTTP2LIB="-L${NGHTTP2}/Mac/${ARCH}/lib"
	fi
	if [ $nohttp3 == "1" ]; then
		NGHTTP3CFG="--with-nghttp3=${NGHTTP3}/Mac/${ARCH}"
		NGHTTP3LIB="-L${NGHTTP3}/Mac/${ARCH}/lib"
		NGTCP2CFG="--with-ngtcp2=${NGTCP2}/Mac/${ARCH}"
		NGTCP2LIB="-L${NGTCP2}/Mac/${ARCH}/lib"
	fi

	export CC="${BUILD_TOOLS}/usr/bin/clang"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode"
	export LDFLAGS="-arch ${ARCH} -Wl,-rpath,/tmp/openssl-${ARCH}/lib"
    export PKG_CONFIG_PATH="/tmp/openssl-${ARCH}/lib/pkgconfig:$(PWD)/../nghttp3/Mac/${ARCH}/lib/pkgconfig:$(PWD)/../ngtcp2/Mac/${ARCH}/lib/pkgconfig"
	pushd . > /dev/null
	cd "${CURL_VERSION}"
	./configure -prefix="/tmp/${CURL_VERSION}-${ARCH}" --disable-shared --enable-optimize --enable-static --enable-ipv6 --with-random=/dev/urandom --with-ssl=/tmp/openssl-${ARCH} ${NGHTTP2CFG} ${NGHTTP3CFG} ${NGTCP2CFG} --host=${HOST} --enable-alt-svc &> "/tmp/${CURL_VERSION}-${ARCH}.log"

	make -j8 >> "/tmp/${CURL_VERSION}-${ARCH}.log" 2>&1
	make install -j8 >> "/tmp/${CURL_VERSION}-${ARCH}.log" 2>&1
	# Save curl binary for Mac Version
	cp "/tmp/${CURL_VERSION}-${ARCH}/bin/curl" "/tmp/curl"
	make clean >> "/tmp/${CURL_VERSION}-${ARCH}.log" 2>&1
	popd > /dev/null
}

buildIOS()
{
	ARCH=$1
	BITCODE=$2

	pushd . > /dev/null
	cd "${CURL_VERSION}"

	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="iPhoneSimulator"
	else
		PLATFORM="iPhoneOS"
	fi

	if [[ "${BITCODE}" == "nobitcode" ]]; then
		CC_BITCODE_FLAG=""
	else
		CC_BITCODE_FLAG="-fembed-bitcode"
	fi

	if [ $nohttp2 == "1" ]; then
		NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/iOS/${ARCH}"
		NGHTTP2LIB="-L${NGHTTP2}/iOS/${ARCH}/lib"
	fi
	if [ $nohttp3 == "1" ]; then
		NGHTTP3CFG="--with-nghttp3=${NGHTTP3}/iOS/${ARCH}"
		NGHTTP3LIB="-L${NGHTTP3}/iOS/${ARCH}/lib"
		NGTCP2CFG="--with-ngtcp2=${NGTCP2}/iOS/${ARCH}"
		NGTCP2LIB="-L${NGTCP2}/iOS/${ARCH}/lib"
	fi

	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${IOS_MIN_SDK_VERSION} ${CC_BITCODE_FLAG}"
	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -Wl,-rpath,/tmp/openssl-iOS-${ARCH}/lib"
    export PKG_CONFIG_PATH="/tmp/openssl-iOS-${ARCH}/lib/pkgconfig:$(PWD)/../nghttp3/iOS/${ARCH}/lib/pkgconfig:$(PWD)/../ngtcp2/iOS/${ARCH}/lib/pkgconfig"

	echo -e "${subbold}Building ${CURL_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${archbold}${ARCH}${dim} ${BITCODE}"

	if [[ "${ARCH}" == *"arm64"* || "${ARCH}" == "arm64e" ]]; then
		./configure -prefix="/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}" --disable-shared --enable-static -with-random=/dev/urandom --with-ssl=/tmp/openssl-iOS-${ARCH} ${NGHTTP2CFG} ${NGHTTP3CFG} ${NGTCP2CFG} --host="arm-apple-darwin" --enable-alt-svc &> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	else
		./configure -prefix="/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}" --disable-shared --enable-static -with-random=/dev/urandom --with-ssl=/tmp/openssl-iOS-${ARCH} ${NGHTTP2CFG} ${NGHTTP3CFG} ${NGTCP2CFG} --host="${ARCH}-apple-darwin" --enable-alt-svc &> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	fi

	make -j8 >> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	make install -j8 >> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	make clean >> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	popd > /dev/null
}

buildTVOS()
{
	ARCH=$1

	pushd . > /dev/null
	cd "${CURL_VERSION}"

	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="AppleTVSimulator"
	else
		PLATFORM="AppleTVOS"
	fi

	if [ $nohttp2 == "1" ]; then
		NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/tvOS/${ARCH}"
		NGHTTP2LIB="-L${NGHTTP2}/tvOS/${ARCH}/lib"
	fi
	if [ $nohttp3 == "1" ]; then
		NGHTTP3CFG="--with-nghttp3=${NGHTTP3}/tvOS/${ARCH}"
		NGHTTP3LIB="-L${NGHTTP3}/tvOS/${ARCH}/lib"
		NGTCP2CFG="--with-ngtcp2=${NGTCP2}/tvOS/${ARCH}"
		NGTCP2LIB="-L${NGTCP2}/tvOS/${ARCH}/lib"
	fi

	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${TVOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} -fembed-bitcode"
	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -Wl,-rpath,/tmp/openssl-tvOS-${ARCH}/lib"
    export PKG_CONFIG_PATH="/tmp/openssl-tvOS-${ARCH}/lib/pkgconfig:$(PWD)/../nghttp3/tvOS/${ARCH}/lib/pkgconfig:$(PWD)/../ngtcp2/tvOS/${ARCH}/lib/pkgconfig"

	echo -e "${subbold}Building ${CURL_VERSION} for ${PLATFORM} ${TVOS_SDK_VERSION} ${archbold}${ARCH}${dim}"

    autoreconf -i
	./configure -prefix="/tmp/${CURL_VERSION}-tvOS-${ARCH}" --host="arm-apple-darwin" --disable-shared -with-random=/dev/urandom --disable-ntlm-wb --with-ssl="/tmp/openssl-tvOS-${ARCH}" ${NGHTTP2CFG} ${NGHTTP3CFG} ${NGTCP2CFG} --enable-alt-svc &> "/tmp/${CURL_VERSION}-tvOS-${ARCH}.log"

	# Patch to not use fork() since it's not available on tvOS
    LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "./lib/curl_config.h"
    LANG=C sed -i -- 's/HAVE_FORK"]=" 1"/HAVE_FORK\"]=" 0"/' "config.status"

	make -j8 >> "/tmp/${CURL_VERSION}-tvOS-${ARCH}.log" 2>&1
	make install -j8 >> "/tmp/${CURL_VERSION}-tvOS-${ARCH}.log" 2>&1
	make clean >> "/tmp/${CURL_VERSION}-tvOS-${ARCH}.log" 2>&1
	popd > /dev/null
}

echo -e "${bold}Cleaning up${dim}"
rm -rf include/curl/* lib/*

mkdir -p lib
mkdir -p include/curl/

rm -rf "/tmp/${CURL_VERSION}-*"
rm -rf "/tmp/${CURL_VERSION}-*.log"

rm -rf "${CURL_VERSION}"

if [ ! -f ${CURL_VERSION}.tar.gz ]; then
	echo "Downloading ${CURL_VERSION}.tar.gz"
	curl -LO https://curl.haxx.se/download/${CURL_VERSION}.tar.gz
else
	echo "Using ${CURL_VERSION}.tar.gz"
fi

rm -rf "${CURL_VERSION}"
echo "Unpacking curl"
tar xfz "${CURL_VERSION}.tar.gz"

echo -e "${bold}Building Mac libraries${dim}"
buildMac "x86_64"

echo "  Copying headers"
cp /tmp/${CURL_VERSION}-x86_64/include/curl/* include/curl/

lipo \
	"/tmp/${CURL_VERSION}-x86_64/lib/libcurl.a" \
	-create -output lib/libcurl_Mac.a

echo -e "${bold}Building iOS libraries (bitcode)${dim}"
buildIOS "armv7" "bitcode"
buildIOS "armv7s" "bitcode"
buildIOS "arm64" "bitcode"
buildIOS "arm64e" "bitcode"
buildIOS "x86_64" "bitcode"
buildIOS "i386" "bitcode"

lipo \
	"/tmp/${CURL_VERSION}-iOS-armv7-bitcode/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-iOS-armv7s-bitcode/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-iOS-i386-bitcode/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-iOS-arm64-bitcode/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-iOS-arm64e-bitcode/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-iOS-x86_64-bitcode/lib/libcurl.a" \
	-create -output lib/libcurl_iOS.a


if [[ "${NOBITCODE}" == "yes" ]]; then
	echo -e "${bold}Building iOS libraries (nobitcode)${dim}"
	buildIOS "armv7" "nobitcode"
	buildIOS "armv7s" "nobitcode"
	buildIOS "arm64" "nobitcode"
	buildIOS "arm64e" "nobitcode"
	buildIOS "x86_64" "nobitcode"
	buildIOS "i386" "nobitcode"

	lipo \
		"/tmp/${CURL_VERSION}-iOS-armv7-nobitcode/lib/libcurl.a" \
		"/tmp/${CURL_VERSION}-iOS-armv7s-nobitcode/lib/libcurl.a" \
		"/tmp/${CURL_VERSION}-iOS-i386-nobitcode/lib/libcurl.a" \
		"/tmp/${CURL_VERSION}-iOS-arm64-nobitcode/lib/libcurl.a" \
		"/tmp/${CURL_VERSION}-iOS-arm64e-nobitcode/lib/libcurl.a" \
		"/tmp/${CURL_VERSION}-iOS-x86_64-nobitcode/lib/libcurl.a" \
		-create -output lib/libcurl_iOS_nobitcode.a

fi

echo -e "${bold}Building tvOS libraries${dim}"
buildTVOS "arm64"
buildTVOS "x86_64"

lipo \
	"/tmp/${CURL_VERSION}-tvOS-arm64/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-tvOS-x86_64/lib/libcurl.a" \
	-create -output lib/libcurl_tvOS.a


echo -e "${bold}Cleaning up${dim}"
rm -rf /tmp/${CURL_VERSION}-*
rm -rf ${CURL_VERSION}

echo "Checking libraries"
xcrun -sdk iphoneos lipo -info lib/*.a

#reset trap
trap - INT TERM EXIT

echo -e "${normal}Done"
