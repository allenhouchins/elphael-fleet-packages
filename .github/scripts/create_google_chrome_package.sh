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

# # Check if Homebrew is installed ## Remove comments if running locally
# if ! command -v brew &> /dev/null; then
#     echo "Homebrew is not installed. Installing Homebrew without root privileges..."

#     # Install Homebrew as the non-root user
#     su -l $SUDO_USER -c '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' ## Uncomment if running locally and comment out next line
#     brew install git

#     # Check if Homebrew installation was successful
#     if [ $? -ne 0 ]; then
#         echo "Homebrew installation failed!"
#         exit 1
#     fi

#     echo "Homebrew installation complete."
# else
#     echo "Homebrew is already installed."
# fi

# # Install Git using Homebrew (no root privileges)
# echo "Installing Git using Homebrew..."
# # su -l $SUDO_USER -c 'brew install git' ## Uncomment if running locally and comment out next line
# brew install git

# # Check if Git installation was successful
# if [ $? -ne 0 ]; then
#     echo "Git installation failed!"
#     exit 1
# fi

# echo "Git installation complete."

# Add the AutoPkg 'recipes' repo after Git is installed
echo "Adding the 'recipes' repo to AutoPkg..."
# su -l $SUDO_USER -c 'autopkg repo-add recipes' ## Uncomment if running locally and comment out next line
autopkg repo-add recipes ## add whatever additional repos you need here

# Check if repo-add was successful
if [ $? -ne 0 ]; then
    echo "Failed to add the 'recipes' repo!"
    exit 1
fi

echo "'recipes' repo added successfully!"

# Run the AutoPkg recipe for Google Chrome
echo "Running the AutoPkg recipe to create the Google Chrome installer..."
# su -l $SUDO_USER -c 'autopkg run -v GoogleChromePkg.pkg' ## Uncomment if running locally and comment out next line
autopkg run -v GoogleChromePkg.pkg

# Check if the recipe run was successful
if [ $? -ne 0 ]; then
    echo "Failed to create the Google Chrome installer!"
    exit 1
fi

echo "Google Chrome installer created successfully!"

PACKAGE_FILE=$(ls /Users/runner/Library/AutoPkg/Cache/com.github.autopkg.pkg.googlechromePkg/GoogleChrome*.pkg)

echo "This is the Package File Path: $PACKAGE_FILE"

# Verify that the package file exists
if [ -f "$PACKAGE_FILE" ]; then
   echo "Found package: $PACKAGE_FILE"
else
    echo "No package file found!"
    exit 1
fi

# Check the size of the package
PKGSIZE=$(stat -f%z "${PACKAGE_FILE}")

if [ "$PKGSIZE" -eq 0 ]; then
    echo "Package size is 0. Something went wrong."
    exit 1
fi

echo "Package size is: $PKGSIZE bytes"

# Configure git if necessary
git config --global user.email "$USER_EMAIL"
git config --global user.name "$USER_NAME"

# Clone repo
git clone "https://$PACKAGE_AUTOMATION_TOKEN@github.com/$REPO_OWNER/$REPO_NAME.git" /tmp/repo

if [ $? -ne 0 ]; then
    echo "Failed to clone repository!"
    exit 1
fi

# Change to repo directory
cd /tmp/repo

echo "Repository status before changes:"
git status

# Check if Git LFS is needed (>100MB)
if [ "$PKGSIZE" -gt "104857600" ]; then
    echo "Package is larger than 100MB, setting up Git LFS..."
    
    # Install and configure Git LFS
    git lfs install
    
    # Track .pkg files with LFS
    git lfs track "*.pkg"
    
    # Add the .gitattributes file
    git add .gitattributes
    
    echo "Git LFS configured for .pkg files"
else
    echo "Package is smaller than 100MB, Git LFS not needed"
fi

# Copy the package to the GitHub repo
echo "Copying package to GitHub repo..."
PACKAGE_NAME=$(basename "$PACKAGE_FILE")
cp "$PACKAGE_FILE" "/tmp/repo/$PACKAGE_NAME"

if [ $? -ne 0 ]; then
    echo "Failed to copy package file!"
    exit 1
fi

echo "Package copied successfully as: $PACKAGE_NAME"

echo "Repository status after copying package:"
git status

# Add and commit the package
echo "Adding and committing the package..."

# Add the package file
git add "$PACKAGE_NAME"

# If we set up LFS, make sure .gitattributes is also committed
if [ "$PKGSIZE" -gt "104857600" ]; then
    git add .gitattributes
fi

echo "Files staged for commit:"
git status --staged

# Commit the changes
git commit -m "Add newest Google Chrome installer package: $PACKAGE_NAME"

if [ $? -ne 0 ]; then
    echo "Failed to commit package!"
    exit 1
fi

# Push to the GitHub repository
echo "Pushing to GitHub..."
git push origin main

# Check if the push was successful
if [ $? -eq 0 ]; then
    echo "Package uploaded to GitHub successfully!"
else
    echo "Failed to upload package to GitHub."
    exit 1
fi

# Extract version string for Fleet policy update
version_string=$(basename "$PACKAGE_FILE" | sed -n 's/.*GoogleChrome-\([0-9.]*\)\.pkg/\1/p')

echo "Extracted version: $version_string"

# Write new version info to Fleet policy
FILE_PATH="lib/software/latest-google-chrome-pkg.yml"
NEW_URL="https://github.com/$REPO_OWNER/$REPO_NAME/raw/refs/heads/main/GoogleChrome-$version_string.pkg"

echo "New URL: $NEW_URL"

BRANCH_NAME="main"
COMMIT_MESSAGE="Update URL in latest-google-chrome-pkg.yml"

# Clone the GitOps repository
git clone "https://$SOFTWARE_PACKAGE_UPDATER@github.com/$GITOPS_REPO_OWNER/$GITOPS_REPO_NAME.git" /tmp/gitops

if [ $? -ne 0 ]; then
    echo "Failed to clone GitOps repository!"
    exit 1
fi

cd /tmp/gitops

# Checkout the target branch
git checkout $BRANCH_NAME

echo "Updating file: /tmp/gitops/$FILE_PATH"

# Modify the URL line in the file
if [ -f "/tmp/gitops/$FILE_PATH" ]; then
    sed "s|^url:.*|url: $NEW_URL|" "/tmp/gitops/$FILE_PATH" > /tmp/tempfile && mv /tmp/tempfile "/tmp/gitops/$FILE_PATH"
    
    # Verify that the change has been made
    echo "Updated file content:"
    cat "/tmp/gitops/$FILE_PATH"
    
    # Configure Git
    git config user.name "$USER_NAME"
    git config user.email "$USER_EMAIL"
    
    # Add the changes
    git add "$FILE_PATH"
    
    # Commit the changes
    git commit -m "$COMMIT_MESSAGE"
    
    # Push the changes back to GitHub
    git push "https://$SOFTWARE_PACKAGE_UPDATER@github.com/$GITOPS_REPO_OWNER/$GITOPS_REPO_NAME.git" $BRANCH_NAME
    
    if [ $? -eq 0 ]; then
        echo "GitOps changes have been committed and pushed successfully."
    else
        echo "Failed to push GitOps changes."
        exit 1
    fi
else
    echo "Warning: GitOps file $FILE_PATH not found!"
fi

# Clean up
echo "Cleaning up temporary files..."
cd /tmp
rm -rf /tmp/repo
rm -rf /tmp/gitops
rm -f "$DOWNLOAD_PATH"

echo "Script completed successfully!"

exit 0