#!/bin/bash

installer_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
installer="${installer_dir}/rocknix-retroid-controls/install.sh"

if [ ! -x "${installer}" ]; then
  /usr/bin/foot /bin/bash -c "echo 'Installer payload was not found.'; sleep 15"
  exit 1
fi

exec /usr/bin/foot /bin/bash "${installer}"
