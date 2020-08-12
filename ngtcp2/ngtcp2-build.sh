#!/bin/bash
# This script downloads and builds the Mac, iOS and tvOS ngtcp2 libraries
#
# Credits:
# Bachue Zhou, @bachue
#   https://github.com/bachue/Build-OpenSSL-cURL
#
# NGTCP2 - https://github.com/ngtcp2/ngtcp2
#

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

# set trap to help debug build errors
trap 'echo -e "${alert}** ERROR with Build - Check /tmp/ngtcp2*.log${alertdim}"; tail -3 /tmp/ngtcp2*.log' INT TERM EXIT

IOS_MIN_SDK_VERSION="7.1"
IOS_SDK_VERSION=""
TVOS_MIN_SDK_VERSION="9.0"
TVOS_SDK_VERSION=""
usage ()
{
    echo
    echo -e "${bold}Usage:${normal}"
    echo
    echo -e "  ${subbold}$0${normal} [-s ${dim}<iOS SDK version>${normal}] [-t ${dim}<tvOS SDK version>${normal}] [-x] [-h]"
    echo
    echo "         -s   iOS SDK version (default $IOS_MIN_SDK_VERSION)"
    echo "         -t   tvOS SDK version (default $TVOS_MIN_SDK_VERSION)"
    echo "         -x   disable color output"
    echo "         -h   show usage"
    echo
    trap - INT TERM EXIT
    exit 127
}

while getopts "s:t:xh\?" o; do
    case "${o}" in
        s)
            IOS_SDK_VERSION="${OPTARG}"
            ;;
        t)
            TVOS_SDK_VERSION="${OPTARG}"
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

NGTCP2="${PWD}/../ngtcp2"

# Check to see if autoconf is already installed
if (type "autoreconf" > /dev/null) ; then
    echo "  autoconf already installed"
else
    echo -e "${alertdim}** WARNING: autoconf not installed... attempting to install.${dim}"

    # Check to see if Brew is installed
    if ! type "brew" > /dev/null; then
        echo -e "${alert}** FATAL ERROR: brew not installed - unable to install autoconf - exiting.${normal}"
        exit
    else
        echo "  brew installed - using to install autoconf"
        brew install autoconf
    fi

    # Check to see if installation worked
    if (type "autoreconf" > /dev/null) ; then
        echo "  SUCCESS: autoconf installed"
    else
        echo -e "${alert}** FATAL ERROR: autoconf failed to install - exiting.${normal}"
        exit
    fi
fi

# Check to see if git is already installed
if (type "git" > /dev/null) ; then
    echo "  git already installed"
else
    echo -e "${alertdim}** WARNING: git not installed... attempting to install.${dim}"

    # Check to see if Brew is installed
    if ! type "brew" > /dev/null; then
        echo -e "${alert}** FATAL ERROR: brew not installed - unable to install git - exiting.${normal}"
        exit
    else
        echo "  brew installed - using to install git"
        brew install git
    fi

    # Check to see if installation worked
    if (type "git" > /dev/null) ; then
        echo "  SUCCESS: git installed"
    else
        echo -e "${alert}** FATAL ERROR: git failed to install - exiting.${normal}"
        exit
    fi
fi

buildMac()
{
    ARCH=$1
        HOST="i386-apple-darwin"

    echo -e "${subbold}Building ngtcp2 for ${archbold}${ARCH}${dim}"

    TARGET="darwin-i386-cc"

    if [[ $ARCH == "x86_64" ]]; then
        TARGET="darwin64-x86_64-cc"
    fi

    export CC="${BUILD_TOOLS}/usr/bin/clang -fembed-bitcode"
    export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode"
    export LDFLAGS="-arch ${ARCH} -L$(PWD)/../openssl/Mac/lib -L$(PWD)/../nghttp3/Mac/lib -Wl,-rpath,/tmp/openssl-${ARCH}/lib"
    export PKG_CONFIG_PATH="/tmp/openssl-${ARCH}/lib/pkgconfig:$(PWD)/../nghttp3/Mac/${ARCH}/lib/pkgconfig"

    pushd . > /dev/null
    cd ngtcp2
    autoreconf -i
    ./configure --disable-shared --disable-app --enable-lib-only --prefix="${NGTCP2}/Mac/${ARCH}" --host=${HOST} &> "/tmp/ngtcp2-${ARCH}.log"
    make -j8 >> "/tmp/ngtcp2-${ARCH}.log" 2>&1
    make install >> "/tmp/ngtcp2-${ARCH}.log" 2>&1
    cp -r "${NGTCP2}/Mac/${ARCH}" "${NGTCP2}/Mac/${ARCH}-archive"
    make clean >> "/tmp/ngtcp2-${ARCH}.log" 2>&1
    mv "${NGTCP2}/Mac/${ARCH}-archive" "${NGTCP2}/Mac/${ARCH}"
    popd > /dev/null
}

buildIOS()
{
    ARCH=$1
    BITCODE=$2

    pushd . > /dev/null
    cd ngtcp2
    autoreconf -i

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

    export $PLATFORM
    export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
    export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
    export BUILD_TOOLS="${DEVELOPER}"
    export CC="${BUILD_TOOLS}/usr/bin/gcc"
    export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${IOS_MIN_SDK_VERSION} ${CC_BITCODE_FLAG}"
    export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -L$(PWD)/../openssl/iOS/lib -L$(PWD)/../nghttp3/iOS/lib -Wl,-rpath,/tmp/openssl-iOS-${ARCH}/lib"
    export PKG_CONFIG_PATH="/tmp/openssl-iOS-${ARCH}/lib/pkgconfig:$(PWD)/../nghttp3/iOS/${ARCH}/lib/pkgconfig"

    echo -e "${subbold}Building ngtcp2 for ${PLATFORM} ${IOS_SDK_VERSION} ${archbold}${ARCH}${dim}"
        if [[ "${ARCH}" == "arm64" || "${ARCH}" == "arm64e"  ]]; then
        ./configure --disable-shared --disable-app --enable-lib-only --prefix="${NGTCP2}/iOS/${ARCH}" --host="arm-apple-darwin" &> "/tmp/ngtcp2-iOS-${ARCH}-${BITCODE}.log"
        else
        ./configure --disable-shared --disable-app --enable-lib-only --prefix="${NGTCP2}/iOS/${ARCH}" --host="${ARCH}-apple-darwin" &> "/tmp/ngtcp2-iOS-${ARCH}-${BITCODE}.log"
        fi

        make -j8 >> "/tmp/ngtcp2-iOS-${ARCH}-${BITCODE}.log" 2>&1
        make install >> "/tmp/ngtcp2-iOS-${ARCH}-${BITCODE}.log" 2>&1
        cp -r "${NGTCP2}/iOS/${ARCH}" "${NGTCP2}/iOS/${ARCH}-archive"
        make clean >> "/tmp/ngtcp2-iOS-${ARCH}-${BITCODE}.log" 2>&1
        mv "${NGTCP2}/iOS/${ARCH}-archive" "${NGTCP2}/iOS/${ARCH}"
        popd > /dev/null
}

buildTVOS()
{
    ARCH=$1

    pushd . > /dev/null
    cd ngtcp2
    autoreconf -i

    if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
        PLATFORM="AppleTVSimulator"
    else
        PLATFORM="AppleTVOS"
    fi

    export $PLATFORM
    export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
    export CROSS_SDK="${PLATFORM}${TVOS_SDK_VERSION}.sdk"
    export BUILD_TOOLS="${DEVELOPER}"
    export CC="${BUILD_TOOLS}/usr/bin/gcc"
    export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} -fembed-bitcode"
    export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} ${NGTCP2LIB} -L$(PWD)/../openssl/tvOS/lib -L$(PWD)/../nghttp3/tvOS/lib -Wl,-rpath,/tmp/openssl-tvOS-${ARCH}/lib"
    export LC_CTYPE=C
    export PKG_CONFIG_PATH="/tmp/openssl-tvOS-${ARCH}/lib/pkgconfig:$(PWD)/../nghttp3/tvOS/${ARCH}/lib/pkgconfig"

    echo -e "${subbold}Building ngtcp2 for ${PLATFORM} ${TVOS_SDK_VERSION} ${archbold}${ARCH}${dim}"

    # Patch apps/speed.c to not use fork() since it's not available on tvOS
    # LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "./apps/speed.c"

    # Patch Configure to build for tvOS, not iOS
    # LANG=C sed -i -- 's/D\_REENTRANT\:iOS/D\_REENTRANT\:tvOS/' "./Configure"
    # chmod u+x ./Configure

    ./configure --disable-shared --disable-app --enable-lib-only --prefix="${NGTCP2}/tvOS/${ARCH}" --host="arm-apple-darwin" &> "/tmp/ngtcp2-tvOS-${ARCH}.log"
    LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "config.h"

    # add -isysroot to CC=
    #sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} !" "Makefile"

    make -j8  >> "/tmp/ngtcp2-tvOS-${ARCH}.log" 2>&1
    make install  >> "/tmp/ngtcp2-tvOS-${ARCH}.log" 2>&1
    cp -r "${NGTCP2}/tvOS/${ARCH}" "${NGTCP2}/tvOS/${ARCH}-archive"
    make clean >> "/tmp/ngtcp2-tvOS-${ARCH}.log" 2>&1
    mv "${NGTCP2}/tvOS/${ARCH}-archive" "${NGTCP2}/tvOS/${ARCH}"
    popd > /dev/null
}

echo -e "${bold}Cleaning up${dim}"
rm -rf lib/*
rm -fr Mac
rm -fr iOS
rm -fr tvOS
rm -rf /tmp/ngtcp2-*

mkdir -p lib

rm -rf "/tmp/ngtcp2-*"
rm -rf "/tmp/ngtcp2-*.log"

rm -rf "ngtcp2"

echo "Cloning ngtcp2"
git clone https://github.com/ngtcp2/ngtcp2.git
(cd ngtcp2 && git checkout -f a09a480c6d3d2ef7633bea55bfd3cf5457b04086)

echo -e "${bold}Building Mac libraries${dim}"
buildMac "x86_64"
lipo \
        "${NGTCP2}/Mac/x86_64/lib/libngtcp2.a" \
        -create -output "${NGTCP2}/lib/libngtcp2_Mac.a"
lipo \
        "${NGTCP2}/Mac/x86_64/lib/libngtcp2_crypto_openssl.a" \
        -create -output "${NGTCP2}/lib/libngtcp2_crypto_openssl_Mac.a"

echo -e "${bold}Building iOS libraries (bitcode)${dim}"
buildIOS "armv7" "bitcode"
buildIOS "armv7s" "bitcode"
buildIOS "arm64" "bitcode"
buildIOS "arm64e" "bitcode"
buildIOS "x86_64" "bitcode"
buildIOS "i386" "bitcode"

lipo \
    "${NGTCP2}/iOS/armv7/lib/libngtcp2.a" \
    "${NGTCP2}/iOS/armv7s/lib/libngtcp2.a" \
    "${NGTCP2}/iOS/i386/lib/libngtcp2.a" \
    "${NGTCP2}/iOS/arm64/lib/libngtcp2.a" \
    "${NGTCP2}/iOS/arm64e/lib/libngtcp2.a" \
    "${NGTCP2}/iOS/x86_64/lib/libngtcp2.a" \
    -create -output "${NGTCP2}/lib/libngtcp2_iOS.a"

lipo \
    "${NGTCP2}/iOS/armv7/lib/libngtcp2_crypto_openssl.a" \
    "${NGTCP2}/iOS/armv7s/lib/libngtcp2_crypto_openssl.a" \
    "${NGTCP2}/iOS/i386/lib/libngtcp2_crypto_openssl.a" \
    "${NGTCP2}/iOS/arm64/lib/libngtcp2_crypto_openssl.a" \
    "${NGTCP2}/iOS/arm64e/lib/libngtcp2_crypto_openssl.a" \
    "${NGTCP2}/iOS/x86_64/lib/libngtcp2_crypto_openssl.a" \
    -create -output "${NGTCP2}/lib/libngtcp2_crypto_openssl_iOS.a"

echo -e "${bold}Building tvOS libraries${dim}"
buildTVOS "arm64"
buildTVOS "x86_64"

lipo \
        "${NGTCP2}/tvOS/arm64/lib/libngtcp2.a" \
        "${NGTCP2}/tvOS/x86_64/lib/libngtcp2.a" \
        -create -output "${NGTCP2}/lib/libngtcp2_tvOS.a"

lipo \
        "${NGTCP2}/tvOS/arm64/lib/libngtcp2_crypto_openssl.a" \
        "${NGTCP2}/tvOS/x86_64/lib/libngtcp2_crypto_openssl.a" \
        -create -output "${NGTCP2}/lib/libngtcp2_crypto_openssl_tvOS.a"

#reset trap
trap - INT TERM EXIT

echo -e "${normal}Done"
