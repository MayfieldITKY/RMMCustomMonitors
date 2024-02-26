# CustomMonitors

### OVERVIEW
This is the repository to control server monitoring scripts for use with Datto RMM.
Monitoring scripts should run as Scheduled Tasks and write results to a custom event log.
Datto will monitor this event log and generate alerts as needed.


### SERVER SETUP
Initial deployment of scripts should be done through Datto RMM, including scripts to create Scheduled Tasks.


### TEST BRANCH
A test group should be set up in Datto for testing new scripts and changes to current scripts.


### SCRIPT UPDATES
A Scheduled Task should be set up to check for script updates from the main branch. The test group will check from the test branch.
Alternatively, this could be run as a job in Datto.


### CREATING NEW MONITORS
New monitoring scripts should have a narrowly defined purpose, i.e.: Check for Shadow Copies on Host Servers. 
Script results should be written to the custom event log according to the Event ID scheme in the tracking sheet.
RMM monitors should only check for these events for creating alerts.


### REFERENCE
Links to important references.

