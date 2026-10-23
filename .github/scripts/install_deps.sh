#!/bin/bash
set -e

while (($# > 0)); do
  case $1 in
  --test) # install test dependencies
    TEST=1
    shift
    ;;
  esac
done

OS=$(uname -s)
ARCH=$(uname -m)
if [[ $OS == Linux ]]; then
  # The hosted runner's Azure mirror can stall package downloads for minutes.
  # Keep this override confined to disposable GitHub runners.
  if [[ ${RUNNER_ENVIRONMENT:-} == github-hosted ]]; then
    for exon_apt_source in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources /etc/apt/apt-mirrors.txt; do
      if [[ -f $exon_apt_source ]]; then
        sudo sed -i 's|azure.archive.ubuntu.com|archive.ubuntu.com|g' "$exon_apt_source"
      fi
    done
  fi
  sudo apt-get update
  sudo apt-get install -y build-essential cmake curl gettext ninja-build

  if [[ $CC == clang ]]; then
    DEFAULT_CLANG_VERSION=$(echo |  clang -dM -E - | grep __clang_major | awk '{print $3}')
    CLANG_VERSION=21
    if ((DEFAULT_CLANG_VERSION >= CLANG_VERSION)); then
      echo "Default clang version is $DEFAULT_CLANG_VERSION, which is equal or larger than wanted version $CLANG_VERSION. Aborting!"
      exit 1
    fi

    wget https://apt.llvm.org/llvm.sh
    chmod +x llvm.sh
    sudo ./llvm.sh $CLANG_VERSION
    # Alternatively could use `./llvm.sh … all` above, but that is heavy/slow.
    sudo apt-get install -y clang-tidy-$CLANG_VERSION
    sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-$CLANG_VERSION 100
    sudo update-alternatives --set clang /usr/bin/clang-$CLANG_VERSION
    sudo update-alternatives --install /usr/bin/clang-tidy clang-tidy /usr/bin/clang-tidy-$CLANG_VERSION 100
    sudo update-alternatives --set clang-tidy /usr/bin/clang-tidy-$CLANG_VERSION
  fi

  if [[ -n $TEST ]]; then
    sudo apt-get install -y locales-all cpanminus attr libattr1-dev fish gdb inotify-tools xdg-utils

    # Use default CC to avoid compilation problems when installing Python modules
    CC=cc python3 -m pip -q install --user --upgrade --break-system-packages pynvim

    # Skip installing npm on aarch64 as it tends to cause intermittent segmentation faults.
    # See https://github.com/neovim/neovim/issues/32339.
    if [[ $ARCH != aarch64 ]]; then
      npm install -g neovim
      npm link neovim
    fi
  fi
elif [[ $OS == Darwin ]]; then
  if [[ -n $TEST ]]; then
    brew untap aws/tap
    brew install cpanminus fish fswatch

    npm install -g neovim
    npm link neovim

    # Use default CC to avoid compilation problems when installing Python modules
    CC=cc python3 -m pip -q install --user --upgrade --break-system-packages pynvim
  fi
fi
