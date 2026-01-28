BUILD_OUTPUT_DIR=./output
ANDROID_OUTPUT=$(realpath "$BUILD_OUTPUT_DIR/android")
IOS_OUTPUT=$(realpath "$BUILD_OUTPUT_DIR/ios")

mkdir -p $ANDROID_OUTPUT
mkdir -p $IOS_OUTPUT

SCRIPT_DIR=$(dirname $(realpath "$0"))
cd $SCRIPT_DIR/pjproject-apple-platforms
# sh start.sh $IOS_OUTPUT

cd $SCRIPT_DIR/android-build
sh android_build.sh $ANDROID_OUTPUT