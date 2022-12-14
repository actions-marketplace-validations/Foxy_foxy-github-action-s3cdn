#!/bin/bash

set -e

# Check that the environment variable has been set correctly
if [ -z "$AWS_S3_CDN_BUCKET_NAME" ]; then
  echo >&2 'error: missing AWS_S3_CDN_BUCKET_NAME environment variable'
  exit 1
fi

if [ -z "$AWS_S3_CDN_KEY_ID" ]; then
  echo >&2 'error: missing AWS_S3_CDN_KEY_ID environment variable'
  exit 1
fi

if [ -z "$AWS_S3_CDN_KEY_SECRET" ]; then
  echo >&2 'error: missing AWS_S3_CDN_KEY_SECRET environment variable'
  exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
  echo >&2 "$SOURCE_DIR does not exist. There is nothing to upload."
  exit 1
fi

# GET Released tag or Branch name taken from GITHUB_REF#refs/*/ e.g refs/heads/feature-branch-1
RELEASE_TAG_BRANCH="${GITHUB_REF#refs/*/}"
echo "Current release tag or branch name is is: ${RELEASE_TAG_BRANCH}"

if [ -z "$1" ]; then
  PACKAGE_NAME=$(echo "$GITHUB_REPOSITORY" | awk -F / '{print $2}')
else
  PACKAGE_NAME=$1
fi

echo "Getting the latest tag name from env:  ${LATEST_TAG_NAME}"
TAG_NAME=${LATEST_TAG_NAME}

# Set dir names to be created/synced with AWS S3
IFS='.' # . is set as delimiter
read -ra TAG_NAME <<< "$LATEST_TAG_NAME"   #  ${LATEST_TAG_NAME} is read into an array as tokens separated by IFS

if [ "${TAG_NAME[0]:0:1}" == "v" ]
then
  MAJOR="${PACKAGE_NAME}@${TAG_NAME[0]:1:3}"
else
  MAJOR=${PACKAGE_NAME}@${TAG_NAME[0]}
fi

MINOR="$MAJOR.${TAG_NAME[1]}"

if [ "${TAG_NAME[3]}" == "" ]
then
  PATCH="$MINOR.${TAG_NAME[2]}" # e.g v1.2.3
else
  PATCH="$MINOR.${TAG_NAME[2]}.${TAG_NAME[3]}"  # e.g v1.2.3-beta.1
fi

LATEST="${PACKAGE_NAME}@latest"
BETA="${PACKAGE_NAME}@beta"

echo "Major: $MAJOR Minor: $MINOR  Patch: $PATCH Beta: $BETA "

# Upload to S3
# Default to us-east-1 if AWS_REGION not set.
if [ -z "$AWS_REGION" ]; then
  AWS_REGION="us-east-1"
fi

# Create a dedicated profile for this action to avoid conflicts with past/future actions.
aws configure --profile s3cdn-sync <<-EOF > /dev/null 2>&1
${AWS_S3_CDN_KEY_ID}
${AWS_S3_CDN_KEY_SECRET}
${AWS_REGION}
text
EOF

# If its running from beta branch only update `repo@beta` and `repo@patch`
if [ "${RELEASE_TAG_BRANCH}" == "beta" ]
then
  # upload to beta and patch dir only i.e `repo@1.2.3-beta7` and `repo@beta`
  bash -c "aws s3 sync ${SOURCE_DIR:-.} s3://${AWS_S3_CDN_BUCKET_NAME}/${PATCH}  --profile s3cdn-sync  --no-progress"
  bash -c "aws s3 sync ${SOURCE_DIR:-.} s3://${AWS_S3_CDN_BUCKET_NAME}/${BETA}  --profile s3cdn-sync  --no-progress"
else
  # in case of main branch
  # Uploads dir content to it's respective AWS S3 `latest `dir
  bash -c "aws s3 sync ${SOURCE_DIR:-.} s3://${AWS_S3_CDN_BUCKET_NAME}/${LATEST} --profile s3cdn-sync --no-progress"
  # Uploads major version to it's respective AWS S3 dir
  bash -c "aws s3 sync ${SOURCE_DIR:-.} s3://${AWS_S3_CDN_BUCKET_NAME}/${MAJOR} --profile s3cdn-sync --no-progress"
  # Uploads minor version to it's respective AWS S3 dir
  if [ "$MINOR" != "" ]
  then
    bash -c "aws s3 sync ${SOURCE_DIR:-.} s3://${AWS_S3_CDN_BUCKET_NAME}/${MINOR} --profile s3cdn-sync --no-progress"
    # Uploads PATCH version to it's respective AWS S3 dir
    if [ "$PATCH" != "" ]
    then
      bash -c "aws s3 sync ${SOURCE_DIR:-.} s3://${AWS_S3_CDN_BUCKET_NAME}/${PATCH}  --profile s3cdn-sync  --no-progress"
    fi
  fi
fi

# Clear out credentials after we're done.
aws configure --profile s3cdn-sync <<-EOF > /dev/null 2>&1
null
null
null
text
EOF
