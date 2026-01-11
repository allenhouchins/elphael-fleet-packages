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

# Note: Git and Homebrew are pre-installed in GitHub Actions runners

# Add the AutoPkg 'recipes' repo
echo "Adding the 'recipes' repo to AutoPkg..."
autopkg repo-add recipes

# Check if repo-add was successful
if [ $? -ne 0 ]; then
    echo "Failed to add the 'recipes' repo!"
    exit 1
fi

echo "'recipes' repo added successfully!"

# Run the AutoPkg recipe for Firefox
echo "Running the AutoPkg recipe to create the Firefox installer..."
autopkg run -v /Users/runner/Library/AutoPkg/RecipeRepos/com.github.autopkg.recipes/Mozilla/FirefoxSignedPkg.pkg.recipe

# Check if the recipe run was successful
if [ $? -ne 0 ]; then
    echo "Failed to create the Firefox installer!"
    exit 1
fi

echo "Firefox installer created successfully!"

PACKAGE_FILE=$(ls /Users/runner/Library/AutoPkg/Cache/com.github.autopkg.pkg.FirefoxSignedPkg/downloads/Firefox*.pkg)

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

# Configure git
git config --global user.email "$USER_EMAIL"
git config --global user.name "$USER_NAME"

# Clone repo with LFS smudge skipped to avoid downloading large files
# We only need the repository structure, not the actual LFS files
echo "Cloning repository (skipping LFS file download)..."
GIT_LFS_SKIP_SMUDGE=1 git clone "https://$PACKAGE_AUTOMATION_TOKEN@github.com/$REPO_OWNER/$REPO_NAME.git" /tmp/repo

if [ $? -ne 0 ]; then
    echo "Failed to clone repository!"
    exit 1
fi

# Change to repo directory
cd /tmp/repo

# Ensure Git LFS is initialized and .pkg files are tracked
if [ "$PKGSIZE" -gt "104857600" ]; then
    echo "Package is larger than 100MB, ensuring Git LFS is configured..."
    git lfs install
    
    # Ensure .pkg files are tracked by LFS
    if ! grep -q "*.pkg filter=lfs" .gitattributes 2>/dev/null; then
        git lfs track "*.pkg"
        git add .gitattributes
    fi
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

# Clean up old packages - keep only the latest 2
echo "Cleaning up old Firefox packages (keeping only the latest 2)..."
# Get all Firefox packages sorted by modification time (newest first)
# The newly copied package will be the newest
ALL_FIREFOX_PACKAGES=$(ls -t Firefox*.pkg 2>/dev/null)
if [ -n "$ALL_FIREFOX_PACKAGES" ]; then
    # Keep only the 2 newest packages
    KEEP_PACKAGES=$(echo "$ALL_FIREFOX_PACKAGES" | head -2)
    echo "Keeping the following packages:"
    echo "$KEEP_PACKAGES"
    
    # Find all Firefox packages and delete those not in the keep list
    for pkg in Firefox*.pkg; do
        if [ -f "$pkg" ]; then
            if ! echo "$KEEP_PACKAGES" | grep -q "^$pkg$"; then
                echo "Deleting old package: $pkg"
                # Use git rm -f to remove tracked files (force in case of modifications)
                # If file is untracked, git rm will fail, so just remove it
                git rm -f "$pkg" 2>/dev/null || rm -f "$pkg"
            fi
        fi
    done
else
    echo "No existing Firefox packages found to clean up."
fi

echo "Repository status after copying package and cleanup:"
git status

# Add and commit the package
echo "Adding and committing the package..."

# Add the package file and any .gitattributes changes
git add "$PACKAGE_NAME"
if [ "$PKGSIZE" -gt "104857600" ] && [ -f .gitattributes ]; then
    git add .gitattributes
fi

# Commit the changes
git commit -m "Add newest Firefox installer package: $PACKAGE_NAME"

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
version_string=$(basename "$PACKAGE_FILE" | sed -n 's/.*Firefox-\([0-9.]*\)\.pkg/\1/p')

echo "Extracted version: $version_string"

# Write new version info to Fleet policy
FILE_PATH="lib/software/latest-firefox-pkg.yml"
NEW_URL="https://github.com/$REPO_OWNER/$REPO_NAME/raw/refs/heads/main/Firefox-$version_string.pkg"

echo "New URL: $NEW_URL"

BRANCH_NAME="main"
COMMIT_MESSAGE="Update URL in latest-firefox-pkg.yml"

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