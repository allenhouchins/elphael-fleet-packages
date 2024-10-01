#!/bin/bash

# Define the URL and target paths for AutoPkg
PACKAGE_URL="https://github.com/autopkg/autopkg/releases/download/v2.7.3/autopkg-2.7.3.pkg"
DOWNLOAD_PATH="/tmp/autopkg-2.7.3.pkg"
# USER_HOME=$(eval echo ~$SUDO_USER)
# AUTOPKG_CACHE_PATH="${USER_HOME}/Library/AutoPkg/Cache/com.github.autopkg.pkg.googlechrome/"
# REPO_URL="xxx" ## Uncomment if running locally
# PACKAGE_AUTOMATION_TOKEN="xxx" ## Uncomment if running locally
# REPO_OWNER="xxx" ## Uncomment if running locally
# REPO_NAME="" ## Uncomment if running locally

# Download the AutoPkg package
echo "Downloading AutoPkg package..."
curl -L -o "$DOWNLOAD_PATH" "$PACKAGE_URL"

# Check if download was successful
if [ $? -ne 0 ]; then
    echo "Download failed!"
    exit 1
fi

echo "Download complete."

#Check if autopkg is installed
if ! command -v autopkg &> /dev/null; then
    echo "AutoPkg is not installed. Installing AutoPkg..."
    # Install the downloaded AutoPkg package
    sudo installer -pkg "$DOWNLOAD_PATH" -target /

    # Check if installation was successful
    if [ $? -ne 0 ]; then
        echo "AutoPkg installation failed!"
        exit 1
    fi
    echo "AutoPkg installation complete."
else
    echo "AutoPkg is already installed."
fi

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "Homebrew is not installed. Installing Homebrew without root privileges..."

    # Install Homebrew as the non-root user
    su -l $SUDO_USER -c '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' ## Uncomment if running locally and comment out next line
    brew install git

    # Check if Homebrew installation was successful
    if [ $? -ne 0 ]; then
        echo "Homebrew installation failed!"
        exit 1
    fi

    echo "Homebrew installation complete."
else
    echo "Homebrew is already installed."
fi

# Install Git using Homebrew (no root privileges)
echo "Installing Git using Homebrew..."
# su -l $SUDO_USER -c 'brew install git' ## Uncomment if running locally and comment out next line
brew install git

# Check if Git installation was successful
if [ $? -ne 0 ]; then
    echo "Git installation failed!"
    exit 1
fi

echo "Git installation complete."

# Add the AutoPkg 'recipes' repo after Git is installed
echo "Adding the 'recipes' repo to AutoPkg..."
# su -l $SUDO_USER -c 'autopkg repo-add recipes' ## Uncomment if running locally and comment out next line
autopkg repo-add recipes

# Check if repo-add was successful
if [ $? -ne 0 ]; then
    echo "Failed to add the 'recipes' repo!"
    exit 1
fi

echo "'recipes' repo added successfully!"

# Run the AutoPkg recipe for Firefox
echo "Running the AutoPkg recipe to create the Firefox installer..."
# su -l $SUDO_USER -c 'autopkg run -v Firefox.pkg' ## Uncomment if running locally and comment out next line
autopkg run -v /Users/runner/Library/AutoPkg/RecipeRepos/com.github.autopkg.recipes/Mozilla/FirefoxSignedPkg.pkg.recipe

# Check if the recipe run was successful
if [ $? -ne 0 ]; then
    echo "Failed to create the Firefox installer!"
    exit 1
fi

echo "Firefox installer created successfully!"

PACKAGE_FILE=$(ls /Users/runner/Library/AutoPkg/Cache/com.github.autopkg.pkg.Firefox_EN/Firefox*.pkg)

echo "This is the Package File Path: $PACKAGE_FILE"

# Verify that the package file exists
if [ -f "$PACKAGE_FILE" ]; then
   echo "Found package: $PACKAGE_FILE"
else
    echo "No package file found in $AUTOPKG_CACHE_PATH!"
    exit 1
fi

# Check the size of the package
PKGSIZE=$(stat -f%z "${PACKAGE_FILE}")

if [ "$PKGSIZE" -eq 0 ]; then
    echo "Package size is 0. Something went wrong."
    exit 1
fi

echo "Package size is: $PKGSIZE bytes"

if [ "$PKGSIZE" -gt "104857600" ]; then
    echo "Installing git-lifs"
    # su -l $SUDO_USER -c 'brew install git-lfs'
    brew install git-lfs
    add_git_lfs="git lfs install; git lfs track *.pkg; git add .gitattributes" ## Need to verify this adds to gitattributes as new packages get created
else
    echo "Package is smaller than 100MB"
    add_git_lfs="echo "git lfs not needed. Continuing...""
fi

# Check if the recipe run was successful
if [ $? -ne 0 ]; then
    echo "Failed to install git-lfs!"
    exit 1
fi

# Configure git if necessary
git config --global user.email "$USER_EMAIL"
git config --global user.name "$USER_NAME"

# Clone repo
git clone "https://$PACKAGE_AUTOMATION_TOKEN@github.com/$REPO_OWNER/$REPO_NAME.git" /tmp/repo

# Copy the package to the GitHub repo
echo "Copying package to GitHub repo..."
# cp "${PACKAGE_FILE}" /tmp/repo
cp /Users/runner/Library/AutoPkg/Cache/com.github.autopkg.pkg.Firefox_EN/Firefox*.pkg /tmp/repo
cd /tmp/repo
# echo "This is the git lfs command at this step: $add_git_lfs"
# eval "$add_git_lfs"
git lfs install; git lfs track *.pkg; git add .gitattributes

# Add, commit, and push the package to GitHub
echo "Adding and committing the package..."
git add $(basename "$PACKAGE_FILE")
git commit -m "Add newest Firefox installer package"

# Push to the GitHub repository using a personal access token
echo "Pushing to GitHub..."
git push origin main

# Check if the push was successful
if [ $? -eq 0 ]; then
    echo "Package uploaded to GitHub successfully!"
else
    echo "Failed to upload package to GitHub."
    exit 1
fi

# cd .. ## Uncomment if running locally
# rm -rf /tmp/repo ## Uncomment if running locally
# rm -rf ${USER_HOME}/Library/AutoPkg/Cache/com.github.autopkg.pkg.googlechrome/*  ## ## Uncomment if running locally 


## write the new software package to YAML (basename)
## Replace any existing Google Chrome entries

exit 0





