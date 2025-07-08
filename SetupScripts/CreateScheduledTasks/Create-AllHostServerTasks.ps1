# =========== CREATE TASKS: HOST SERVER AND WINDOWS SERVER BACKUPS ============
# Creates or updates scheduled tasks to run the following scripts:
#       HOST-CheckandClearShadowCopies.ps1
#       HOST-CheckHyperVCheckpoints.ps1
#       WSB-BackuptheBackups.ps1
#       WSB-StartWindowsServerBackup.ps1


# Get start time for Windows Server Backup and if it should run on weekends
# Other tasks will schedule around this time

# Schedule Windows Server Backup
# Revise to write to event log that weekend backup is not needed. Datto will
# monitor this event instead of WSB success event.

# Backup the backups runs 30 minutes before backup, and after Friday backups,
# unless backups also run on weekends.

# Check and clear shadow copies runs 15 minutes before backup the backups.
# 

# Checking Hyper-V checkpoints can occur daily at 8 AM


# (Script not created yet) Script to correct common backup errors should run
# after failure events are triggered. 