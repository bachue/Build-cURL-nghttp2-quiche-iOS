#!/bin/bash -x
# This script downloads and builds the Mac, iOS quiche libraries
#
# Credits:
# Bachue Zhou, @bachue
#   https://github.com/bachue/Build-cURL-nghttp2-quiche-iOS
# QUICHE - https://github.com/cloudflare/quiche.git
#

# > quiche is an implementation of the QUIC transport protocol 
# > and HTTP/3 as specified by the IETF.

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
trap 'echo -e "${alert}** ERROR with Build - Check /tmp/quiche*.log${alertdim}"; tail -3 /tmp/quiche*.log' INT TERM EXIT

QUICHE_VERNUM="0.6.0"
IOS_MIN_SDK_VERSION="7.1"
IOS_SDK_VERSION=""

usage ()
{
	echo
	echo -e "${bold}Usage:${normal}"
	echo
	echo -e "  ${subbold}$0${normal} [-v ${dim}<quiche version>${normal}] [-s ${dim}<iOS SDK version>${normal}] [-x] [-h]"
	echo
	echo "         -v   version of quiche (default $QUICHE_VERNUM)"
	echo "         -s   iOS SDK version (default $IOS_MIN_SDK_VERSION)"
	echo "         -x   disable color output"
	echo "         -h   show usage"
	echo
	trap - INT TERM EXIT
	exit 127
}

while getopts "v:s:xh\?" o; do
	case "${o}" in
		v)
			QUICHE_VERNUM="${OPTARG}"
			;;
		s)
			IOS_SDK_VERSION="${OPTARG}"
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

# --- Edit this to update version ---

QUICHE_VERSION="quiche-${QUICHE_VERNUM}"
DEVELOPER=`xcode-select -print-path`

QUICHE="${PWD}/../quiche"

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

checkTool curl curl
checkTool git git
checkTool cmake cmake

checkRust() {
    if (type "rustup" > /dev/null); then
        echo "  rustup already installed"
    else
        echo -e "${alertdim}** WARNING: rustup not installed... attempting to install.${dim}"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source $HOME/.cargo/env
        if (type "rustup" > /dev/null); then
            echo "  SUCCESS: rustup installed"
        else
            echo -e "${alert}** FATAL ERROR: rustup failed to install - exiting.${normal}"
            exit
        fi
    fi
    rustup target add aarch64-apple-ios x86_64-apple-darwin x86_64-apple-ios
    cargo install cargo-lipo -q
}
checkRust

build()
{
	ARCH=$1
	TARGETS=$2

	echo -e "${subbold}Building ${QUICHE_VERSION} for ${archbold}${ARCH}${dim}"

	pushd . > /dev/null
	cd "${QUICHE_VERSION}"
	cargo lipo -v --targets "$TARGETS" --release --features "pkg-config-meta,qlog" &> "/tmp/${QUICHE_VERSION}-${ARCH}.log" 
	popd > /dev/null
}

echo -e "${bold}Cleaning up${dim}"
rm -fr Mac
rm -fr iOS
rm -fr lib

rm -rf "/tmp/${QUICHE_VERSION}-*"
rm -rf "/tmp/${QUICHE_VERSION}-*.log"

if [ ! -e "${QUICHE_VERSION}" ]; then
    echo "Cloning quiche"
    git clone -b "$QUICHE_VERNUM" --recursive https://github.com/cloudflare/quiche.git "${QUICHE_VERSION}"
else
    echo "Using quiche"
    (
        cd "${QUICHE_VERSION}" 
        git reset --hard "$QUICHE_VERNUM"
        git submodule update --init --recursive
        cargo clean
    )
fi

mkdir -p lib Mac/x86_64-apple-darwin iOS/{aarch64-apple-ios,x86_64-apple-ios}

echo -e "${bold}Building Mac libraries${dim}"
build "apple-darwin" "x86_64-apple-darwin"
cp "${QUICHE_VERSION}/target/universal/release/libquiche.a" Mac/libquiche.a
cp "${QUICHE_VERSION}/target/release/quiche.pc" Mac/quiche.pc
for TARGET in x86_64-apple-darwin
do
    cp -r "${QUICHE_VERSION}/deps/boringssl/src" "Mac/${TARGET}/openssl"
    mkdir -p "Mac/${TARGET}/openssl/lib"
    ln $(find "${QUICHE_VERSION}/target/${TARGET}/release/" -type f -name libssl.a -o -type f -name libcrypto.a) "Mac/${TARGET}/openssl/lib"
done
lipo Mac/libquiche.a -create -output lib/libquiche_Mac.a
lipo $(find Mac -type f -name libssl.a) -create -output lib/libssl_Mac.a
lipo $(find Mac -type f -name libcrypto.a) -create -output lib/libcrypto_Mac.a

echo -e "${bold}Building iOS libraries${dim}"
build "apple-ios" "aarch64-apple-ios,x86_64-apple-ios"
cp "${QUICHE_VERSION}/target/universal/release/libquiche.a" iOS/libquiche.a
cp "${QUICHE_VERSION}/target/release/quiche.pc" iOS/quiche.pc
for TARGET in aarch64-apple-ios x86_64-apple-ios
do
    cp -r "${QUICHE_VERSION}/deps/boringssl/src" "iOS/${TARGET}/openssl"
    mkdir -p iOS/${TARGET}/openssl/lib
    ln $(find "${QUICHE_VERSION}/target/${TARGET}/release/" -type f -name libssl.a -o -type f -name libcrypto.a) "iOS/${TARGET}/openssl/lib"
done
lipo iOS/libquiche.a -create -output lib/libquiche_iOS.a
lipo $(find iOS -type f -name libssl.a) -create -output lib/libssl_iOS.a
lipo $(find iOS -type f -name libcrypto.a) -create -output lib/libcrypto_iOS.a

echo -e "${bold}Cleaning up${dim}"
rm -rf /tmp/${QUICHE_VERSION}-*

#reset trap
trap - INT TERM EXIT

echo -e "${normal}Done"

