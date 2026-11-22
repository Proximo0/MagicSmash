# Graceful stop: runner finishes the current id, pushes, and exits.
New-Item -ItemType File D:\projects\hh_art\STOP -Force | Out-Null; "STOP file written; runner exits after the current id"
