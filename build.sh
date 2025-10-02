export PJPROJECT_DIR=/Users/ngominhtoan/Desktop/MyProject/build_pjsip/pjproject
export SDK_DIR=/Users/ngominhtoan/Desktop/MyProject/build_pjsip/pjsip_sdk

./android_script.sh android-arm armeabi-v7a
./android_script.sh android-arm64 arm64-v8a
./android_script.sh android-x86 x86
./android_script.sh android-x86_64 x86_64

# Output JniLibs
JNILIBS_DEST=$SDK_DIR/android/src/main/jniLibs
JNILIBS_SRC=$PJPROJECT_DIR/pjsip-apps/src/swig/java/android/pjsua2/src/main/jniLibs
# Make directory
mkdir -p $JNILIBS_DEST/armeabi-v7a
mkdir -p $JNILIBS_DEST/arm64-v8a
mkdir -p $JNILIBS_DEST/x86
mkdir -p $JNILIBS_DEST/x86_64

# Copy lib files
cp -v $JNILIBS_SRC/armeabi-v7a/* $JNILIBS_DEST/armeabi-v7a
cp -v $JNILIBS_SRC/arm64-v8a/* $JNILIBS_DEST/arm64-v8a
cp -v $JNILIBS_SRC/x86/* $JNILIBS_DEST/x86
cp -v $JNILIBS_SRC/x86_64/* $JNILIBS_DEST/x86_64

# Output Headers
HEADERS_DEST=$SDK_DIR/android/src/main/java
HEADERS_SRC=$PJPROJECT_DIR/pjsip-apps/src/swig/java/android/pjsua2/src/main/java

# Copy files
rm -rf $HEADERS_DEST/org/pjsip/*
cp -Rv $HEADERS_SRC/* $HEADERS_DEST