#!/bin/bash

launcher_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
uninstaller="${launcher_dir}/rocknix-retroid-controls/uninstall.sh"

if [ ! -x "${uninstaller}" ]; then
  /usr/bin/foot /bin/bash -c "echo 'Uninstaller payload was not found.'; sleep 15"
  exit 1
fi

exec /usr/bin/foot /bin/bash "${uninstaller}"
