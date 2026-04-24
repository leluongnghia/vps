# Change socket paths:
# /tmp/valkey.sock  -> /var/run/valkey/valkey.sock
# /tmp/redis.sock   -> /var/run/redis/redis.sock
# Also add mkdir -p + chown before socket creation in install_valkey/install_redis

$file = Join-Path $PSScriptRoot "modules\wordpress_performance.sh"
$enc  = [System.Text.UTF8Encoding]::new($false)
$c    = [System.IO.File]::ReadAllText($file, $enc)

$before = $c.Length

# 1. Socket path references (valkey)
$c = $c.Replace("/tmp/valkey.sock", "/var/run/valkey/valkey.sock")

# 2. Socket path references (redis)
$c = $c.Replace("/tmp/redis.sock", "/var/run/redis/redis.sock")

# 3. In install_valkey: add mkdir + chown before writing unixsocket to conf
$oldValkeyBlock = 'echo "unixsocket /var/run/valkey/valkey.sock" >> "$vconf"' + "`r`n" + '        echo "unixsocketperm 770" >> "$vconf"'
$newValkeyBlock = 'mkdir -p /var/run/valkey && chown valkey:valkey /var/run/valkey 2>/dev/null || true' + "`r`n" + '        echo "unixsocket /var/run/valkey/valkey.sock" >> "$vconf"' + "`r`n" + '        echo "unixsocketperm 770" >> "$vconf"'

if ($c.Contains($oldValkeyBlock)) {
    $c = $c.Replace($oldValkeyBlock, $newValkeyBlock)
    Write-Host "PATCH valkey mkdir: OK"
} else {
    # Try LF
    $oldLF = $oldValkeyBlock.Replace("`r`n", "`n")
    $newLF = $newValkeyBlock.Replace("`r`n", "`n")
    if ($c.Contains($oldLF)) {
        $c = $c.Replace($oldLF, $newLF)
        Write-Host "PATCH valkey mkdir (LF): OK"
    } else {
        Write-Host "WARN: valkey mkdir block not found - skipping"
    }
}

# 4. In install_redis: add mkdir + chown before writing unixsocket to conf
$oldRedisBlock = 'echo "unixsocket /var/run/redis/redis.sock" >> "$rconf"' + "`r`n" + '            echo "unixsocketperm 770" >> "$rconf"'
$newRedisBlock = 'mkdir -p /var/run/redis && chown redis:redis /var/run/redis 2>/dev/null || true' + "`r`n" + '            echo "unixsocket /var/run/redis/redis.sock" >> "$rconf"' + "`r`n" + '            echo "unixsocketperm 770" >> "$rconf"'

if ($c.Contains($oldRedisBlock)) {
    $c = $c.Replace($oldRedisBlock, $newRedisBlock)
    Write-Host "PATCH redis mkdir: OK"
} else {
    $oldLF = $oldRedisBlock.Replace("`r`n", "`n")
    $newLF = $newRedisBlock.Replace("`r`n", "`n")
    if ($c.Contains($oldLF)) {
        $c = $c.Replace($oldLF, $newLF)
        Write-Host "PATCH redis mkdir (LF): OK"
    } else {
        Write-Host "WARN: redis mkdir block not found - skipping"
    }
}

[System.IO.File]::WriteAllText($file, $c, $enc)
$after = ([System.IO.File]::ReadAllText($file, $enc)).Length
Write-Host "Done. File size: $before -> $after bytes"
Write-Host "Occurrences of /var/run/valkey:"
([System.IO.File]::ReadAllText($file, $enc) -split "`n" | Select-String "var/run/valkey").Count
