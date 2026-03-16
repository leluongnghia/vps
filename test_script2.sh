#!/bin/bash
conf="test_conf2.txt"
echo "    set \$skip_cache 0;" > "$conf"
if [[ -f "$conf" ]] && grep -q "\$skip_cache" "$conf"; then
    sed -i -e 's/set \$skip_cache 0;/set \$skip_cache 1; # DEV_MODE_ACTIVE/' "$conf"
fi
cat "$conf"
