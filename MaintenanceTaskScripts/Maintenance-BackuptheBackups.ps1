# ============ BACKUP THE BACKUPS ============
# Creates revisions of Windows Server Backups on host servers.
# Checks that the recent backup is successful before updating revisions.
# This should replace the old backup_the_backups.bat script that creates revisions
# without checking for successful backup.

# Check for successful backup