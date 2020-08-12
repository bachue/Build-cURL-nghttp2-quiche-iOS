#!/bin/bash
# This script downloads and builds the Mac, iOS and tvOS nghttp3 libraries
#
# Credits:
# Bachue Zhou, @bachue
#   https://github.com/bachue/Build-OpenSSL-cURL
#
# NGHTTP3 - https://github.com/ngtcp2/nghttp3
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
trap 'echo -e "${alert}** ERROR with Build - Check /tmp/nghttp3*.log${alertdim}"; tail -3 /tmp/nghttp3*.log' INT TERM EXIT

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

NGHTTP3="${PWD}/../nghttp3"

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
checkTool git git

buildMac()
{
    ARCH=$1
        HOST="i386-apple-darwin"

    echo -e "${subbold}Building nghttp3 for ${archbold}${ARCH}${dim}"

    TARGET="darwin-i386-cc"

    if [[ $ARCH == "x86_64" ]]; then
        TARGET="darwin64-x86_64-cc"
    fi

    export CC="${BUILD_TOOLS}/usr/bin/clang -fembed-bitcode"
    export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode"
    export LDFLAGS="-arch ${ARCH} -L$(PWD)/../openssl/Mac/lib"

    pushd . > /dev/null
    cd nghttp3
    autoreconf -i
    ./configure --disable-shared --disable-app --enable-lib-only --prefix="${NGHTTP3}/Mac/${ARCH}" --host=${HOST} &> "/tmp/nghttp3-${ARCH}.log"
    make -j8 >> "/tmp/nghttp3-${ARCH}.log" 2>&1
    make install -j8 >> "/tmp/nghttp3-${ARCH}.log" 2>&1
    cp -r "${NGHTTP3}/Mac/${ARCH}" "${NGHTTP3}/Mac/${ARCH}-archive"
    make clean >> "/tmp/nghttp3-${ARCH}.log" 2>&1
    mv "${NGHTTP3}/Mac/${ARCH}-archive" "${NGHTTP3}/Mac/${ARCH}"
    popd > /dev/null
}

buildIOS()
{
    ARCH=$1
    BITCODE=$2

    pushd . > /dev/null
    cd nghttp3
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
    export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -L$(PWD)/../openssl/iOS/lib"

    echo -e "${subbold}Building nghttp3 for ${PLATFORM} ${IOS_SDK_VERSION} ${archbold}${ARCH}${dim}"
        if [[ "${ARCH}" == "arm64" || "${ARCH}" == "arm64e"  ]]; then
        ./configure --disable-shared --disable-app --enable-lib-only --prefix="${NGHTTP3}/iOS/${ARCH}" --host="arm-apple-darwin" &> "/tmp/nghttp3-iOS-${ARCH}-${BITCODE}.log"
        else
        ./configure --disable-shared --disable-app --enable-lib-only --prefix="${NGHTTP3}/iOS/${ARCH}" --host="${ARCH}-apple-darwin" &> "/tmp/nghttp3-iOS-${ARCH}-${BITCODE}.log"
        fi

        make -j8 >> "/tmp/nghttp3-iOS-${ARCH}-${BITCODE}.log" 2>&1
        make install -j8 >> "/tmp/nghttp3-iOS-${ARCH}-${BITCODE}.log" 2>&1
        cp -r "${NGHTTP3}/iOS/${ARCH}" "${NGHTTP3}/iOS/${ARCH}-archive"
        make clean >> "/tmp/nghttp3-iOS-${ARCH}-${BITCODE}.log" 2>&1
        mv  "${NGHTTP3}/iOS/${ARCH}-archive" "${NGHTTP3}/iOS/${ARCH}"
        popd > /dev/null
}

buildTVOS()
{
    ARCH=$1

    pushd . > /dev/null
    cd nghttp3
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
    export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -L$(PWD)/../openssl/tvOS/lib ${NGHTTP3LIB}"
    export LC_CTYPE=C

    echo -e "${subbold}Building nghttp3 for ${PLATFORM} ${TVOS_SDK_VERSION} ${archbold}${ARCH}${dim}"

    # Patch apps/speed.c to not use fork() since it's not available on tvOS
    # LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "./apps/speed.c"

    # Patch Configure to build for tvOS, not iOS
    # LANG=C sed -i -- 's/D\_REENTRANT\:iOS/D\_REENTRANT\:tvOS/' "./Configure"
    # chmod u+x ./Configure

    ./configure --disable-shared --disable-app --enable-lib-only  --prefix="${NGHTTP3}/tvOS/${ARCH}" --host="arm-apple-darwin" &> "/tmp/nghttp3-tvOS-${ARCH}.log"
    LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "config.h"

    # add -isysroot to CC=
    #sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} !" "Makefile"

    make -j8 >> "/tmp/nghttp3-tvOS-${ARCH}.log" 2>&1
    make install -j8 >> "/tmp/nghttp3-tvOS-${ARCH}.log" 2>&1
    cp -r "${NGHTTP3}/tvOS/${ARCH}" "${NGHTTP3}/tvOS/${ARCH}-archive"
    make clean >> "/tmp/nghttp3-tvOS-${ARCH}.log" 2>&1
    mv "${NGHTTP3}/tvOS/${ARCH}-archive" "${NGHTTP3}/tvOS/${ARCH}"
    popd > /dev/null
}

echo -e "${bold}Cleaning up${dim}"
rm -rf lib/*
rm -fr Mac
rm -fr iOS
rm -fr tvOS
rm -rf /tmp/nghttp3-*

mkdir -p lib

rm -rf "/tmp/nghttp3-*"
rm -rf "/tmp/nghttp3-*.log"

rm -rf "nghttp3"

echo "Cloning nghttp3"
git clone --depth 1 https://github.com/ngtcp2/nghttp3.git

echo -e "${bold}Building Mac libraries${dim}"
buildMac "x86_64"
lipo \
        "${NGHTTP3}/Mac/x86_64/lib/libnghttp3.a" \
        -create -output "${NGHTTP3}/lib/libnghttp3_Mac.a"

echo -e "${bold}Building iOS libraries (bitcode)${dim}"
buildIOS "armv7" "bitcode"
buildIOS "armv7s" "bitcode"
buildIOS "arm64" "bitcode"
buildIOS "arm64e" "bitcode"
buildIOS "x86_64" "bitcode"
buildIOS "i386" "bitcode"

lipo \
    "${NGHTTP3}/iOS/armv7/lib/libnghttp3.a" \
    "${NGHTTP3}/iOS/armv7s/lib/libnghttp3.a" \
    "${NGHTTP3}/iOS/i386/lib/libnghttp3.a" \
    "${NGHTTP3}/iOS/arm64/lib/libnghttp3.a" \
    "${NGHTTP3}/iOS/arm64e/lib/libnghttp3.a" \
    "${NGHTTP3}/iOS/x86_64/lib/libnghttp3.a" \
    -create -output "${NGHTTP3}/lib/libnghttp3_iOS.a"

echo -e "${bold}Building tvOS libraries${dim}"
buildTVOS "arm64"
buildTVOS "x86_64"

lipo \
        "${NGHTTP3}/tvOS/arm64/lib/libnghttp3.a" \
        "${NGHTTP3}/tvOS/x86_64/lib/libnghttp3.a" \
        -create -output "${NGHTTP3}/lib/libnghttp3_tvOS.a"

#reset trap
trap - INT TERM EXIT

echo -e "${normal}Done"
