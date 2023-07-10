#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# MuseScore-CLA-applies
#
# MuseScore
# Music Composition & Notation
#
# Copyright (C) 2023 MuseScore BVBA and others
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# For maximum AppImage compatibility, build on the oldest Linux distribution
# that still receives security updates from its manufacturer.

echo "Setup Linux build environment"
trap 'echo Setup failed; exit 1' ERR

df -h .

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --arch) PACKARCH="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

BUILD_TOOLS=$HOME/build_tools
ENV_FILE=$BUILD_TOOLS/environment.sh

mkdir -p $BUILD_TOOLS

# Let's remove the file with environment variables to recreate it
rm -f $ENV_FILE

echo "echo 'Setup MuseScore build environment'" >> $ENV_FILE

##########################################################################
# GET DEPENDENCIES
##########################################################################

# DISTRIBUTION PACKAGES

sed -i "s/^deb/deb [arch=amd64,i386]/g" /etc/apt/sources.list
echo "deb [arch=arm64,armhf] http://ports.ubuntu.com/ bionic main universe multiverse restricted" | tee -a /etc/apt/sources.list
echo "deb [arch=arm64,armhf] http://ports.ubuntu.com/ bionic-security main universe multiverse restricted" | tee -a /etc/apt/sources.list
echo "deb [arch=arm64,armhf] http://ports.ubuntu.com/ bionic-updates main universe multiverse restricted" | tee -a /etc/apt/sources.list
if [ "$PACKARCH" == "armv7l" ]; then
  dpkg --add-architecture armhf
else
  dpkg --add-architecture arm64
fi

apt_packages=(
  curl
  cimg-dev
  desktop-file-utils
  file
  fuse
  git
  gpg
  libtool
  patchelf
  pkg-config
  software-properties-common # installs `add-apt-repository`
  argagg-dev
  unzip
  wget
  xxd
  p7zip-full
  make
  desktop-file-utils # installs `desktop-file-validate` for appimagetool
  zsync # installs `zsyncmake` for appimagetool
  )

apt_packages_dev=(
  libboost-dev
  libboost-filesystem-dev
  libboost-regex-dev
  libcairo2-dev
  libfuse-dev
  libtool
  libssl-dev
  libasound2-dev 
  libfontconfig1-dev
  libfreetype6-dev
  libfreetype6
  libgl1-mesa-dev
  libjack-dev
  libnss3-dev
  libportmidi-dev
  libpulse-dev
  libsndfile1-dev
  zlib1g-dev
  libglib2.0-dev
  librsvg2-dev
  libgcrypt20-dev
  libcurl4-openssl-dev
  libgpg-error-dev
  libegl1-mesa-dev
  libgles2-mesa-dev
  libpq-dev
  libxcomposite-dev
  libxcursor-dev
  libxtst-dev
  libdrm-dev
  libxi-dev
  libjpeg-dev
  )

# MuseScore compiles without these but won't run without them
apt_packages_runtime=(
  libcups2
  libdbus-1-3
  libodbc1
  libxkbcommon-x11-0
  libxrandr2
  libxcb-icccm4
  libxcb-image0
  libxcb-keysyms1
  libxcb-randr0
  libxcb-render-util0
  libxcb-xinerama0
  )

apt_packages_ffmpeg=(
  ffmpeg
  libavcodec-dev
  libavformat-dev 
  libswscale-dev
  )

apt-get update # no package lists in Docker image
if [ "$PACKARCH" == "armv7l" ]; then
  DEBIAN_FRONTEND="noninteractive" TZ="Europe/London" apt-get install -y --no-install-recommends \
    "${apt_packages[@]}" "${apt_packages_dev[@]/%/:armhf}" \
    "${apt_packages_runtime[@]}" \
    "${apt_packages_ffmpeg[@]/%/:armhf}"
else
  DEBIAN_FRONTEND="noninteractive" TZ="Europe/London" apt-get install -y --no-install-recommends \
    "${apt_packages[@]}" "${apt_packages_dev[@]/%/:arm64}" \
    "${apt_packages_runtime[@]}" \
    "${apt_packages_ffmpeg[@]/%/:arm64}"
fi

# Add additional ppa (Qt 5.15.2 and CMake)
wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ bionic main' | tee /etc/apt/sources.list.d/kitware.list >/dev/null
add-apt-repository --yes ppa:theofficialgman/opt-qt-5.15.2-bionic-arm
apt-get update

# add an exception for the "detected dubious ownership in repository" (only seen inside a Docker image)
git config --global --add safe.directory /MuseScore

##########################################################################
# GET TOOLS
##########################################################################

# COMPILER
if [ "$PACKARCH" == "armv7l" ]; then
  apt_packages_compiler=(
    automake
    gcc-8-arm-linux-gnueabihf
    g++-8-arm-linux-gnueabihf
    gfortran-8-arm-linux-gnueabihf
    binutils-arm-linux-gnueabihf
    )
  echo "export AS=/usr/bin/arm-linux-gnueabihf-as \
AR=/usr/bin/arm-linux-gnueabihf-ar \
CC=/usr/bin/arm-linux-gnueabihf-gcc-8 \
CPP=/usr/bin/arm-linux-gnueabihf-cpp-8 \
CXX=/usr/bin/arm-linux-gnueabihf-g++-8 \
LD=/usr/bin/arm-linux-gnueabihf-ld \
FC=/usr/bin/arm-linux-gnueabihf-gfortran-8 \
PKG_CONFIG_PATH=/usr/lib/arm-linux-gnueabihf/pkgconfig" >> ${ENV_FILE}
  export AS=/usr/bin/arm-linux-gnueabihf-as \
  AR=/usr/bin/arm-linux-gnueabihf-ar \
  CC=/usr/bin/arm-linux-gnueabihf-gcc-8 \
  CPP=/usr/bin/arm-linux-gnueabihf-cpp-8 \
  CXX=/usr/bin/arm-linux-gnueabihf-g++-8 \
  LD=/usr/bin/arm-linux-gnueabihf-ld \
  FC=/usr/bin/arm-linux-gnueabihf-gfortran-8 \
  PKG_CONFIG_PATH=/usr/lib/arm-linux-gnueabihf/pkgconfig
else
  apt_packages_compiler=(
    automake
    gcc-8-aarch64-linux-gnu
    g++-8-aarch64-linux-gnu
    gfortran-8-aarch64-linux-gnu
    binutils-aarch64-linux-gnu
    )
  echo "export AS=/usr/bin/aarch64-linux-gnu-as \
AR=/usr/bin/aarch64-linux-gnu-ar \
CC=/usr/bin/aarch64-linux-gnu-gcc-8 \
CPP=/usr/bin/aarch64-linux-gnu-cpp-8 \
CXX=/usr/bin/aarch64-linux-gnu-g++-8 \
LD=/usr/bin/aarch64-linux-gnu-ld \
FC=/usr/bin/aarch64-linux-gnu-gfortran-8 \
PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig" >> ${ENV_FILE}
  export AS=/usr/bin/aarch64-linux-gnu-as \
  AR=/usr/bin/aarch64-linux-gnu-ar \
  CC=/usr/bin/aarch64-linux-gnu-gcc-8 \
  CPP=/usr/bin/aarch64-linux-gnu-cpp-8 \
  CXX=/usr/bin/aarch64-linux-gnu-g++-8 \
  LD=/usr/bin/aarch64-linux-gnu-ld \
  FC=/usr/bin/aarch64-linux-gnu-gfortran-8 \
  PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig
fi

apt-get install -y --no-install-recommends \
  "${apt_packages_compiler[@]}"

# CMAKE
# Get newer CMake (only used cached version if it is the same)
apt-get install -y --no-install-recommends cmake
cmake --version

# Ninja
apt-get install -y --no-install-recommends ninja-build
echo "ninja version"
ninja --version

##########################################################################
# GET QT
##########################################################################

# Get newer Qt (only used cached version if it is the same)

if [ "$PACKARCH" == "armv7l" ]; then
  apt_packages_qt=(
    qt515base:armhf
    qt515declarative:armhf
    qt515quickcontrols:armhf
    qt515quickcontrols2:armhf
    qt515graphicaleffects:armhf
    qt515imageformats:armhf
    qt515networkauth-no-lgpl:armhf
    qt515remoteobjects:armhf
    qt515svg:armhf
    qt515tools:armhf
    qt515wayland:armhf
    qt515x11extras:armhf
    qt515xmlpatterns:armhf
    )
else
  apt_packages_qt=(
    qt515base:arm64
    qt515declarative:arm64
    qt515quickcontrols:arm64
    qt515quickcontrols2:arm64
    qt515graphicaleffects:arm64
    qt515imageformats:arm64
    qt515networkauth-no-lgpl:arm64
    qt515remoteobjects:arm64
    qt515svg:arm64
    qt515tools:arm64
    qt515wayland:arm64
    qt515x11extras:arm64
    qt515xmlpatterns:arm64
    )
fi

apt-get install -y \
  "${apt_packages_qt[@]}"

qt_version="5152"
qt_dir="/opt/qt515"

##########################################################################
# Compile and install nlohmann-json
##########################################################################
export CFLAGS="-Wno-psabi"
export CXXFLAGS="-Wno-psabi"
CURRDIR=${PWD}
cd /

git clone https://github.com/nlohmann/json
cd /json/
git checkout --recurse-submodules v3.10.4
git submodule update --init --recursive
mkdir -p build
cd build
cmake -DJSON_BuildTests=OFF ..
cmake --build . -j $(nproc)
cmake --build . --target install
cd /

##########################################################################
# Compile and install linuxdeploy
##########################################################################

git clone https://github.com/linuxdeploy/linuxdeploy
cd /linuxdeploy/
git checkout --recurse-submodules 49f4f237762395c6a37
git submodule update --init --recursive
mkdir -p build
cd build
cmake -DBUILD_TESTING=OFF -DUSE_SYSTEM_BOOST=ON ..
cmake --build . -j $(nproc)
mkdir -p $BUILD_TOOLS/linuxdeploy
mv /linuxdeploy/build/bin/* $BUILD_TOOLS/linuxdeploy/
$BUILD_TOOLS/linuxdeploy/linuxdeploy --version
cd /

##########################################################################
# Compile and install linuxdeploy-plugin-qt
##########################################################################

git clone https://github.com/linuxdeploy/linuxdeploy-plugin-qt
cd /linuxdeploy-plugin-qt/
git checkout --recurse-submodules 59b6c1f90e21ba14
git submodule update --init --recursive
mkdir -p build
cd build
cmake -DBUILD_TESTING=OFF -DUSE_SYSTEM_BOOST=ON ..
cmake --build . -j $(nproc)
mv /linuxdeploy-plugin-qt/build/bin/linuxdeploy-plugin-qt $BUILD_TOOLS/linuxdeploy/linuxdeploy-plugin-qt
$BUILD_TOOLS/linuxdeploy/linuxdeploy --list-plugins
cd /

##########################################################################
# Compile and install linuxdeploy-plugin-appimage
##########################################################################

git clone https://github.com/linuxdeploy/linuxdeploy-plugin-appimage
cd /linuxdeploy-plugin-appimage/
git checkout --recurse-submodules 779bd58443e8cc
git submodule update --init --recursive
mkdir -p build
cd build
cmake -DBUILD_TESTING=OFF ..
cmake --build . -j $(nproc)
mv /linuxdeploy-plugin-appimage/build/src/linuxdeploy-plugin-appimage $BUILD_TOOLS/linuxdeploy/linuxdeploy-plugin-appimage
cd /
$BUILD_TOOLS/linuxdeploy/linuxdeploy --list-plugins

##########################################################################
# Compile and install AppImageKit
##########################################################################

git clone https://github.com/AppImage/AppImageKit
cd /AppImageKit/
git checkout --recurse-submodules 13
git submodule update --init --recursive
mkdir -p build
cd build
cmake -DBUILD_TESTING=OFF ..
cmake --build . -j $(nproc)
cmake --build . --target install
mkdir -p $BUILD_TOOLS/appimagetool
cd /
appimagetool --version

##########################################################################
# Compile and install appimageupdatetool
##########################################################################

git clone https://github.com/AppImageCommunity/AppImageUpdate.git
cd AppImageUpdate
git checkout --recurse-submodules 2.0.0-alpha-1-20220512
git submodule update --init --recursive
mkdir -p build
cd build
# switch to using pkgconf
# the following is a super ugly hack that exists upstream
apt-get install -y --no-install-recommends pkgconf

if [ "$PACKARCH" == "armv7l" ]; then
  cp ../ci/libgcrypt.pc /usr/lib/arm-linux-gnueabihf/pkgconfig/libgcrypt.pc
  sed -i 's|x86_64-linux-gnu|arm-linux-gnueabihf|g' /usr/lib/arm-linux-gnueabihf/pkgconfig/libgcrypt.pc
  sed -i 's|x86_64-pc-linux-gnu|arm-pc-linux-gnueabihf|g' /usr/lib/arm-linux-gnueabihf/pkgconfig/libgcrypt.pc
else
  cp ../ci/libgcrypt.pc /usr/lib/aarch64-linux-gnu/pkgconfig/libgcrypt.pc
  sed -i 's|x86_64|aarch64|g' /usr/lib/aarch64-linux-gnu/pkgconfig/libgcrypt.pc
fi

# the hack uses pkgconf to produce a partial makefile and then installs back pkg-config to finish producing the makefile
cmake -DBUILD_TESTING=OFF -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=RelWithDebInfo .. || true
apt-get install -y --no-install-recommends pkg-config
cmake -DBUILD_TESTING=OFF -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=RelWithDebInfo ..
make -j"$(nproc)"
# create the extracted appimage directory
mkdir -p $BUILD_TOOLS/appimageupdatetool
make install DESTDIR=$BUILD_TOOLS/appimageupdatetool/appimageupdatetool-${PACKARCH}.AppDir
mkdir -p $BUILD_TOOLS/appimageupdatetool/appimageupdatetool-${PACKARCH}.AppDir/resources
cp -v ../resources/*.xpm $BUILD_TOOLS/appimageupdatetool/appimageupdatetool-${PACKARCH}.AppDir/resources/
$BUILD_TOOLS/linuxdeploy/linuxdeploy -v0 --appdir $BUILD_TOOLS/appimageupdatetool/appimageupdatetool-${PACKARCH}.AppDir  --output appimage -d ../resources/appimageupdatetool.desktop -i ../resources/appimage.png
cd $BUILD_TOOLS/appimageupdatetool
ln -s "appimageupdatetool-${PACKARCH}.AppDir/AppRun" appimageupdatetool # symlink for convenience
rm -rf /usr/lib/arm-linux-gnueabihf/pkgconfig/libgcrypt.pc /usr/lib/aarch64-linux-gnu/pkgconfig/libgcrypt.pc
cd /
$BUILD_TOOLS/appimageupdatetool/appimageupdatetool --version

cd ${CURRDIR}

# delete build folders
rm -rf /linuxdeploy*
rm -rf /AppImageKit
rm -rf /AppImageUpdate

# Dump syms
if [ "$PACKARCH" == "armv7l" ]; then
  echo "Get Breakpad"
  breakpad_dir=$BUILD_TOOLS/breakpad
  if [[ ! -d "$breakpad_dir" ]]; then
    wget -q --show-progress -O $BUILD_TOOLS/dump_syms.7z "https://s3.amazonaws.com/utils.musescore.org/breakpad/linux/armv7l/dump_syms.zip"
    7z x -y $BUILD_TOOLS/dump_syms.7z -o"$breakpad_dir"
  fi
  echo export DUMPSYMS_BIN="$breakpad_dir/dump_syms" >> $ENV_FILE
else
  echo "Get Breakpad"
  breakpad_dir=$BUILD_TOOLS/breakpad
  if [[ ! -d "$breakpad_dir" ]]; then
    wget -q --show-progress -O $BUILD_TOOLS/dump_syms.7z "https://s3.amazonaws.com/utils.musescore.org/breakpad/linux/aarch64/dump_syms.zip"
    7z x -y $BUILD_TOOLS/dump_syms.7z -o"$breakpad_dir"
  fi
  echo export DUMPSYMS_BIN="$breakpad_dir/dump_syms" >> $ENV_FILE
fi

echo export PATH="${qt_dir}/bin:\${PATH}" >> ${ENV_FILE}
echo export LD_LIBRARY_PATH="${qt_dir}/lib:\${LD_LIBRARY_PATH}" >> ${ENV_FILE}
echo export QT_PATH="${qt_dir}" >> ${ENV_FILE}
echo export QT_PLUGIN_PATH="${qt_dir}/plugins" >> ${ENV_FILE}
echo export QML2_IMPORT_PATH="${qt_dir}/qml" >> ${ENV_FILE}
echo export CFLAGS="-Wno-psabi" >> ${ENV_FILE}
echo export CXXFLAGS="-Wno-psabi" >> ${ENV_FILE}

##########################################################################
# POST INSTALL
##########################################################################

chmod +x "$ENV_FILE"

# # tidy up (reduce size of Docker image)
# apt-get clean autoclean
# apt-get autoremove --purge -y
# rm -rf /tmp/* /var/{cache,log,backups}/* /var/lib/apt/*

df -h .
echo "Setup script done"
