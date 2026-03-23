# Tránh lỗi
PKG_CONFIG_PATH=
LDFLAGS=
CPPFLAGS=
CFLAGS=
CXXFLAGS=
PKG_CONFIG_LIBDIR=/dev/null

# output
BUILD_OUTPUT_DIR=./output
mkdir -p $BUILD_OUTPUT_DIR/android
mkdir -p $BUILD_OUTPUT_DIR/ios

ANDROID_OUTPUT=$(realpath "$BUILD_OUTPUT_DIR/android")
IOS_OUTPUT=$(realpath "$BUILD_OUTPUT_DIR/ios")

SCRIPT_DIR=$(dirname $(realpath "$0"))
cd $SCRIPT_DIR/pjproject-apple-platforms
# sh start.sh $IOS_OUTPUT

cd $SCRIPT_DIR/android-build
sh android_build.sh $ANDROID_OUTPUT