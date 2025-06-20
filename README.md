## Instalations

- bash <(curl -s https://raw.githubusercontent.com/adminizor/bash/refs/heads/master/Utils/Install.bash)
- bash <(curl -s https://raw.githubusercontent.com/adminizor/bash/refs/heads/master/PHP/8.2/Install.bash)

- /bin/php8.2 /usr/share/adminizor/artisan bash:setup-disk-quotas
- /bin/php8.2 /usr/share/adminizor/artisan bash:install-mysql --port=3306 --bind-address=0.0.0.0 --mysqlx-port=33060 --mysqlx-bind-address=0.0.0.0 --innodb-buffer-pool-size=4G
- /bin/php8.2 /usr/share/adminizor/artisan bash:install-nginx --ip=192.168.0.200 --port=80
