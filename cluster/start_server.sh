#!/bin/sh
#
# The MIT License
#
# Copyright 2018 Yahoo Japan Corporation.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# AUTHOR:   Hirotaka Wakabayashi
# CREATE:   Fri, 14 Sep 2018
# REVISION:
#

# Sets the default locale. LC_ALL has precedence over other LC* variables.
unset LANG
unset LANGUAGE
LC_ALL=en_US.utf8
export LC_ALL

# Sets PATH. setup_*.sh uses useradd command
PATH=${PATH}:/usr/sbin:/sbin

# an unset parameter expansion will fail
set -u

# umask 022 is enough
umask 022

# environments
SRCDIR=$(cd $(dirname "$0") && pwd)
DEBUG=1
if test "${DEBUG}" -eq 1; then
    TAG="$(basename $0) -s"
else
    TAG=$(basename $0)
fi
USER=$(whoami)
LOGLEVEL=info

# Starts chmpx and k2hdkc
#
start_process() {
    echo "chmpx -conf ${SRCDIR}/server.yaml -d ${LOGLEVEL} > ${SRCDIR}/chmpx.log 2>&1"
    nohup chmpx -conf ${SRCDIR}/server.yaml -d ${LOGLEVEL} > ${SRCDIR}/chmpx.log 2>&1 &
    echo "sleep 3"
    sleep 3
    echo "k2hdkc -conf ${SRCDIR}/server.yaml -d ${LOGLEVEL} > ${SRCDIR}/k2hdkc.log 2>&1"
    nohup k2hdkc -conf ${SRCDIR}/server.yaml -d ${LOGLEVEL} > ${SRCDIR}/k2hdkc.log 2>&1 &
    echo "sleep 3"
    sleep 3
    echo "chmpx -conf ${SRCDIR}/slave.yaml -d ${LOGLEVEL}  > ${SRCDIR}/slave.log 2>&1"
    nohup chmpx -conf ${SRCDIR}/slave.yaml -d ${LOGLEVEL}  > ${SRCDIR}/slave.log 2>&1 &
    echo "sleep 3"
    sleep 3
}

# Stops chmpx and k2hdkc
#
stop_process() {
    for PROC in chmpx k2hdkc; do
        echo "pgrep -u ${USER} -x ${PROC}"
        pgrep -u ${USER} -x ${PROC}
        if test "${?}" = "0"; then
            echo "pkill -9 -x ${PROC}"
            pkill -9 -x ${PROC}
        fi
    done
}

# Shows status of chmpx and k2hdkc
#
status_process() {
    RET=0
    for PROC in chmpx k2hdkc; do
        echo "pgrep -u ${USER} -x ${PROC}"
        pgrep -u ${USER} -x ${PROC}
        RET=$(echo ${?} + ${RET}|bc)
    done
    return ${RET}
}

# Starts chmpx and k2hdkc if no chmpx and k2hdkc processes are running
#
startifnotexist() {
    status_process
    if test "${RET}" = "2" ; then
        echo "start_process"
        start_process
    elif test "${RET}" = "1" ; then
        echo "stop_process"
        stop_process
        echo "start_process"
        start_process
    fi
}

# Checks if k2hdkc is installed
#
# Params::
#   no params
#
# Returns::
#   0 on installed
#   1 on not installed
#
which_k2hdkc() {
    which k2hdkc
    if test "${?}" = "0"; then
        logger -t ${TAG} -p user.info "k2hdkc already installed"
        return 0
    fi
    return 1
}

# Determines the current OS
#
# Params::
#   no params
#
# Returns::
#   0 on success
#   1 on failure
#
setup_os_env() {
    if test -f "/etc/os-release"; then
        . /etc/os-release
        OS_NAME=$ID
        OS_VERSION=$VERSION_ID
    else
        logger -t ${TAG} -p user.warn "unknown OS, no /etc/os-release and /etc/centos-release falling back to CentOS-7"
        OS_NAME=centos
        OS_VERSION=7
    fi

    if test "${OS_NAME}" = "ubuntu"; then
        logger -t ${TAG} -p user.notice "ubuntu configurations are currently equal to debian one"
        OS_NAME=debian
    elif test "${OS_NAME}" = "centos"; then
        if test "${OS_VERSION}" != "7"; then
            logger -t ${TAG} -p user.err "centos7 only currently supported, not ${OS_NAME} ${OS_VERSION}"
            exit 1
        fi
    fi

    HOSTNAME=$(hostname)
    logger -t ${TAG} -p user.debug "HOSTNAME=${HOSTNAME} OS_NAME=${OS_NAME} OS_VERSION=${OS_VERSION}"
}

# Builds k2hdkc from source code
#
# Params::
#   $1 os_name
#
# Returns::
#   0 on success
#   1 on failure(exit)
#
make_k2hdkc() {

    _os_name=${1:?"os_name should be nonzero"}

    if test "${_os_name}" = "debian" -o "${_os_name}" = "ubuntu"; then
        _configure_opt="--with-gnutls"
        sudo apt-get update -y
        sudo apt-get install -y git curl autoconf autotools-dev gcc g++ make gdb libtool pkg-config libyaml-dev libgnutls28-dev
    elif test "${_os_name}" = "fedora"; then
        _configure_opt="--with-nss"
        sudo dnf install -y git curl autoconf automake gcc gcc-c++ gdb make libtool pkgconfig libyaml-devel nss-devel
    elif test "${_os_name}" = "centos" -o "${_os_name}" = "rhel"; then
        _configure_opt="--with-nss"
        sudo yum install -y git curl autoconf automake gcc gcc-c++ gdb make libtool pkgconfig libyaml-devel nss-devel
    else
        logger -t ${TAG} -p user.error "OS should be debian, ubuntu, fedora, centos or rhel"
        exit 1
    fi

    logger -t ${TAG} -p user.debug "git clone https://github.com/yahoojapan/k2hdkc"
    git clone https://github.com/yahoojapan/k2hdkc
    cd k2hdkc

    logger -t ${TAG} -p user.debug "git clone https://github.com/yahoojapan/fullock"
    git clone https://github.com/yahoojapan/fullock
    logger -t ${TAG} -p user.debug "git clone https://github.com/yahoojapan/k2hash"
    git clone https://github.com/yahoojapan/k2hash
    logger -t ${TAG} -p user.debug "git clone https://github.com/yahoojapan/chmpx"
    git clone https://github.com/yahoojapan/chmpx

    if ! test -d "fullock"; then
        echo "no fullock"
        exit 1
    fi
    cd fullock
    ./autogen.sh
    ./configure --prefix=/usr
    make
    sudo make install

    if ! test -d "../k2hash"; then
        echo "no k2hash"
        exit 1
    fi
    cd ../k2hash
    ./autogen.sh
    ./configure --prefix=/usr ${_configure_opt}
    make
    sudo make install

    if ! test -d "../chmpx"; then
        echo "no chmpx"
        exit 1
    fi
    cd ../chmpx
    ./autogen.sh
    ./configure --prefix=/usr ${_configure_opt}
    make
    sudo make install

    cd ..
    ./autogen.sh
    ./configure --prefix=/usr ${_configure_opt}
    make
    sudo make install

    which k2hdkc
    if test "${?}" != "0"; then
        logger -t ${TAG} -p user.error "no k2hdkc installed"
        exit 1
    fi
    return 0
}

#
# main loop
#

setup_os_env

which_k2hdkc
if test "${?}" = "0"; then
    startifnotexist
    exit 0
fi

if test "${OS_NAME}" = "fedora"; then
    which java
    if test "${?}" = "1"; then
        sudo dnf install -y java-1.8.0-openjdk
    fi
    which mvn
    if test "${?}" = "1"; then
        sudo dnf install -y maven
    fi
    which bc
    if test "${?}" = "1"; then
        sudo dnf install -y bc
    fi
    if test "${OS_VERSION}" = "28"; then
        sudo dnf install -y curl
        curl -s https://packagecloud.io/install/repositories/antpickax/stable/script.rpm.sh | sudo bash
        sudo dnf install  k2hdkc-devel -y
    elif test "${OS_VERSION}" = "29"; then
        sudo dnf install -y curl
        curl -s https://packagecloud.io/install/repositories/antpickax/current/script.rpm.sh | sudo bash
        sudo dnf install  k2hdkc-devel -y
    else
        make_k2hdkc ${OS_NAME}
    fi
elif test "${OS_NAME}" = "debian" -o "${OS_NAME}" = "ubuntu"; then
    which java
    if test "${?}" = "1"; then
        sudo apt-get install -y openjdk-8-jdk
    fi
    which mvn
    if test "${?}" = "1"; then
        sudo apt-get install -y maven
    fi
    which bc
    if test "${?}" = "1"; then
        sudo apt-get install -y bc
    fi
    if test "${OS_VERSION}" = "9"; then
        sudo apt-get install -y curl
        curl -s https://packagecloud.io/install/repositories/antpickax/stable/script.deb.sh | sudo bash
        sudo apt-get install -y k2hdkc-dev
    else
        make_k2hdkc ${OS_NAME}
    fi
elif test "${OS_NAME}" = "centos" -o "${OS_NAME}" = "rhel"; then
    which java
    if test "${?}" = "1"; then
    sudo yum install -y java-1.8.0-openjdk
    fi
    which mvn
    if test "${?}" = "1"; then
        sudo yum install -y maven
    fi
    which bc
    if test "${?}" = "1"; then
        sudo yum install -y bc
    fi
    sudo yum install -y k2hdkc-devel
    if test "${?}" != "0"; then
        sudo yum install -y curl
        curl -s https://packagecloud.io/install/repositories/antpickax/stable/script.rpm.sh | sudo bash
        sudo yum install -y k2hdkc-devel
        if test "${?}" != "0"; then
            make_k2hdkc ${OS_NAME}
        fi
    fi
else
    logger -t ${TAG} -p user.error "OS must be either fedora or centos or debian or ubuntu, not ${OS_NAME}"
    exit 1
fi

which_k2hdkc
if test "${?}" = "0"; then
    startifnotexist
    exit 0
fi

exit 0

#
# Local variables:
# tab-width: 4
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim600: noexpandtab sw=4 ts=4 fdm=marker
# vim<600: noexpandtab sw=4 ts=4
#
