#!/bin/bash

if test "X$1" = Xinstall ; then
  sudo apt-get install git cmake make gcc-arm-none-eabi qemu-system-arm g++
  if grep -q trixie /etc/os-release || grep -q forky /etc/os-release ; then # Debian 13 or 14
    sudo apt-get install picolibc-arm-none-eabi picolibc-aarch64-linux-gnu libstdc++-arm-none-eabi-picolibc
    sudo apt-get install clang-19
  fi
  exit 0
fi

if test "X$1" = Xupload ; then
  rsync -av --delete . debian-14:data/FreeRTOS/
  exit 0
fi

# Checkout the source the first time:
if ! test -d FreeRTOS ; then
  git clone https://github.com/FreeRTOS/FreeRTOS
  #git clone --depth 1 https://github.com/FreeRTOS/FreeRTOS
  pushd FreeRTOS
    git config pull.rebase false
    patch -s -p1 < ../FreeRTOS.patch
    echo output > FreeRTOS/Demo/CORTEX_MPS2_QEMU_IAR_GCC/build/gcc/.gitignore
    #git submodule update --init --recursive
    #git submodule update --checkout --init --depth 1 FreeRTOS/Source 
    git submodule update --checkout --init FreeRTOS/Source
    git submodule update --checkout --init FreeRTOS-Plus/Source/FreeRTOS-Plus-TCP
    git submodule update --checkout --init FreeRTOS-Plus/Source/FreeRTOS-Plus-Trace
    git submodule update --remote
    pushd FreeRTOS/Source
      git config pull.rebase false
      patch -s -p1 < ../../../FreeRTOS-Kernel.patch
    popd
    pushd FreeRTOS-Plus/Source/FreeRTOS-Plus-TCP
      git config pull.rebase false
      patch -s -p1 < ../../../../FreeRTOS-TCP.patch
    popd
    pushd FreeRTOS-Plus/Source/FreeRTOS-Plus-Trace
      git config pull.rebase false
      patch -s -p1 < ../../../../FreeRTOS-Trace.patch
    popd
  popd
fi

# Create new patch file after editing further files:
if test "X$1" = Xpatch ; then
  pushd FreeRTOS
    git diff --ignore-submodules=dirty > ../FreeRTOS.patch2
    pushd FreeRTOS/Source
      git diff > ../../../FreeRTOS-Kernel.patch2
    popd
    pushd FreeRTOS-Plus/Source/FreeRTOS-Plus-TCP
      git diff > ../../../../FreeRTOS-TCP.patch2
    popd
    pushd FreeRTOS-Plus/Source/FreeRTOS-Plus-Trace
      git diff > ../../../../FreeRTOS-Trace.patch2
    popd
  popd
  diff -u FreeRTOS.patch FreeRTOS.patch2
  diff -u FreeRTOS-Kernel.patch FreeRTOS-Kernel.patch2
  diff -u FreeRTOS-TCP.patch FreeRTOS-TCP.patch2
  diff -u FreeRTOS-Trace.patch FreeRTOS-Trace.patch2
  mv FreeRTOS.patch2 FreeRTOS.patch
  mv FreeRTOS-Kernel.patch2 FreeRTOS-Kernel.patch
  mv FreeRTOS-TCP.patch2 FreeRTOS-TCP.patch
  mv FreeRTOS-Trace.patch2 FreeRTOS-Trace.patch
  exit 0
fi

# Update the source:
if test "X$1" = Xupdate ; then
  pushd FreeRTOS
    git stash
    pushd FreeRTOS/Source
      git stash
    popd
    pushd FreeRTOS-Plus/Source/FreeRTOS-Plus-TCP
      git stash
    popd
    pushd FreeRTOS-Plus/Source/FreeRTOS-Plus-Trace
      git stash
    popd
    git pull -a --all
    git stash pop
    git submodule update --remote
    pushd FreeRTOS/Source
      git stash pop
    popd
    pushd FreeRTOS-Plus/Source/FreeRTOS-Plus-TCP
      git stash pop
    popd
    pushd FreeRTOS-Plus/Source/FreeRTOS-Plus-Trace
      git stash pop
    popd
    #pushd FreeRTOS/Source
    #  git stash
    #  git pull -a --all
    #  git stash pop
    #popd
  popd
  exit 0
fi

if test "X$1" != X ; then
PLATFORM="$1"
else
#PLATFORM=posix
#PLATFORM=mps2a
#PLATFORM=mps2b
PLATFORM=mps2net
fi

if test -z "$PICOLIBC"; then
  export PICOLIBC=0
fi

if test $PLATFORM = posix ; then
  if test "X$USE_CLANG" = X1 ; then
    if grep -q 22.04 /etc/os-release ; then
      export CC=clang-15
      export CXX=clang++-15
      SB="scan-build-15 --use-cc=$CC --use-c++=$CXX"
    else
      export CC=clang-19
      export CXX=clang++-19
      SB="scan-build-19 --use-cc=$CC --use-c++=$CXX"
    fi
    SBM="$SB --status-bugs"
  fi
  # Für stabile Tests den cpu scaling_governor auf performance setzen:
  rm -fr FreeRTOS/FreeRTOS/Demo/Posix_GCC/build
  mkdir -p FreeRTOS/FreeRTOS/Demo/Posix_GCC/build
  pushd FreeRTOS/FreeRTOS/Demo/Posix_GCC/build
    $SB cmake .. -DNO_TRACING=1 # -DPROFILE=1 # -DSANITIZE_ADDRESS=1 -DSANITIZE_LEAK=1
    #make clean
    $SBM make # --trace
    ./posix_demo
  popd
elif test $PLATFORM = mps2a ; then
  pushd FreeRTOS/FreeRTOS/Demo/CORTEX_MPS2_QEMU_IAR_GCC/build/gcc
    make clean
    make
    #arm-none-eabi-objdump -d output/RTOSDemo.out > output/RTOSDemo.lst
    echo "Running qemu now... Press Ctrl-C to end:"
    qemu-system-arm -machine mps2-an385 -cpu cortex-m3 -kernel output/RTOSDemo.out -monitor none -nographic -serial stdio # -s -S
  popd
elif test $PLATFORM = mps2b ; then
  pushd FreeRTOS/FreeRTOS/Demo/CORTEX_MPU_M3_MPS2_QEMU_GCC
    make clean
    make
    #arm-none-eabi-objdump -d build/RTOSDemo.axf > output/RTOSDemo.lst
    echo "Running qemu now... Press Ctrl-C to end:"
    qemu-system-arm -machine mps2-an385 -monitor null -semihosting --semihosting-config enable=on,target=native -kernel build/RTOSDemo.axf -serial stdio -nographic # -s -S
  popd
elif test $PLATFORM = mps2net ; then
  pushd FreeRTOS/FreeRTOS-Plus/Demo/FreeRTOS_Plus_TCP_Echo_Qemu_mps2
    make clean
    make
    #arm-none-eabi-objdump -d build/RTOSDemo.axf > output/RTOSDemo.lst
    echo "Running qemu now... Press Ctrl-C to end:"
    qemu-system-arm -machine mps2-an385 -monitor null -semihosting --semihosting-config enable=on,target=native -kernel build/freertos_tcp_mps2_demo.axf -serial stdio -nographic # -s -S
  popd
fi
