#!/usr/bin/env bash
set -euo pipefail

# TODO: Generate vCard based on NFC tag capacity. For example mine has 7676 bytes
# -------------------------------------------------------------------
# update_vcards_multiple_resolutions.sh
#
# Downloads an image, converts it to JPEG at every 100px increment 
# (up to the source's smallest side), base64‐encodes it with proper 
# vCard folding, and generates one .vcf per resolution.
# Backs up original me.vcf to me.vcf.bak.
#
# Usage: ./update_vcards_multiple_resolutions.sh IMAGE_URL
# -------------------------------------------------------------------

VCF_FILE="me.vcf"
BACKUP_FILE="${VCF_FILE}.bak"
TMP_INPUT="photo_input"
TMP_JPG="photo.jpg"

if [ $# -ne 1 ]; then
  echo "Usage: $0 IMAGE_URL"
  exit 1
fi

IMAGE_URL="$1"

# 1. Download the image
curl -sSL -o "$TMP_INPUT" "$IMAGE_URL"

# 2. Determine dimensions of the source
width=$(gm identify -format "%w" "$TMP_INPUT")
height=$(gm identify -format "%h" "$TMP_INPUT")
min_dim=$(( width < height ? width : height ))

# Compute the largest multiple of 100px ≤ min_dim
max_size=$(( (min_dim / 100) * 100 ))
if [ "$max_size" -lt 100 ]; then
  echo "Error: Image too small (min dimension is ${min_dim}px < 100px)."
  exit 1
fi

# 3. Backup the original vCard
cp "$VCF_FILE" "$BACKUP_FILE"
VCF_PREFIX="${VCF_FILE%.*}"

# 4. Loop through each 100px increment
for size in $(seq 100 10 "961"); do
  # Resize & convert to JPEG
  gm convert "$TMP_INPUT" -background black -gravity south -extent "960x960" +profile "*" -background black -gravity south -resize ${size}x${size}\> "$TMP_JPG"

  # cp -f "$TMP_JPG" "output_${size}.jpg"

  # Build a new vCard with the resized, base64-encoded photo
  perl -Mstrict -Mwarnings -MMIME::Base64 -0777 -e '
    my ($vcf_file, $img_file) = @ARGV;
    # Read the entire vCard
    open my $vcffh, "<", $vcf_file or die "Cannot open $vcf_file: $!";
    local $/; my $vcf = <$vcffh>;
    close $vcffh;

    # Read and encode the image
    open my $imgfh, "<:raw", $img_file or die "Cannot open $img_file: $!";
    local $/; my $img = <$imgfh>;
    close $imgfh;
    my $b64 = encode_base64($img, "");
    $b64 =~ s/(.{75})/$1\r\n /g;

    # Construct PHOTO block
    my $new_photo = "PHOTO;ENCODING=b;TYPE=JPEG:$b64\r\n";

    # Replace old PHOTO block and print
    $vcf =~ s/PHOTO;ENCODING=b;TYPE=JPEG:.*?END:VCARD/$new_photo\nEND:VCARD/s;
    print $vcf;
  ' "$VCF_FILE" "$TMP_JPG" > "${VCF_PREFIX}_${size}.vcf"

  echo "✅ Generated ${VCF_PREFIX}_${size}.vcf with ${size}px photo"
done

# 5. Cleanup
rm -f "$TMP_INPUT" "$TMP_JPG"

echo "🎉 Done! Original backed up as $BACKUP_FILE."
