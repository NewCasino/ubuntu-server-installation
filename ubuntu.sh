#!/bin/bash
ROOT_UID=0

if [ $UID != $ROOT_UID ]; then
    echo "You don't have sufficient privileges to run this script."
    exit 1
fi

while [[ true ]]
do
	echo -n "create mysql root password (must be at least 8 characters): "
	read -s rootPassword
	echo ""
	l=${#rootPassword}
	if [[ $l -lt 8 ]]
	then
		continue
	fi
	break
done

while [[ true ]]
do
	echo -n "create mysql user (must be at least 3 characters)[Lower case only]: "
	read dbUser
	dbUser2="$(tr [A-Z] [a-z] <<< "$dbUser")"
	l=${#dbUser2}
	if [ $l -lt 3 -o $dbUser2 == "root" ]
	then
		continue
	fi
	break
done

while [[ true ]]
do
	echo -n "create mysql $dbUser2 password (must be at least 8 characters): "
	read -s userPassword
	echo ""
	l=${#userPassword}
	if [[ $l -lt 8 ]]
	then
		continue
	fi
	break
done

apt-get update
apt-get upgrade -y

echo "LC_ALL=en_US.UTF-8" >> /etc/default/locale
locale-gen en_US.UTF-8

# Set The Timezone to UTC
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

relese=$(lsb_release -r | awk '{print $2}')
relese=${relese%.*}

# Add repositories
if [[ "$relese" -lt "16" ]] 
then
	apt-add-repository ppa:nginx/stable -y
	apt-add-repository ppa:rwky/redis -y
	apt-add-repository ppa:chris-lea/node.js -y
	apt-add-repository ppa:ondrej/php -y
	apt-get update
fi

# Set The Hostname If Necessary
echo "Server" > /etc/hostname
sed -i 's/127\.0\.0\.1.*localhost/127.0.0.1	Server localhost/' /etc/hosts
hostname Server



# Setup Unattended Security Upgrades
codename=$(lsb_release -c | awk '{print $2}')
cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
	"Ubuntu $codename-security";
};
Unattended-Upgrade::Package-Blacklist {
	//
};
EOF

cat > /etc/apt/apt.conf.d/10periodic << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

apt-get update

# Base Packages
apt-get install -y software-properties-common curl git mcrypt openssl build-essential dos2unix fail2ban \
gcc libmcrypt4 libpcre3-dev make python3-dev python-pip re2c supervisor unattended-upgrades whois nano ufw unzip

# Copy Github And Bitbucket Public Keys Into Known Hosts File
ssh-keyscan -H github.com >> /home/ubuntu/.ssh/known_hosts
ssh-keyscan -H bitbucket.org >> /home/ubuntu/.ssh/known_hosts

# Install Python Httpie
pip install httpie

# Setup UFW Firewall
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

# Install PHP 7 packages
apt-get install -y php7.0 php7.0-cli php7.0-dev php7.0-common php7.0-curl php7.0-gd php7.0-imap \
php7.0-gmp php7.0-json php7.0-mbstring php7.0-mcrypt php7.0-mysql php7.0-pspell php7.0-readline \
php7.0-tidy php7.0-zip php-pear php-imagick

# Install Nginx & PHP-FPM
sudo apt-get install -y nginx php7.0-fpm

# PHP CLI configuration
sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/7.0/cli/php.ini
sed -i "s/display_errors = .*/display_errors = On/" /etc/php/7.0/cli/php.ini
sed -i "s/memory_limit = .*/memory_limit = 512M/" /etc/php/7.0/cli/php.ini
sed -i "s/;date.timezone.*/date.timezone = UTC/" /etc/php/7.0/cli/php.ini

# PHP-FPM Settings
sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/7.0/fpm/php.ini
sed -i "s/display_errors = .*/display_errors = On/" /etc/php/7.0/fpm/php.ini
sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php/7.0/fpm/php.ini
sed -i "s/memory_limit = .*/memory_limit = 512M/" /etc/php/7.0/fpm/php.ini
sed -i "s/;date.timezone.*/date.timezone = UTC/" /etc/php/7.0/fpm/php.ini
sed -i "s/\;session.save_path = .*/session.save_path = \"\/var\/lib\/php\/sessions\"/" /etc/php/7.0/fpm/php.ini

# Configure Nginx & PHP-FPM
sed -i "s/# server_names_hash_bucket_size.*/server_names_hash_bucket_size 64;/" /etc/nginx/nginx.conf
sed -i "s/;listen\.mode.*/listen.mode = 0666/" /etc/php/7.0/fpm/pool.d/www.conf
sed -i "s/;request_terminate_timeout.*/request_terminate_timeout = 60/" /etc/php/7.0/fpm/pool.d/www.conf
sed -i "s/worker_processes.*/worker_processes auto;/" /etc/nginx/nginx.conf
sed -i "s/# multi_accept.*/multi_accept on;/" /etc/nginx/nginx.conf

# Enable PHP-FPM in Nginx default
sed -i "s/index.nginx-debian.html/index.php/" /etc/nginx/sites-available/default
sed -i -E "s/#(location.*php.*)/\1/" /etc/nginx/sites-available/default
sed -i -E "s/#(.+include snippets.*php.*)/\1/" /etc/nginx/sites-available/default
sed -i -E "s/#(.+fastcgi_pass.*fpm.sock.*)/\1\n\t}/" /etc/nginx/sites-available/default

# Install A Catch All Server
cat > /etc/nginx/sites-available/catch-all << EOF
server {
	return 404;
}
EOF

ln -s /etc/nginx/sites-available/catch-all /etc/nginx/sites-enabled/catch-all

# Restart Nginx & PHP-FPM Services
service php7.0-fpm restart
service nginx restart

# Install NodeJs
apt-get install -y nodejs
apt-get install -y npm

npm install -g pm2
npm install -g gulp

# Install Composer
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# Set The Automated Root Password
debconf-set-selections <<< "mariadb-server-10.0 mysql-server/root_password password $rootPassword"
debconf-set-selections <<< "mariadb-server-10.0 mysql-server/root_password_again password $rootPassword"

# Install MariaDB
apt-get install -y mariadb-server-10.0 mariadb-client-10.0

myip="$(dig +short myip.opendns.com @resolver1.opendns.com)"

# Configure Access Permissions For Root & Web User
sed -i '/^bind-address/s/bind-address.*=.*/bind-address = */' /etc/mysql/my.cnf
mysql --user="root" --password="$rootPassword" -e "GRANT ALL ON *.* TO root@'$myip' IDENTIFIED BY '$rootPassword';"
mysql --user="root" --password="$rootPassword" -e "GRANT ALL ON *.* TO root@'%' IDENTIFIED BY '$rootPassword';"
service mysql restart

mysql --user="root" --password="$rootPassword" -e "CREATE USER '$dbUser2'@'$myip' IDENTIFIED BY '$userPassword';"
mysql --user="root" --password="$rootPassword" -e "GRANT ALL ON *.* TO '$dbUser2'@'$myip' IDENTIFIED BY '$userPassword' WITH GRANT OPTION;"
mysql --user="root" --password="$rootPassword" -e "GRANT ALL ON *.* TO '$dbUser2'@'%' IDENTIFIED BY '$userPassword' WITH GRANT OPTION;"
mysql --user="root" --password="$rootPassword" -e "FLUSH PRIVILEGES;"

mysql --user="root" --password="$rootPassword" -e "CREATE DATABASE web;"

# Install PhpMyAdmin
echo "phpmyadmin phpmyadmin/internal/skip-preseed boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect" | debconf-set-selections
echo "phpmyadmin phpmyadmin/dbconfig-install boolean false" | debconf-set-selections
apt-get install -y phpmyadmin

# Install & Configure Redis Server
apt-get install -y redis-server
sed -i 's/bind 127.0.0.1/bind 0.0.0.0/' /etc/redis/redis.conf
service redis-server restart

apt-get clean -y
apt-get autoclean -y
apt-get autoremove -y

# Restart all services
service php7.0-fpm restart
service nginx restart
service mysql restart
service redis-server restart

echo "Installation finished."
echo "DB login details:"
echo " -> DB name: web"
echo " -> DB username: $dbUser2"
echo " -> DB password: $userPassword"

echo ""
echo "Enjoy :)"
