# Patches

Our own changes to Actual's code live here as `.patch` files. `scripts/prepare.sh`
applies them in filename order (`001-...patch`, `002-...patch`) on top of the
pinned Actual commit, so the app keeps our features while still being easy
to update to new Actual releases.
