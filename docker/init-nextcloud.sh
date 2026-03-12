#!/bin/bash
# Wait for Nextcloud to finish initial setup
until curl -s http://localhost/status.php | grep -q '"installed":true'; do
  echo "Waiting for Nextcloud installation..."
  sleep 5
done

echo "Nextcloud installed, configuring apps..."

# Enable apps via occ
su -s /bin/bash www-data -c "php occ app:enable notes"
su -s /bin/bash www-data -c "php occ app:enable calendar"
su -s /bin/bash www-data -c "php occ app:enable spreed"  # Talk

# Create ExCalibur folder
su -s /bin/bash www-data -c "php occ files:scan --all"

echo "Nextcloud init complete."
