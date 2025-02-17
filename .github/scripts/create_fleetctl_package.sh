#!/bin/bash

# Define the URL and target paths for AutoPkg
AUTOPKG_URL="https://github.com/autopkg/autopkg/releases/download/v2.7.3/autopkg-2.7.3.pkg"
DOWNLOAD_PATH="/tmp/autopkg-2.7.3.pkg"

# Download and install AutoPkg
echo "Downloading AutoPkg package..."
curl -L -o "$DOWNLOAD_PATH" "$AUTOPKG_URL"

if [ $? -ne 0 ]; then
    echo "Download failed!"
    exit 1
fi

if ! command -v autopkg &> /dev/null; then
    echo "Installing AutoPkg..."
    sudo installer -pkg "$DOWNLOAD_PATH" -target /
    if [ $? -ne 0 ]; then
        echo "AutoPkg installation failed!"
        exit 1
    fi
fi

# Install Homebrew if needed
if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    brew install git
fi

# Add required AutoPkg repos
echo "Adding required AutoPkg repos..."
autopkg repo-add homebysix-recipes
autopkg repo-add https://github.com/allenhouchins/fleet-stuff.git

# Run the AutoPkg recipe for Fleet with verbose output
echo "Running the AutoPkg recipe to create the Fleet package..."
autopkg run -vv fleetctl.pkg

# List the AutoPkg cache directory to help debug
echo "Listing AutoPkg cache directory contents:"
ls -la ~/Library/AutoPkg/Cache/

# The package should be in the downloads subdirectory
PACKAGE_FILE=$(find ~/Library/AutoPkg/Cache -name "fleetctl-*.pkg" -type f | tail -n 1)

if [ ! -f "$PACKAGE_FILE" ]; then
    echo "Package not found! Checking alternate locations..."
    # Try searching in the parent directories
    PACKAGE_FILE=$(find ~/Library/AutoPkg -name "fleetctl-*.pkg" -type f | tail -n 1)
    
    if [ ! -f "$PACKAGE_FILE" ]; then
        echo "Package still not found! Directory contents:"
        find ~/Library/AutoPkg -type f
        exit 1
    fi
fi

echo "Found package at: $PACKAGE_FILE"

# Check package size for Git LFS
PKGSIZE=$(stat -f%z "${PACKAGE_FILE}")
if [ "$PKGSIZE" -gt "104857600" ]; then
    echo "Installing git-lfs"
    brew install git-lfs
    export add_git_lfs="git lfs install; git lfs track *.pkg; git add .gitattributes"
else
    export add_git_lfs="echo 'git lfs not needed. Continuing...'"
fi

# Configure git
git config --global user.email "$USER_EMAIL"
git config --global user.name "$USER_NAME"

# Clone repo and add package
git clone "https://$PACKAGE_AUTOMATION_TOKEN@github.com/$REPO_OWNER/$REPO_NAME.git" /tmp/repo
cp "${PACKAGE_FILE}" /tmp/repo
cd /tmp/repo
eval "$add_git_lfs"

# Commit and push
git add $(basename "$PACKAGE_FILE")
git commit -m "Add Fleet package version ${FLEET_VERSION}"
git push origin main

# Cleanup
rm -rf /tmp/repo