# Custom dockur/windows image with built-in unattended provisioning.
# The /oem folder is copied by dockur to C:\OEM on the Windows disk during
# setup, and C:\OEM\install.bat runs automatically (proxy + installers).
FROM docker.io/dockurr/windows:latest

COPY oem/ /oem/
