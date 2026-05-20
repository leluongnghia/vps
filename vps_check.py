import paramiko
import sys
import io

# Reconfigure stdout to use utf-8 to avoid encoding errors on Windows
if sys.stdout.encoding != 'utf-8':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

def run_ssh_command(hostname, username, password, command):
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(hostname, username=username, password=password, timeout=10)
        stdin, stdout, stderr = client.exec_command(command)
        out = stdout.read().decode('utf-8')
        err = stderr.read().decode('utf-8')
        return out, err
    except Exception as e:
        return "", str(e)
    finally:
        client.close()

if __name__ == "__main__":
    host = "160.187.147.89"
    user = "root"
    pw = "LeLuongVinh@02022022@VinH"
    
    # Force disable display_errors in PHP-FPM
    checks = [
        "echo 'php_admin_flag[display_errors] = off' >> /etc/php/8.4/fpm/pool.d/www.conf",
        "systemctl restart php8.4-fpm",
        "wp --allow-root --path=/var/www/azevent.vn/public_html cache flush"
    ]
    
    for cmd in checks:
        print(f"--- Running: {cmd} ---")
        out, err = run_ssh_command(host, user, pw, cmd)
        if out: print(out)
        if err: print(f"Error: {err}")
        print("\n")
