export OPENSSL_DIR=/Users/ngominhtoan/Desktop/MyProject/build_pjsip/openssl-3.4.2
export PJPROJECT_DIR=/Users/ngominhtoan/Desktop/MyProject/build_pjsip/pjproject

cd $OPENSSL_DIR
make clean
rm -rf lib/*

cd $PJPROJECT_DIR
make distclean
make clean
