#!/bin/bash

set -eu

REPO="simpl-hq/zero"
APP_NAME="zero-runtime"
BIN_DIR="$HOME/.local/bin"
BIN_PATH="$BIN_DIR/$APP_NAME"
PLATFORM="$(uname)"

if [ -n "${1:-}" ]; then
  RELEASE="tag/$1"
  DOWNLOAD="download/$1"
  echo "downloading Zero $1 ..."
else
  RELEASE=latest
  DOWNLOAD="latest/download"
  echo "downloading the latest version of Zero ..."
fi

if [ "$PLATFORM" = "Darwin" ]; then
  PLATFORM="macos-x86-64"
elif [ "$PLATFORM" = "Linux" ]; then
  PLATFORM="ubuntu-22_04-x86_64"
else
  echo "Scripted installation on your platform is not supported."
  echo "See compiled binaries in the ${1:-latest} release: https://github.com/$REPO/releases/$RELEASE"
  exit 1
fi

[ ! -d "$BIN_DIR" ] && mkdir -p "$BIN_DIR"

if [ -n "$(command -v curl)" ]; then
  curl -L -o "$BIN_PATH" "https://github.com/$REPO/releases/$DOWNLOAD/$APP_NAME-$PLATFORM"
elif [ -n "$(command -v wget)" ]; then
  wget -O "$BIN_PATH" "https://github.com/$REPO/releases/$DOWNLOAD/$APP_NAME-$PLATFORM"
else
  echo "Cannot download $APP_NAME - please install curl or wget"
  exit 1
fi

chmod +x "$BIN_PATH"

echo "$APP_NAME installed successfully!"

SHELL_FILE=""
if [ -z "$(command -v "$APP_NAME")" ]; then
  if [ -n "${ZSH_VERSION:-}" ] || [[ "${SHELL:-}" == *zsh* ]]; then
    SHELL_FILE="$HOME/.zshrc"
  elif [ -n "${BASH_VERSION:-}" ] || [[ "${SHELL:-}" == *bash* ]]; then
    SHELL_FILE="$HOME/.bashrc"
  else
    echo "Unknown shell - cannot add $APP_NAME folder to PATH"
    echo "Please add $BIN_DIR to PATH variable"
    echo "Or you can run $APP_NAME via full path: $BIN_PATH"
  fi
  if [ -n "$SHELL_FILE" ]; then
    echo "export PATH=\$PATH:$BIN_DIR" >> "$SHELL_FILE"
    echo "Source your $SHELL_FILE or open a new shell and type $APP_NAME to run it"
  fi
else
  echo "Type $APP_NAME in your terminal to run it"
fi
