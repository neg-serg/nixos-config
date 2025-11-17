[general]
status_path = "@XDG_STATE@/vdirsyncer"

# Calendars pair (filesystem <-> CalDAV)
[pair calendars]
a = "calendars_local"
b = "calendars_remote"
collections = ["from b"]
conflict_resolution = "b wins"
metadata = ["color", "displayname"]

[storage calendars_local]
type = "filesystem"
path = "@XDG_CONFIG@/vdirsyncer/calendars"
fileext = ".ics"

[storage calendars_remote]
type = "caldav"
# TODO: Replace with your CalDAV base URL (e.g., Nextcloud/Fastmail)
# Example (Nextcloud): https://cloud.example.com/remote.php/dav/calendars/USERNAME/
url = "https://REPLACE-ME-CALDAV-BASE/"
username = "REPLACE-ME-USER"
password = "REPLACE-ME-PASSWORD"
verify = true

# Contacts pair (filesystem <-> CardDAV)
[pair contacts]
a = "contacts_local"
b = "contacts_remote"
collections = ["from b"]
conflict_resolution = "b wins"

[storage contacts_local]
type = "filesystem"
path = "@XDG_CONFIG@/vdirsyncer/contacts"
fileext = ".vcf"

[storage contacts_remote]
type = "carddav"
# TODO: Replace with your CardDAV base URL (e.g., Nextcloud/Fastmail)
# Example (Nextcloud): https://cloud.example.com/remote.php/dav/addressbooks/users/USERNAME/
url = "https://REPLACE-ME-CARDDAV-BASE/"
username = "REPLACE-ME-USER"
password = "REPLACE-ME-PASSWORD"
verify = true
