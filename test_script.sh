#!/bin/bash
conf="test_conf.txt"
echo "    set \$skip_cache 0;" > "$conf"
echo "Original:"
cat "$conf"
if [[ -f "$conf" ]] && grep -q "\$skip_cache" "$conf"; then
    sed -i 's/set \$skip_cache 0;/set \$skip_cache 1; # DEV_MODE_ACTIVE/' "$conf"
fi
echo "Result:"
cat "$conf"
