#!/bin/bash

#check that a directory exists
check_directory_exists()
{
    local dir=$1
    local errormsg=$2

    if [ "" == "$dir" ]; then
        echo "$errormsg"
        exit 1
    fi

    if [ -d "$dir" ]; then
        echo "Verified that $dir exists."
    else
        echo "$errormsg"
        exit 1
    fi
}

#check for an executable
check_exe()
{
    if which $1 >/dev/null 2>&1; then
        echo $1 detected.
    else
        echo $1 not detected!  Install $1.
        exit 1
    fi
}

#download a file if it doesn't exist
download_if_missing()
{
    local url=$1
    local base="${url##*/}"

    if [ ! -f $base ]; then
        echo Downloading $base from $url.
        curl -# -L -O $url
    else
        echo $base already downloaded.
    fi
}

#get the given public key from the given server if missing
get_pubkey_if_missing()
{
    if gpg -k $1 > /dev/null 2>&1; then
        echo Public Key $1 found.
    else
        echo Fetching public key $1 from $2.
        if gpg --keyserver $2 --recv-keys $1; then
            echo "    Success."
        else
            echo "    Failure."
            exit 1
        fi
    fi
}

#verify the PGP signature of a given file
verify_signature()
{
    if gpg --quiet --verify $1 $2; then
        echo $2 verified.
    else
        echo "**** BAD SIGNATURE FOR $2.  ABORTING  ****"
        exit 1
    fi
}

#verify the MD5 checksum of a given file.  Ugly hack.  Why do people still use
#MD5???
verify_md5_ugly()
{
    local dgst=`openssl dgst -md5 -hex $2 | awk '{print $2}'`
    if [ "$1" == "$dgst" ]; then
        echo "$2 matches MD5 digest $1, for whatever that's worth."
    else
        echo "**** $2 DOES NOT MATCH MD5 DIGEST $1.  ABORTING  ****"
        exit 1
    fi
}

#verify the SHA512 checksum of a given file.
verify_sha512()
{
    local dgst=`openssl dgst -sha512 -hex $2 | awk '{print $2}'`
    if [ "$1" == "$dgst" ]; then
        echo "$2 matches SHA-512 digest $1."
    else
        echo $dgst
        echo "**** $2 DOES NOT MATCH SHA-512 DIGEST $1.  ABORTING  ****"
        exit 1
    fi
}

#extract a given file just once
extract_once()
{
    local tag=.${1}_extracted
    local args=x${2}f
    local archive=$3
    if [ ! -f $tag ]; then
        echo "Extracting $archive..."
        if tar $args $archive; then
            touch $tag
            echo "$archive extracted."
        else
            echo "Failure extracting $archive."
            exit 1
        fi
    else
        echo "$archive already extracted."
    fi
}

#configure a given workspace just once
configure_once()
{
    local tag=.${1}_configured
    local workspace=$2
    local opts=$3
    local builddir=$4
    if [ ! -f $tag ]; then
        echo "Configuring $workspace..."

        #enter directory
        if [ "" != "$builddir" ]; then
            mkdir -p $workspace/$builddir
            pushd $workspace/$builddir
            local configcmd=../configure
        else
            pushd $workspace
            local configcmd=./configure
        fi

        if $configcmd --prefix=$ARM_TOOLCHAIN_DIR $opts; then
            #restore directory
            popd
            touch $tag
            echo "Configure succeeded."
        else
            echo "Failure configuring $workspace."
            exit 1
        fi
    else
        echo "$workspace already configured."
    fi
}

#build a given workspace just once
build_once()
{
    local tag=.${1}_built
    local workspace=$2
    local builddir=$3
    local buildtarget=$4
    if [ ! -f $tag ]; then
        echo "Building $workspace..."

        #enter directory
        if [ "" != "$builddir" ]; then
            pushd $workspace/$builddir
        else
            pushd $workspace
        fi

        if make $MAKE_OPTS $buildtarget; then
            #restore directory
            popd
            touch $tag
            echo "Build succeeded."
        else
            echo "Failure building $workspace."
            exit 1
        fi
    else
        echo "$workspace already built."
    fi
}

#test a given workspace just once
test_once()
{
    local tag=.${1}_tested
    local workspace=$2
    local testcmd=$3
    local builddir=$4
    if [ ! -f $tag ]; then
        echo "Testing $workspace..."

        #enter directory
        if [ "" != "$builddir" ]; then
            pushd $workspace/$builddir
        else
            pushd $workspace
        fi

        if make $MAKE_OPTS $testcmd; then
            #restore directory
            popd
            touch $tag
            echo "Test succeeded."
        else
            echo "Failure testing $workspace."
            exit 1
        fi
    else
        echo "$workspace already tested."
    fi
}

#install a given workspace just once
install_once()
{
    local tag=.${1}_installed
    local workspace=$2
    local builddir=$3
    local installtarget=$4
    if [ ! -f $tag ]; then
        echo "Installing $workspace..."

        #enter directory
        if [ "" != "$builddir" ]; then
            pushd $workspace/$builddir
        else
            pushd $workspace
        fi

        #set the install target
        if [ "" == "$installtarget" ]; then
            local installtarget=install
        fi

        if make $installtarget; then
            #restore directory
            popd
            touch $tag
            echo "Install succeeded."
        else
            echo "Failure installing $workspace."
            exit 1
        fi
    else
        echo "$workspace already installed."
    fi
}

#check that the environment variables we need have been set
check_directory_exists "$ARM_TOOLCHAIN_DIR" "Please set ARM_TOOLCHAIN_DIR to a valid destination directory."

#override paths to use ARM_TOOLCHAIN_DIR
export DYLD_LIBRARY_PATH=$ARM_TOOLCHAIN_DIR/lib:$DYLD_LIBRARY_PATH
export LD_LIBRARY_PATH=$ARM_TOOLCHAIN_DIR/lib:$LD_LIBRARY_PATH
export PATH=$ARM_TOOLCHAIN_DIR/bin:$PATH

#set the ARM cpu to cortex-m4 by default
ARM_CPU="${ARM_CPU:-cortex-m4}"

#check that we have the executables we need to run this script.
check_exe git
check_exe gcc
check_exe g++
check_exe curl
check_exe openssl
check_exe gpg
check_exe gzip
check_exe bzip2
check_exe xz
check_exe sed
check_exe libtool

GMP_VERSION=gmp-6.1.2
MPFR_VERSION=mpfr-4.0.0
MPC_VERSION=mpc-1.1.0
BINUTILS_VERSION=binutils-2.29.1
GCC_VERSION=gcc-7.2.0
NEWLIB_VERSION=newlib-2.5.0.20171222
GDB_VERSION=gdb-8.0.1

#get GMP
get_pubkey_if_missing 28C67298 pgp.mit.edu
download_if_missing https://gmplib.org/download/gmp/${GMP_VERSION}.tar.xz.sig
download_if_missing https://gmplib.org/download/gmp/${GMP_VERSION}.tar.xz
verify_signature ${GMP_VERSION}.tar.xz.sig ${GMP_VERSION}.tar.xz

#get MPFR
get_pubkey_if_missing 980C197698C3739D pgp.mit.edu
download_if_missing http://www.mpfr.org/mpfr-current/${MPFR_VERSION}.tar.xz.asc
download_if_missing http://www.mpfr.org/mpfr-current/${MPFR_VERSION}.tar.xz
verify_signature ${MPFR_VERSION}.tar.xz.asc ${MPFR_VERSION}.tar.xz

#get MPC
get_pubkey_if_missing F7D5C9BF765C61E3 pgp.mit.edu
download_if_missing ftp://ftp.gnu.org/gnu/mpc/${MPC_VERSION}.tar.gz.sig
download_if_missing ftp://ftp.gnu.org/gnu/mpc/${MPC_VERSION}.tar.gz
verify_signature ${MPC_VERSION}.tar.gz.sig ${MPC_VERSION}.tar.gz

#get binutils
get_pubkey_if_missing 4AE55E93 pgp.mit.edu
download_if_missing https://ftp.gnu.org/gnu/binutils/${BINUTILS_VERSION}.tar.gz.sig
download_if_missing https://ftp.gnu.org/gnu/binutils/${BINUTILS_VERSION}.tar.gz
verify_signature ${BINUTILS_VERSION}.tar.gz.sig ${BINUTILS_VERSION}.tar.gz

#get gcc
get_pubkey_if_missing FC26A641 pgp.mit.edu
get_pubkey_if_missing C3C45C06 pgp.mit.edu
download_if_missing https://ftp.gnu.org/gnu/gcc/${GCC_VERSION}/${GCC_VERSION}.tar.xz.sig
download_if_missing https://ftp.gnu.org/gnu/gcc/${GCC_VERSION}/${GCC_VERSION}.tar.xz
verify_signature ${GCC_VERSION}.tar.xz.sig ${GCC_VERSION}.tar.xz

#get newlib
download_if_missing ftp://sourceware.org/pub/newlib/${NEWLIB_VERSION}.tar.gz
verify_sha512 753a948b96611a75c709e477991117510975a9274f4e6f13f9092b229cae3da48a4a08d339745c00f54fa28584eb471d704f87c997faa9b852771d7bd2cd7f9d ${NEWLIB_VERSION}.tar.gz

#get gdb
get_pubkey_if_missing FF325CF3 pgp.mit.edu
download_if_missing https://ftp.gnu.org/gnu/gdb/${GDB_VERSION}.tar.xz.sig
download_if_missing https://ftp.gnu.org/gnu/gdb/${GDB_VERSION}.tar.xz
verify_signature ${GDB_VERSION}.tar.xz.sig ${GDB_VERSION}.tar.xz

#extract and build GMP
extract_once gmp J ${GMP_VERSION}.tar.xz
configure_once gmp `pwd`/${GMP_VERSION}
build_once gmp `pwd`/${GMP_VERSION}
test_once gmp `pwd`/${GMP_VERSION} check
install_once gmp `pwd`/${GMP_VERSION}

#extract and build MPFR
extract_once mpfr J ${MPFR_VERSION}.tar.xz
configure_once mpfr `pwd`/${MPFR_VERSION} "--with-gmp=$ARM_TOOLCHAIN_DIR --disable-shared --enable-static"
build_once mpfr `pwd`/${MPFR_VERSION}
test_once mpfr `pwd`/${MPFR_VERSION} check
install_once mpfr `pwd`/${MPFR_VERSION}

#extract and build MPC
extract_once mpc z ${MPC_VERSION}.tar.gz
configure_once mpc `pwd`/${MPC_VERSION} "--with-gmp=$ARM_TOOLCHAIN_DIR --with-mpfr=$ARM_TOOLCHAIN_DIR --disable-shared --enable-static"
build_once mpc `pwd`/${MPC_VERSION}
test_once mpc `pwd`/${MPC_VERSION} check
install_once mpc `pwd`/${MPC_VERSION}

#extract and build binutils
extract_once binutils z ${BINUTILS_VERSION}.tar.gz
configure_once binutils `pwd`/${BINUTILS_VERSION} "--target=arm-none-eabi --with-cpu=${ARM_CPU} --with-mode=thumb --enable-interwork --with-float=soft --disable-multilib --disable-nls"
build_once binutils `pwd`/${BINUTILS_VERSION}
test_once binutils `pwd`/${BINUTILS_VERSION} check
install_once binutils `pwd`/${BINUTILS_VERSION}

#extract and build gcc (bootstrap)
extract_once gcc J ${GCC_VERSION}.tar.xz
configure_once gcc_bootstrap `pwd`/${GCC_VERSION} "--target=arm-none-eabi --with-cpu=${ARM_CPU} --with-float=soft --with-mode=thumb --enable-interwork --disable-multilib --with-system-zlib --with-newlib --without-headers --disable-shared --disable-nls --with-gnu-as --with-gnu-ld --with-gmp=$ARM_TOOLCHAIN_DIR --with-mpfr=$ARM_TOOLCHAIN_DIR --with-mpc=$ARM_TOOLCHAIN_DIR --enable-languages=c" bootstrap
build_once gcc_bootstrap `pwd`/${GCC_VERSION} bootstrap all-gcc
install_once gcc_bootstrap `pwd`/${GCC_VERSION} bootstrap install-gcc

#extract and build newlib
extract_once newlib z ${NEWLIB_VERSION}.tar.gz
configure_once newlib `pwd`/${NEWLIB_VERSION} "--target=arm-none-eabi --with-cpu=${ARM_CPU} --with-float=soft --enable-soft-float --with-mode=thumb --enable-interwork --disable-multilib --with-gnu-as --with-gnu-ld --disable-nls --disable-newlib-supplied-syscalls --enable-newlib-reent-small --disable-newlib-fvwrite-in-streamio --disable-newlib-fseek-optimization --disable-newlib-wide-orient --enable-newlib-nano-malloc --disable-newlib-unbuf-stream-opt --enable-lite-exit --enable-newlib-global-atexit"
build_once newlib `pwd`/${NEWLIB_VERSION}
install_once newlib `pwd`/${NEWLIB_VERSION}

#build full GCC C/C++
extract_once gcc J ${GCC_VERSION}.tar.xz
configure_once gcc_full `pwd`/${GCC_VERSION} "--target=arm-none-eabi --with-cpu=${ARM_CPU} --with-float=soft --with-mode=thumb --enable-interwork --disable-multilib --with-system-zlib --with-newlib --without-headers --disable-shared --disable-nls --with-gnu-as --with-gnu-ld --with-gmp=$ARM_TOOLCHAIN_DIR --with-mpfr=$ARM_TOOLCHAIN_DIR --with-mpc=$ARM_TOOLCHAIN_DIR --enable-languages=c,c++" full
build_once gcc_full `pwd`/${GCC_VERSION} full all
install_once gcc_full `pwd`/${GCC_VERSION} full install

#extract and build gdb
extract_once gdb J ${GDB_VERSION}.tar.xz
configure_once gdb `pwd`/${GDB_VERSION} "--target=arm-none-eabi -disable-intl"
build_once gdb `pwd`/${GDB_VERSION}
install_once gdb `pwd`/${GDB_VERSION}
