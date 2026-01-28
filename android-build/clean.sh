SCRIPT_DIR=$(dirname $(realpath "$0"))
export OPENSSL_DIR=$SCRIPT_DIR/openssl-3.4.2
export PJPROJECT_DIR=$SCRIPT_DIR/pjproject

cd $OPENSSL_DIR
make clean
rm -rf lib/*

cd $PJPROJECT_DIR
make distclean
make clean
