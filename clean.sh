#!/bin/bash
echo "Cleaning Build-cURL-nghttp2-nghttp3-ngtcp2"
rm -fr curl/curl-* curl/include curl/lib openssl/openssl openssl/Mac openssl/iOS openssl/tvOS \
       nghttp2/nghttp2-1* nghttp2/Mac nghttp2/iOS nghttp2/tvOS nghttp2/lib \
       nghttp3/nghttp3 nghttp3/Mac nghttp3/iOS nghttp3/tvOS nghttp3/lib \
       ngtcp2/ngtcp2 ngtcp2/Mac ngtcp2/iOS ngtcp2/tvOS ngtcp2/lib \
       /tmp/openssl-* /tmp/nghttp2-* /tmp/nghttp3-* /tmp/ngtcp2-*
