#!/bin/sh

mkdir -p ./apps/multiplatform/common/src/commonMain/cpp/android/libs/arm64-v8a/
rm ./apps/multiplatform/common/src/commonMain/cpp/android/libs/arm64-v8a/*
unzip -o ~/Downloads/pkg-aarch64-android-libsupport.zip -d ./apps/multiplatform/common/src/commonMain/cpp/android/libs/arm64-v8a/
unzip -o  ~/Downloads/pkg-aarch64-android-libzero.zip -d ./apps/multiplatform/common/src/commonMain/cpp/android/libs/arm64-v8a/

mkdir -p ./apps/multiplatform/common/src/commonMain/cpp/android/libs/armeabi-v7a/
rm ./apps/multiplatform/common/src/commonMain/cpp/android/libs/armeabi-v7a/*
unzip -o  ~/Downloads/pkg-armv7a-android-libsupport.zip -d ./apps/multiplatform/common/src/commonMain/cpp/android/libs/armeabi-v7a/
unzip -o  ~/Downloads/pkg-armv7a-android-libzero.zip -d ./apps/multiplatform/common/src/commonMain/cpp/android/libs/armeabi-v7a/
