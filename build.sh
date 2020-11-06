#!/bin/bash

# This script builds libcurl+nghttp2+quiche libraries for MacOS, iOS
#
# Credits:
# Jason Cox, @jasonacox
#   https://github.com/jasonacox/Build-OpenSSL-cURL
# Bachue Zhou, @bachue
#   https://github.com/bachue/Build-cURL-nghttp2-quiche-iOS
#

################################################
# EDIT this section to Select Default Versions #
################################################

LIBCURL="7.73.0"	# https://curl.haxx.se/download.html
NGHTTP2="1.41.0"	# https://nghttp2.org/
QUICHE="v0.6.0"          # https://github.com/cloudflare/quiche.git

################################################

# Global flags
engine=""
buildnghttp2="-2"
buildquiche="-q"
colorflag=""

# Formatting
default="\033[39m"
wihte="\033[97m"
green="\033[32m"
red="\033[91m"
yellow="\033[33m"

bold="\033[0m${white}\033[1m"
subbold="\033[0m${green}"
normal="${white}\033[0m"
dim="\033[0m${white}\033[2m"
alert="\033[0m${red}\033[1m"
alertdim="\033[0m${red}\033[2m"

usage ()
{
    echo
	echo -e "${bold}Usage:${normal}"
	echo
	echo -e "  ${subbold}$0${normal} [-c ${dim}<curl version>${normal}] [-n ${dim}<nghttp2 version>${normal}] [-q ${dim}<quiche version>${normal}] [-d] [-f] [-e] [-x] [-h]"
	echo
	echo "         -c <version>   Build curl version (default $LIBCURL)"
	echo "         -n <version>   Build nghttp2 version (default $NGHTTP2)"
	echo "         -q <version>   Build quiche version (default $QUICHE)"
	echo "         -d             Compile without HTTP2 support"
	echo "         -f             Compile without QUICHE support"
	echo "         -e             Compile with OpenSSL engine support" # TODO: THINK ABOUT REMOVING IT
	echo "         -x             No color output"
	echo "         -h             Show usage"
	echo
    exit 127
}

while getopts "c:n:q:dfexh\?" o; do
    case "${o}" in
		c)
			LIBCURL="${OPTARG}"
			;;
		n)
			NGHTTP2="${OPTARG}"
			;;
		q)
			QUICHE="${OPTARG}"
			;;
		d)
			buildnghttp2=""
			;;
		f)
			buildquiche=""
			;;
		e)
			engine="-e"
			;;
		x)
			bold=""
			subbold=""
			normal=""
			dim=""
			alert=""
			alertdim=""
			colorflag="-x"
			;;
		*)
			usage
			;;
    esac
done
shift $((OPTIND-1))

## Welcome
echo -e "${bold}Build-cURL-nghttp2-quiche${dim}"
echo "This script builds nghttp2, quiche and libcurl for MacOS (OS X), iOS devices."
echo "Targets: x86_64, armv7, armv7s, arm64 and arm64e"
echo

set -e

## Nghttp2 Build
if [ "$buildnghttp2" == "" ]; then
	NGHTTP2="NONE"
else
	echo
	echo -e "${bold}Building nghttp2 for HTTP2 support${normal}"
	cd nghttp2
	./nghttp2-build.sh -v "$NGHTTP2" $colorflag
	cd ..
fi

## Quiche Build
if [ -n "$buildquiche" ]; then
	echo
	echo -e "${bold}Building quiche for HTTP3 support${normal}"
	cd quiche
	./quiche-build.sh -v "$QUICHE" $colorflag
	cd ..
fi

## Curl Build
echo
echo -e "${bold}Building Curl${normal}"
cd curl
./libcurl-build.sh -v "$LIBCURL" $colorflag $buildnghttp2 $buildquiche
cd ..

echo
echo -e "${bold}Libraries...${normal}"
echo
echo -e "${subbold}nghttp2 (rename to libnghttp2.a)${normal} [${dim}$NGHTTP2${normal}]${dim}"
xcrun -sdk iphoneos lipo -info nghttp2/lib/*.a
echo
echo -e "${subbold}quiche (rename to libquiche.a)${normal} [${dim}$QUICHE${normal}]${dim}"
xcrun -sdk iphoneos lipo -info quiche/lib/*.a
echo
echo -e "${subbold}libcurl (rename to libcurl.a)${normal} [${dim}$LIBCURL${normal}]${dim}"
xcrun -sdk iphoneos lipo -info curl/lib/*.a

EXAMPLE="examples/iOS Test App"
ARCHIVE="archive/libcurl-$LIBCURL-nghttp2-$NGHTTP2-quiche-$QUICHE"

echo
echo -e "${bold}Creating archive for release v$LIBCURL...${dim}"
echo "  See $ARCHIVE"
mkdir -p "$ARCHIVE"
mkdir -p "$ARCHIVE/include/openssl"
mkdir -p "$ARCHIVE/include/curl"
mkdir -p "$ARCHIVE/lib/iOS"
mkdir -p "$ARCHIVE/lib/MacOS"
mkdir -p "$ARCHIVE/bin"
# archive libraries
cp curl/lib/libcurl_iOS.a $ARCHIVE/lib/iOS/libcurl.a
cp curl/lib/libcurl_Mac.a $ARCHIVE/lib/MacOS/libcurl.a
cp quiche/lib/libcrypto_iOS.a $ARCHIVE/lib/iOS/libcrypto.a
cp quiche/lib/libcrypto_Mac.a $ARCHIVE/lib/MacOS/libcrypto.a
cp quiche/lib/libssl_iOS.a $ARCHIVE/lib/iOS/libssl.a
cp quiche/lib/libssl_Mac.a $ARCHIVE/lib/MacOS/libssl.a
cp quiche/lib/libquiche_iOS.a $ARCHIVE/lib/iOS/libquiche.a
cp quiche/lib/libquiche_Mac.a $ARCHIVE/lib/MacOS/libquiche.a
cp nghttp2/lib/libnghttp2_iOS.a $ARCHIVE/lib/iOS/libnghttp2.a
cp nghttp2/lib/libnghttp2_Mac.a $ARCHIVE/lib/MacOS/libnghttp2.a
# archive header files
cp -r quiche/quiche-${QUICHE}/deps/boringssl/src/include/openssl/* "$ARCHIVE/include/openssl"
cp curl/include/curl/* "$ARCHIVE/include/curl"
# archive root certs
curl -s https://curl.haxx.se/ca/cacert.pem > $ARCHIVE/cacert.pem
sed -e "s/ZZZLIBCURL/$LIBCURL/g" -e "s/ZZZOPENSSL/$OPENSSL/g" -e "s/ZZZNGHTTP2/$NGHTTP2/g" archive/release-template.md > $ARCHIVE/README.md
echo
echo -e "${bold}Copying libraries to Test App ...${dim}"
echo "  See $EXAMPLE"
mkdir -p "$EXAMPLE"/{libs,include}
cp quiche/lib/libcrypto_iOS.a "$EXAMPLE/libs/libcrypto.a"
cp quiche/lib/libssl_iOS.a "$EXAMPLE/libs/libssl.a"
mkdir "$EXAMPLE/include/openssl/"
cp -r quiche/quiche-${QUICHE}/deps/boringssl/src/include/openssl/* "$EXAMPLE/include/openssl/"
cp curl/include/curl/* "$EXAMPLE/include/curl/"
cp curl/lib/libcurl_iOS.a "$EXAMPLE/libs/libcurl.a"
cp nghttp2/lib/libnghttp2_iOS.a "$EXAMPLE/libs/libnghttp2.a"
cp quiche/lib/libquiche_iOS.a "$EXAMPLE/libs/libquiche.a"
cp $ARCHIVE/cacert.pem "$EXAMPLE/cacert.pem"
echo
echo -e "${normal}Done"
