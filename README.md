# CustomMonitors

### OVERVIEW
This is the repository to control server monitoring scripts for use with Datto RMM.
Monitoring scripts should run as Scheduled Tasks and write results to a custom event log.
Datto will monitor this event log and generate alerts as needed.


### SERVER SETUP
Initial deployment of scripts should be done through Datto RMM, using the script UpdatesFromGitHub.ps1.
UpdatesFromDatto.ps1 can also be used, but confirm that the current repository is used unless this is for testing.
This script also runs scripts to create Scheduled Tasks.


### TEST BRANCH
A test group should be set up in Datto for testing new scripts and changes to current scripts.


### SCRIPT UPDATES
DO NOT SCHEDULE AUTOMATIC UPDATES. If the repository is ever compromised, servers could be infected with malicious scripts!
Only run this as an immediate job when updates are needed.


### CREATING NEW MONITORS
New monitoring scripts should have a narrowly defined purpose, i.e.: Check for Shadow Copies on Host Servers. 
Script results should be written to the custom event log according to the Event ID scheme in the tracking sheet.
RMM monitors should only check for these events for creating alerts.
A separate script is needed to create a scheduled task to run the script! This script will be run during an update or deployment.
This script should also write to the event log.


### REFERENCE
Links to important references.

