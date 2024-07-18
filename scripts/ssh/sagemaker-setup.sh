#!/usr/bin/env bash

set -e

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <INSTANCE_NAME> <NGROK_AUTH_TOKEN> [REGION]"
  exit 1
fi

INSTANCE_NAME="$1"
NGROK_AUTH_TOKEN="$2"
REGION="${3:-eu-west-1}"

# Get the current lifecycle configuration name attached to the instance
CONFIGURATION_NAME=$(aws sagemaker describe-notebook-instance --region "$REGION" --notebook-instance-name "$INSTANCE_NAME" | jq -e '.NotebookInstanceLifecycleConfigName | select (.!=null)' | tr -d '"')
echo "Configuration \"$CONFIGURATION_NAME\" attached to notebook instance $INSTANCE_NAME"

# Create a new configuration if not present
if [[ -z "$CONFIGURATION_NAME" ]]; then
    CONFIGURATION_NAME="better-sagemaker"
    echo "Creating new configuration $CONFIGURATION_NAME..."
    aws sagemaker create-notebook-instance-lifecycle-config \
        --region "$REGION" \
        --notebook-instance-lifecycle-config-name "$CONFIGURATION_NAME" \
        --on-start Content=$(echo '#!/usr/bin/env bash' | base64) \
        --on-create Content=$(echo '#!/usr/bin/env bash' | base64)

    # Attach the new lifecycle configuration to the notebook instance
    echo "Attaching configuration $CONFIGURATION_NAME to ${INSTANCE_NAME}..."
    aws sagemaker update-notebook-instance \
        --region "$REGION" \
        --notebook-instance-name "$INSTANCE_NAME" \
        --lifecycle-config-name "$CONFIGURATION_NAME"
fi

# Export the NGROK_AUTH_TOKEN
export NGROK_AUTH_TOKEN="$NGROK_AUTH_TOKEN"

echo "Downloading on-start.sh..."
# Save the existing on-start script into on-start.sh
aws sagemaker describe-notebook-instance-lifecycle-config --region "$REGION" --notebook-instance-lifecycle-config-name "$CONFIGURATION_NAME" | jq -r '.OnStart[0].Content' | base64 --decode > on-start.sh

echo "Adding SSH setup to on-start.sh..."
# Add the ngrok SSH setup to on-start.sh
{
  echo ''
  echo '# Set up ngrok SSH tunnel'
  echo "export NGROK_AUTH_TOKEN=\"${NGROK_AUTH_TOKEN}\""
  echo 'curl https://raw.githubusercontent.com/TaQuangTu/sagemaker-setup/master/scripts/ssh/on-start-ngrok.sh | bash'
} >> on-start.sh

echo "Uploading on-start.sh..."
# Update the lifecycle configuration with the updated on-start.sh script
aws sagemaker update-notebook-instance-lifecycle-config \
    --region "$REGION" \
    --notebook-instance-lifecycle-config-name "$CONFIGURATION_NAME" \
    --on-start Content="$(base64 < on-start.sh)"

echo "SSH setup with ngrok is complete for instance $INSTANCE_NAME in region $REGION."
