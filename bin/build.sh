#!/bin/bash
#

function cacerts_gen()
{
  local DESTCERTS=$1
  local TMPCERTSDIR=$(mktemp -d)

  pushd $TMPCERTSDIR >/dev/null
  echo "fetching certificates"
  curl -sSL https://curl.haxx.se/ca/cacert.pem -o cacert.pem
  cat cacert.pem | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/{ print $0; }' > cacert-clean.pem
  rm -f cacerts cert_*
# split  -p "-----BEGIN CERTIFICATE-----" cacert-clean.pem cert_
  csplit -k -f cert_ cacert-clean.pem "/-----BEGIN CERTIFICATE-----/" {*}  >/dev/null

  count=$(ls cert_* | wc -l)
  echo "importing ${count} root certificates"
  index=0;
  for CERT_FILE in cert_*; do
    ALIAS=$(basename ${CERT_FILE})
    echo yes | keytool -import -alias ${ALIAS} -keystore cacerts -storepass 'changeit' \
        -file ${CERT_FILE} >/dev/null 2>&1 || :
    rm -f $CERT_FILE
    index=$(expr $index + 1)
    if [ $(expr $index % 10) -eq 0 ]; then
      echo "imported $index certificates"
    fi
  done

  if [ $(expr $index % 10) -ne 0 ]; then
    echo "imported $index certificates"
  fi

  if [ $index -eq 0 ]; then
    echo "no certificates imported" >&2
    exit 1
  fi
  
  rm -f cacert.pem cacert-clean.pem
  mv cacerts $DESTCERTS

  popd >/dev/null
  rm -rf $TMPCERTSDIR
}

function ensure_cacert()
{
  if [ ! -f $OBF_DROP_DIR/cacerts ]; then
    echo "no cacerts found, regenerate it..."
    cacerts_gen $OBF_DROP_DIR/cacerts
  else
    if test `find "$OBF_DROP_DIR/cacerts" -mtime +7`
    then
      echo "cacerts older than one week, regenerate it..."
      cacerts_gen $OBF_DROP_DIR/cacerts
    fi
  fi
}

function ensure_ant()
{
  if [ ! -x $OBF_DROP_DIR/ant/bin/ant ]; then
    mkdir -p $OBF_DROP_DIR/ant
    pushd $OBF_DROP_DIR/ant
    curl -L http://archive.apache.org/dist/ant/binaries/apache-ant-1.8.4-bin.tar.gz -o apache-ant-1.8.4-bin.tar.gz
    tar xzf apache-ant-1.8.4-bin.tar.gz
    mv apache-ant-1.8.4/* .
    rmdir apache-ant-1.8.4
    rm -f apache-ant-1.8.4-bin.tar.gz
    popd
  fi

  export PATH=$OBF_DROP_DIR/ant/bin:$PATH
  export ANT_HOME=$OBF_DROP_DIR/ant
}

function check_version()
{
    local version=$1 check=$2
    local winner=$(echo -e "$version\n$check" | sed '/^$/d' | sort -nr | head -1)
    [[ "$winner" = "$version" ]] && return 0
    return 1
}

function ensure_freetype()
{
  FT_VER=`freetype-config --ftversion`
  check_version "2.3" $FT_VER

  if [ $? == 0 ]; then

    if [ ! -d $OBF_DROP_DIR/freetype ]; then
      pushd $OBF_DROP_DIR
      curl -L http://freefr.dl.sourceforge.net/project/freetype/freetype2/2.4.10/freetype-2.4.10.tar.bz2 -o freetype-2.4.10.tar.bz2
      tar xjf freetype-2.4.10.tar.bz2
      cd freetype-2.4.10
      mkdir -p $OBF_DROP_DIR/freetype
      ./configure --prefix=$OBF_DROP_DIR/freetype
      make
      make install
      popd
    fi

    export OBF_FREETYPE_DIR=$OBF_DROP_DIR/freetype
    export OBF_FREETYPE_LIB_PATH=$OBF_FREETYPE_DIR/lib
    export OBF_FREETYPE_HEADERS_PATH=$OBF_FREETYPE_DIR/include

  fi
}

function fetch_source()
{

  if [ ! -d $OBF_SOURCES_PATH ]; then
    hg clone http://hg.openjdk.java.net/jdk8u/jdk8u $OBF_SOURCES_PATH
  fi

  #
  # Updating sources for Mercurial repo
  #
  pushd $OBF_SOURCES_PATH >>/dev/null
  sh ./get_source.sh
  popd >>/dev/null
}

function update_source() 
{

  pushd $OBF_SOURCES_PATH >>/dev/null

  if [ -n "$XUSE_UPDATE" ]; then
    XUSE_TAG=`hg tags | grep "jdk8u$XUSE_UPDATE" | head -1 | cut -d ' ' -f 1`
  fi

  #
  # Update sources to provided tag XUSE_TAG (if defined)
  #
  if [ ! -z "$XUSE_TAG" ]; then
    echo "using tag $XUSE_TAG"
    sh ./make/scripts/hgforest.sh update --clean $XUSE_TAG
  fi

  # OBF_MILESTONE will contains build tag number and name, ie b56 but without dash inside (suited for RPM packages)
  # OBF_BUILD_NUMBER will contains build number, ie b56
  # OBF_BUILD_DATE will contains build date, ie 20120908
  #
  # Build System concats OBF_MILESTONE, - and OBF_BUILD_DATE, ie b56-20120908
  #
  export OBF_MILESTONE=`hg identify | cut -d ' ' -f 2 | cut -d '/' -f 1`

  if [ "$OBF_MILESTONE" = "tip" ]; then
    OBF_MILESTONE=`hg tags | grep $TAG_FILTER | head -1 | cut -d ' ' -f 1`
  fi

  export OBF_BUILD_NUMBER=`echo $OBF_MILESTONE | sed "s/$TAG_FILTER//" | sed 's/^-//'`
  export OBF_BUILD_DATE=`date +%Y%m%d`
  export OBF_BASE_ARCH=`uname -m`

  echo "Calculated MILESTONE=$OBF_MILESTONE, BUILD_NUMBER=$OBF_BUILD_NUMBER"
  popd >>/dev/null
}

function clone_source()
{
  if [ "$OBF_SOURCES_PATH" != "$OBF_BUILD_PATH" ]; then
    pushd $OBF_SOURCES_PATH >>/dev/null
    mkdir $OBF_BUILD_PATH >/dev/null
    echo "cloning sources from $OBF_SOURCES_PATH to $OBF_BUILD_PATH"
    eval $(cat common/bin/hgforest.sh | grep "subrepos=")
    hg archive -t tar -p . - | tar -C ${OBF_BUILD_PATH} -xf -
    for repo in $subrepos; do
      pushd $repo >>/dev/null
      echo $repo >&2
      hg archive -t tar -p ${repo} - | tar -C ${OBF_BUILD_PATH} -xf -
      popd >>/dev/null
    done

    popd >>/dev/null

  fi
}

function patch_source() 
{
  if ! patch -s -t -p0 < patches/build-performance.patch ; then
    echo "patch failed" >&2
    exit 1
  fi
}

#
# Build using new build system
#
function build_new()
{
  echo "### using new build system ###"

  pushd $OBF_BUILD_PATH >>/dev/null

  # patch common/autoconf/version-numbers
  if [ -f common/autoconf/version-numbers ]; then
    mv common/autoconf/version-numbers common/autoconf/version-numbers.orig
    cat common/autoconf/version-numbers.orig | grep -v "MILESTONE" | grep -v "JDK_BUILD_NUMBER" | grep -v "COMPANY_NAME" > common/autoconf/version-numbers
  fi

  export JDK_BUILD_NUMBER=$OBF_BUILD_DATE
  export MILESTONE=$OBF_MILESTONE
  export COMPANY_NAME=$BUNDLE_VENDOR
  export STATIC_CXX=false

  rm -rf $OBF_WORKSPACE_PATH/.ccache
  mkdir -p $OBF_WORKSPACE_PATH/.ccache

  if [ "$XDEBUG" = "true" ]; then

      if [ "$CPU_BUILD_ARCH" = "x86_64" ]; then
        BUILD_PROFILE=linux-x86_64-normal-server-fastdebug
      elif [ "$CPU_BUILD_ARCH" = "ppc64" ]; then
        BUILD_PROFILE=linux-ppc64-normal-server-fastdebug
        EXTRA_FLAGS=$XEXTRA_FLAGS "--with-jvm-interpreter=cpp"
      else
        BUILD_PROFILE=linux-x86-normal-server-fastdebug
      fi

      rm -rf $OBF_BUILD_PATH/build/$BUILD_PROFILE
      mkdir -p $OBF_BUILD_PATH/build/$BUILD_PROFILE
      pushd $OBF_BUILD_PATH/build/$BUILD_PROFILE >>/dev/null

      bash $OBF_BUILD_PATH/common/autoconf/configure --with-boot-jdk=$OBF_BOOTDIR --with-cacerts-file=$OBF_DROP_DIR/cacerts \
              --with-freetype-include=/usr/include/freetype2/ --with-freetype-lib=/usr/lib/x86_64-linux-gnu \
              --with-target-bits=64 --with-ccache-dir=$OBF_WORKSPACE_PATH/.ccache --enable-debug \
              --with-build-number=$OBF_BUILD_DATE --with-milestone=$OBF_BUILD_NUMBER $EXTRA_FLAGS

  else

      if [ "$CPU_BUILD_ARCH" = "x86_64" ]; then
        BUILD_PROFILE=linux-x86_64-normal-server-release
      elif [ "$CPU_BUILD_ARCH" = "ppc64" ]; then
        BUILD_PROFILE=linux-ppc64-normal-server-release
        EXTRA_FLAGS=$XEXTRA_FLAGS "--with-jvm-interpreter=cpp"
      else
        BUILD_PROFILE=linux-x86-normal-server-release
      fi

      rm -rf $OBF_BUILD_PATH/build/$BUILD_PROFILE
      mkdir -p $OBF_BUILD_PATH/build/$BUILD_PROFILE
      pushd $OBF_BUILD_PATH/build/$BUILD_PROFILE >>/dev/null

      bash $OBF_BUILD_PATH/common/autoconf/configure --with-boot-jdk=$OBF_BOOTDIR --with-cacerts-file=$OBF_DROP_DIR/cacerts \
              --with-freetype-include=/usr/include/freetype2/ --with-freetype-lib=/usr/lib/x86_64-linux-gnu \
              --with-target-bits=64 --with-ccache-dir=$OBF_WORKSPACE_PATH/.ccache \
              --with-build-number=$OBF_BUILD_DATE --with-milestone=$OBF_MILESTONE $EXTRA_FLAGS

  fi

  export IMAGE_BUILD_DIR=$OBF_BUILD_PATH/build/$BUILD_PROFILE/images

  if [ "$XCLEAN" = "true" ]; then
      CONT=$BUILD_PROFILE make clean
  fi
  
  if [ "$XDEBUG_BINARIES" = "false" ]; then
      CONT=$BUILD_PROFILE make EXTRA_CFLAGS=$EXTRA_CFLAGS DEBUG_BINARIES=false images
  else
      CONT=$BUILD_PROFILE make EXTRA_CFLAGS=$EXTRA_CFLAGS DEBUG_BINARIES=true images
  fi

  popd >>/dev/null

  # restore original common/autoconf/version.numbers
  if [ -f common/autoconf/version-numbers.orig ]; then
    mv common/autoconf/version-numbers.orig common/autoconf/version-numbers
  fi

  popd >>/dev/null
}

#
# Verify build
#
function test_build()
{
  if [ -x $IMAGE_BUILD_DIR/j2sdk-image/bin/java ]; then
    $IMAGE_BUILD_DIR/j2sdk-image/bin/java -version
  else
    echo "can't find java into JDK $IMAGE_BUILD_DIR/j2sdk-image, build failed"
    exit -1
   fi

   if [ -x $IMAGE_BUILD_DIR/j2re-image/bin/java ]; then
     $IMAGE_BUILD_DIR/j2re-image/bin/java -version
   else
     echo "can't find java into JRE $IMAGE_BUILD_DIR/j2re-image, build failed"
     exit -1
    fi
}

export PATH=$JAVA_HOME/bin:$PATH
export OBF_PROJECT_NAME=openjdk8
TAG_FILTER=jdk8

#
# Safe Environment
#
export LC_ALL=C
export LANG=C

#
# Prepare Drop DIR
#
if [ -z "$OBF_DROP_DIR" ]; then
  export OBF_DROP_DIR=`pwd`/OBF_DROP_DIR
  mkdir ${OBF_DROP_DIR} >/dev/null
fi

#
# Provide Main Variables to Scripts
#
if [ -z "$OBF_SOURCES_PATH" ]; then
  export OBF_SOURCES_PATH=`pwd`/sources/$OBF_PROJECT_NAME
  mkdir -p `pwd`/sources
fi

if [ -z "$OBF_BUILD_PATH" ]; then
 export OBF_BUILD_PATH=`pwd`/build/$OBF_PROJECT_NAME
 mkdir -p `pwd`/build
fi

if [ -z "$OBF_WORKSPACE_PATH" ]; then
  export OBF_WORKSPACE_PATH=`pwd`
fi


#
# Build start here
#

CPU_BUILD_ARCH=`uname -m`

export JDK_BUNDLE_VENDOR="OBuildFactory"
export BUNDLE_VENDOR="OBuildFactory"

#
# Fetch source code
#
fetch_source
update_source
clone_source
# # patch_source

#
# Ensure cacerts are available
#
ensure_cacert

#
# Ensure Ant is available
#
# ensure_ant

#
# Ensure freetype is correct one
#
# ensure_freetype

#
# Build JDK/JRE images
#
build_new

#
# Test Build
#
test_build

