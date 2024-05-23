# ================ MAINTENANCE TASK: DELETE SHADOW COPIES ==================
# This task attempts to delete shadow copies from a host server. This should
# run before the scheduled task to check if shadow copies are present. It 
# should also check that Windows Server Backup or another backup or copy task 
# (like robocopy) is not running before removing shadow copies.

# The script will check each drive for shadow copies and attempt to delete them
# if found. It will check again after deleting and attempt to delete remaining 
# shadow copies. It will continue to attempt deletion as long as disk space 
# used by shadow copies continues to decrease on a drive, or until all copies 
# are deleted. If repeated attempts are not deleting all shadow copies, that
# drive will be skipped and the shadow copies will be reported by the monitor
# task.


# Check if Windows Server Backup (or another backup or copy task) is running. 
# Do not delete shadow copies if it is running.


# Get a list of drives and check for shadow copies on each drive.


# For each drive with shadow copies, attempt to delete them. After each attempt,
# check again for shadow copies and attempt to delete. Go on to the next drive
# when all copies are deleted or if repeated attempts fail.


# Report results to the event log.