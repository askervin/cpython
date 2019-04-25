#!/bin/bash

# This is early hack for building tiny docker image that contains
# - statically linked version of python
# - pythonshare-server

cd "$(dirname $0)"

# Destination
INSTALL_ROOT=$(pwd)/static-install

# Install prefix under INSTALL_ROOT
INSTALL_PREFIX=/usr
INSTALL_DIR=$INSTALL_ROOT/$INSTALL_PREFIX

# Sources
PYTHON_DIR=$(pwd)
if [ -z "$PYTHONSHARE_DIR" ]; then
    echo "PYTHONSHARE_DIR is not defined." >&2
    echo "Usage: PYTHONSHARE_DIR=/path/to/fmbt/pythonshare $0"
    exit 1
fi
if [ ! -f "$PYTHONSHARE_DIR/pythonshare-server" ]; then
    echo "Invalid PYTHONSHARE_DIR: cannot find '$PYTHONSHARE_DIR/pythonshare-server'"
    exit 1
fi

## Build and install static Python
./configure LINKFORSHARED=" " LDFLAGS="-static -static-libgcc -Wl,--no-export-dynamic" CPPFLAGS="-static -fpic" --disable-shared --prefix "$INSTALL_DIR"
( nice make -j 16 install 2>&1 | tee make.output.txt ) || {
    echo "building and installing static Python from '$PYTHON_DIR' to '$INSTALL_DIR' failed" >&2
    exit 1
}

## Clean install directory

(
    cd "$INSTALL_DIR" || {
        echo "cannot chdir '$INSTALL_DIR', cleaning would be unsafe. stopping."
        exit 2
    }
    find . -name test -type d | xargs rm -rf
    find . -name tests -type d | xargs rm -rf
    find . -name '*.o' -o -name '*.a' | xargs rm -f
    rm -rf lib/python2.7/lib-tk
    rm -rf lib/python2.7/idlelib
    find . -name '*.py' | while read src; do
        [ -f ${src}c ] && echo "removing $src" && rm -f ${src};
        [ -f ${src}o ] && echo "removing ${src}o" && rm -f ${src}o;
    done
    rm -f lib/libpython2.7.a
    cd lib/python2.7
    zip -r ../python27.zip .
    cd ../..
    rm -rf lib/python2.7
    rm -f bin/smtpd.py
    strip bin/python2.7
)

## Build and install Pythonshare using just compiled Python

bash -c "
export PYTHONHOME=$INSTALL_DIR
export PYTHONPATH=$INSTALL_DIR/lib/python27.zip
cd \"$PYTHONSHARE_DIR\"
$INSTALL_DIR/bin/python setup.py install --prefix \"$INSTALL_DIR\"
sed -e 's:#!/usr/bin/env python2:#!$INSTALL_PREFIX/bin/python2:1' -i '$INSTALL_DIR/bin/pythonshare-server' '$INSTALL_DIR/bin/pythonshare-client'
" || {
    echo "installing pythonshare from '$PYTHONSHARE_DIR' to '$INSTALL_DIR' failed" >&2
    exit 2
}

## Create docker image

( cp "$PYTHON_DIR/Dockerfile" "$INSTALL_ROOT" && cd "$INSTALL_ROOT" && docker build -t askervin/pythonshare-server:latest . )
echo "Try it out:"
echo docker run -it -p 8089:8089 askervin/pythonshare-server:latest
