
# arch: android-arm, android-arm64, android-x86, android-x86_64
# ARCH=android-arm64
ARCH=$1

# abi: armeabi-v7a, arm64-v8a, x86, x86_64
# export TARGET_ABI=arm64-v8a
export TARGET_ABI=$2

cd $OPENSSL_DIR
if [ "$ARCH" = "android-arm" ]; then
    # no-asm with armeabi-v7a
    echo "Building for $ARCH (disable asm)..."
    ./Configure $ARCH -D__ANDROID_API__=$ANDROID_TARGET no-asm
else
    echo "Building for $ARCH..."
    ./Configure $ARCH -D__ANDROID_API__=$ANDROID_TARGET
fi
make clean && make

mkdir -p lib
rm -rf lib/*
cp -f lib*.so lib/
cp -f lib*.a lib/
ls lib


# tutorial: https://docs.pjsip.org/en/latest/get-started/android/build_instructions.html#create-config-site-h
# Create pjlib/include/pj/config_site.h file
cd $PJPROJECT_DIR

make distclean
./configure-android -with-ssl=$OPENSSL_DIR --with-oboe=$OBOE_DIR
make dep && make clean && make

SAMPLE_PROJECT_DIR=$PJPROJECT_DIR/pjsip-apps/src/swig/java/android
rm -rf $SAMPLE_PROJECT_DIR/pjsua2/src/main/jniLibs/$TARGET_ABI/*
cd $PJPROJECT_DIR/pjsip-apps/src/swig
make clean && make

cp -v $OPENSSL_DIR/lib/*.so $SAMPLE_PROJECT_DIR/pjsua2/src/main/jniLibs/$TARGET_ABI
cp -v $OBOE_DIR/prefab/modules/oboe/libs/android.$TARGET_ABI/*.so $SAMPLE_PROJECT_DIR/pjsua2/src/main/jniLibs/$TARGET_ABI
ls $SAMPLE_PROJECT_DIR/pjsua2/src/main/jniLibs/$TARGET_ABI