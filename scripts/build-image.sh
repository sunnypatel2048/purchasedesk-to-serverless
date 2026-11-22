#!/usr/bin/env bash
# Build the legacy server's image with Packer (infra/image), then keep only the newest image.
#
#   scripts/build-image.sh        (or: make image; uses the current AWS credentials)
#
# Takes about an hour and costs a few tens of cents (a Windows t3.large). The output is saved to logs/.
# After a successful build, older images of this project (tag Layer=image) are deregistered and their snapshots
# deleted, so only one image is ever stored and paid for.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="us-east-1"
export AWS_PAGER=""

mkdir -p "$ROOT/logs"
log="$ROOT/logs/image-$(date +%Y%m%d-%H%M%S).log"
commit="$(git -C "$ROOT" rev-parse --short HEAD)"
if [[ -n "$(git -C "$ROOT" status --porcelain infra/image)" ]]; then
  echo "Warning: infra/image has uncommitted changes; the image's GitCommit tag will say $commit." >&2
fi

cd "$ROOT/infra/image"
packer init .

start=$(date +%s)
packer build -color=false -var "git_commit=$commit" . 2>&1 | tee "$log"
echo "RESULT image build_s=$(( $(date +%s) - start ))" | tee -a "$log"

new="$(jq -r '.builds[-1].artifact_id' packer-manifest.json | cut -d: -f2)"
if [[ "$new" != ami-* ]]; then
  echo "No image id found in packer-manifest.json" >&2
  exit 1
fi
echo "New image: $new" | tee -a "$log"

# Keep only the newest image.
for old in $(aws ec2 describe-images --region "$REGION" --owners self \
    --filters Name=tag:Project,Values=purchasedesk Name=tag:Layer,Values=image \
    --query "Images[?ImageId!='$new'].ImageId" --output text); do
  snapshots="$(aws ec2 describe-images --region "$REGION" --image-ids "$old" \
    --query 'Images[0].BlockDeviceMappings[].Ebs.SnapshotId' --output text)"
  aws ec2 deregister-image --region "$REGION" --image-id "$old"
  echo "Deregistered the older image $old" | tee -a "$log"
  for snapshot in $snapshots; do
    aws ec2 delete-snapshot --region "$REGION" --snapshot-id "$snapshot"
    echo "Deleted its snapshot $snapshot" | tee -a "$log"
  done
done
