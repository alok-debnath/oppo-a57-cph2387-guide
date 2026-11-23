#!/system/bin/sh
# Nothing persistent is written outside the module directory. The bind-mounts
# are process/boot scoped and vanish on reboot once the module is removed, which
# restores the stock /odm/lib64 libraries. No action needed here.
exit 0
