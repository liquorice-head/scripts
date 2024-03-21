#!/bin/bash

# Check and install Homebrew
if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew not found. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Adding Homebrew to PATH for Apple Silicon Macs
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    echo "Homebrew is already installed."
fi

# Ensure Homebrew does not require further actions
brew doctor

# Update Homebrew and formulas
brew update

# Install applications from the list in brew_packages_list.txt
while read package; do
    brew install "$package"
done < brew_packages_list.txt

# Install GUI applications from the list in brew_cask_list.txt
while read cask; do
    brew install --cask "$cask"
done < brew_cask_list.txt
