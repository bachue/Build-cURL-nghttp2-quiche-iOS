#!/bin/bash
echo "Cleaning Build-cURL-nghttp2-quiche"
rm -fr curl/curl-* curl/include curl/lib \
       nghttp2/nghttp2-1* nghttp2/Mac nghttp2/iOS nghttp2/lib \
       quiche/quiche-0.* quiche/Mac quiche/iOS quiche/lib \
       /tmp/nghttp2-* /tmp/quiche-* /tmp/curl-*
