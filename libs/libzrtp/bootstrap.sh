#!/bin/sh

reconf () {
  aclocal
  mkdir -p config
  libtoolize --copy --automake
  autoconf
  autoheader
  automake --no-force --add-missing --copy
}

(cd third_party/bnlib && sh ./bootstrap.sh)
reconf

