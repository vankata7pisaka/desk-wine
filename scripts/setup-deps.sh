#!/usr/bin/env bash
# Каквото трябва на Ubuntu 24.04, за да компилира Wine за телефон.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

dpkg --add-architecture i386
apt-get update -qq

apt-get install -y --no-install-recommends \
  build-essential \
  git wget curl unzip \
  flex bison gettext \
  autoconf automake libtool pkg-config \
  mingw-w64 \
  gcc-multilib g++-multilib \
  libfreetype6-dev libfreetype6-dev:i386 \
  libpng-dev libpng-dev:i386 \
  zlib1g-dev zlib1g-dev:i386

echo "Готово."
