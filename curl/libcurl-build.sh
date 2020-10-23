#!/bin/bash -x

# This script downloads and builds the Mac, iOS libcurl libraries with Bitcode enabled

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
# Bachue Zhou
#   https://github.com/bachue/Build-cURL-nghttp2-quiche-iOS

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

CURL_VERSION="curl-7.73.0"
IOS_SDK_VERSION=""
IOS_MIN_SDK_VERSION="7.1"
nohttp2="0"
noquiche="0"

usage ()
{
	echo
	echo -e "${bold}Usage:${normal}"
	echo
	echo -e "  ${subbold}$0${normal} [-v ${dim}<curl version>${normal}] [-s ${dim}<iOS SDK version>${normal}] [-b] [-x] [-2] [-q] [-h]"
    echo
	echo "         -v   version of curl (default $CURL_VERSION)"
	echo "         -s   iOS SDK version (default $IOS_MIN_SDK_VERSION)"
	echo "         -b   compile without bitcode"
	echo "         -2   compile with nghttp2"
	echo "         -q   compile with quiche"
	echo "         -x   disable color output"
	echo "         -h   show usage"
	echo
	trap - INT TERM EXIT
	exit 127
}

while getopts "v:s:b2qxh\?" o; do
    case "${o}" in
        v)
	    CURL_VERSION="curl-${OPTARG}"
            ;;
        s)
            IOS_SDK_VERSION="${OPTARG}"
            ;;
	2)
	    nohttp2="1"
	    ;;
	q)
	    noquiche="1"
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
fi

# HTTP3 support
if [ $noquiche == "1" ]; then
    QUICHE="${PWD}/../quiche"
    echo "Building with HTTP3 Support (quiche)"
else
    echo "Building without HTTP3 Support (quiche)"
    QUICHECFG=""
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

	if [ "$nohttp2" == "1" ]; then
		NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/Mac/${ARCH}"
	fi
	if [ "$noquiche" == "1" ]; then
		QUICHECFG="--with-quiche=${QUICHE}/Mac"
		OPENSSLCFG="--with-ssl=${QUICHE}/Mac/${HOST}/openssl"
	fi

	export CC="${BUILD_TOOLS}/usr/bin/clang"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode"
	export LDFLAGS="-arch ${ARCH} -Wl,-rpath,${QUICHE}/Mac/${HOST}/openssl/lib"
	export PKG_CONFIG_PATH="$(PWD)/../nghttp2/Mac/${ARCH}/lib/pkgconfig"
	pushd . > /dev/null
	cd "${CURL_VERSION}"
	./configure --prefix="/tmp/${CURL_VERSION}-${ARCH}" \
	    --disable-shared \
            --enable-optimize \
            --enable-static \
            --enable-ipv6 \
            --with-random=/dev/urandom \
            ${NGHTTP2CFG} ${OPENSSLCFG} ${QUICHECFG} \
            --host=${HOST} &> "/tmp/${CURL_VERSION}-${ARCH}.log"

	make -j8 >> "/tmp/${CURL_VERSION}-${ARCH}.log" 2>&1
	make install -j8 >> "/tmp/${CURL_VERSION}-${ARCH}.log" 2>&1
	make clean >> "/tmp/${CURL_VERSION}-${ARCH}.log" 2>&1
	popd > /dev/null
}

buildIOS()
{
	ARCH=$1
	BITCODE=$2
	HOST=$3

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

	if [ "$nohttp2" == "1" ]; then
		NGHTTP2CFG="--with-nghttp2=${NGHTTP2}/iOS/${ARCH}"
	fi
	if [ "$noquiche" == "1" ]; then
		QUICHECFG="--with-quiche=${QUICHE}/iOS"
		OPENSSLCFG="--with-ssl=${QUICHE}/iOS/${HOST}/openssl"
	fi

	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${IOS_MIN_SDK_VERSION} ${CC_BITCODE_FLAG}"
	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -Wl,-rpath,${QUICHE}/iOS/${HOST}/openssl/lib"

	echo -e "${subbold}Building ${CURL_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${archbold}${ARCH}${dim} ${BITCODE}"

	if [[ "${ARCH}" == *"arm64"* || "${ARCH}" == "arm64e" ]]; then
		./configure \
		    --prefix="/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}" \
                    --disable-shared \
                    --enable-static \
                    --with-random=/dev/urandom \
                    --with-ssl="${QUICHE}/iOS/${HOST}/openssl/" \
		    ${NGHTTP2CFG} ${OPENSSLCFG} ${QUICHECFG} --host="arm-apple-darwin" &> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	else
		./configure \
		    --prefix="/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}" \
                    --disable-shared \
                    --enable-static \
                    --with-random=/dev/urandom \
                    --with-ssl="${QUICHE}/iOS/${HOST}/openssl/" \
                    ${NGHTTP2CFG} ${OPENSSLCFG} ${QUICHECFG} --host="${ARCH}-apple-darwin" &> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	fi

	make -j8 >> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	make install -j8 >> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	make clean >> "/tmp/${CURL_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
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
buildIOS "arm64" "bitcode" "aarch64-apple-ios"
buildIOS "x86_64" "bitcode" "x86_64-apple-ios"

lipo \
	"/tmp/${CURL_VERSION}-iOS-arm64-bitcode/lib/libcurl.a" \
	"/tmp/${CURL_VERSION}-iOS-x86_64-bitcode/lib/libcurl.a" \
	-create -output lib/libcurl_iOS.a


if [[ "${NOBITCODE}" == "yes" ]]; then
	echo -e "${bold}Building iOS libraries (nobitcode)${dim}"
	buildIOS "arm64" "nobitcode"
	buildIOS "x86_64" "nobitcode"

	lipo \
		"/tmp/${CURL_VERSION}-iOS-arm64-nobitcode/lib/libcurl.a" \
		"/tmp/${CURL_VERSION}-iOS-x86_64-nobitcode/lib/libcurl.a" \
		-create -output lib/libcurl_iOS_nobitcode.a

fi

echo -e "${bold}Cleaning up${dim}"
rm -rf /tmp/${CURL_VERSION}-*
rm -rf ${CURL_VERSION}

echo "Checking libraries"
xcrun -sdk iphoneos lipo -info lib/*.a

#reset trap
trap - INT TERM EXIT

echo -e "${normal}Done"
