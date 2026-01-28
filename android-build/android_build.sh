# tutorial: https://docs.pjsip.org/en/latest/get-started/android/requirements.html
SCRIPT_DIR=$(dirname $(realpath "$0"))
export PJPROJECT_DIR=$SCRIPT_DIR/pjproject
export OUTPUT_DIR=$(realpath "$1")
export OBOE_DIR=$SCRIPT_DIR/oboe-1.9.3
export OPENSSL_DIR=$SCRIPT_DIR/openssl-3.4.2
export ANDROID_NDK_ROOT=/Users/ngominhtoan/Library/Android/sdk/ndk/28.2.13676358
export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home
PATH=$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/darwin-x86_64/bin:$PATH

cd $SCRIPT_DIR
PJPROJECT_VERSION=2.16

if [ -d pjproject ]
then
    pushd pjproject
    git reset --hard "${PJPROJECT_VERSION}"
    popd
else
    git -c advice.detachedHead=false clone --depth 1 --branch "${PJPROJECT_VERSION}" https://github.com/pjsip/pjproject # > /dev/null 2>&1
fi

pushd pjproject
cat << EOF > pjlib/include/pj/config_site.h
#define PJ_CONFIG_ANDROID 1
#define PJMEDIA_HAS_VIDEO 1
#include <pj/config_site_sample.h>
EOF
popd


# Output JniLibs
JNILIBS_DEST=$OUTPUT_DIR/src/main/jniLibs
JNILIBS_SRC=$PJPROJECT_DIR/pjsip-apps/src/swig/java/android/pjsua2/src/main/jniLibs

# export NDK_TOOLCHAIN_VERSION=4.9
export ANDROID_TARGET=35

$SCRIPT_DIR/android_script.sh android-arm armeabi-v7a
mkdir -p $JNILIBS_DEST/armeabi-v7a
cp -v $JNILIBS_SRC/armeabi-v7a/* $JNILIBS_DEST/armeabi-v7a

$SCRIPT_DIR/android_script.sh android-arm64 arm64-v8a
mkdir -p $JNILIBS_DEST/arm64-v8a
cp -v $JNILIBS_SRC/arm64-v8a/* $JNILIBS_DEST/arm64-v8a

$SCRIPT_DIR/android_script.sh android-x86 x86
mkdir -p $JNILIBS_DEST/x86
cp -v $JNILIBS_SRC/x86/* $JNILIBS_DEST/x86

$SCRIPT_DIR/android_script.sh android-x86_64 x86_64
mkdir -p $JNILIBS_DEST/x86_64
cp -v $JNILIBS_SRC/x86_64/* $JNILIBS_DEST/x86_64

# Output Headers
HEADERS_DEST=$OUTPUT_DIR/src/main/java
mkdir -p $HEADERS_DEST
HEADERS_SRC=$PJPROJECT_DIR/pjsip-apps/src/swig/java/android/pjsua2/src/main/java

# Copy files
rm -rf $HEADERS_DEST/*
cp -Rv $HEADERS_SRC/* $HEADERS_DEST