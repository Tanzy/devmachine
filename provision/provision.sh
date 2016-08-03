#!/bin/bash
#
# provision.sh
#
# This file is specified in Vagrantfile and is loaded by Vagrant as the primary
# provisioning script whenever the commands `vagrant up`, `vagrant provision`,
# or `vagrant reload` are used. It provides all of the default packages and
# configurations included with Varying Vagrant Vagrants.

# By storing the date now, we can calculate the duration of provisioning at the
# end of this script.
start_seconds="$(date +%s)"

# PACKAGE INSTALLATION
#
# Build a bash array to pass all of the packages we want to install to a single
# apt-get command. This avoids doing all the leg work each time a package is
# set to install. It also allows us to easily comment out or add single
# packages. We set the array as empty to begin with so that we can append
# individual packages to it as required.
apt_package_install_list=()

# Start with a bash array containing all packages we want to install in the
# virtual machine. We'll then loop through each of these and check individual
# status before adding them to the apt_package_install_list array.
apt_package_check_list=(

  # Our base packages for php5
  php5
  php5-cli

  # Common and dev packages for php
  php5-common
  php5-dev

  # Extra PHP modules that we find useful
  php5-memcache
  php5-imagick
  php5-xdebug
  php5-mcrypt
  php5-mysql
  php5-imap
  php5-curl
  php-pear
  php5-gd
  php-apc
  php5-cgi

  # Dependencies for building PHP versions with phpbrew
  autoconf
  automake
  libcurl3-openssl-dev
  build-essential
  libxslt1-dev
  re2c
  libxml2
  libxml2-dev
  bison
  libbz2-dev
  libreadline-dev
  libfreetype6
  libfreetype6-dev
  libpng12-0
  libpng12-dev
  libjpeg-dev
  libjpeg8-dev
  libjpeg8
  libgd-dev
  libgd3
  libxpm4
  libltdl7
  libltdl-dev
  libssl-dev
  openssl
  libgettextpo-dev
  libgettextpo0
  libicu-dev
  libmhash-dev
  libmhash2
  libmcrypt-dev
  libmcrypt4
  libmagickwand-dev
  libmagickcore-dev

  # Apache is installed as the default web server
	apache2-mpm-prefork
  apache2-dev
	libapache2-mod-fastcgi
  libapache2-mod-php5

  # Memcached is made available for object caching
  memcached

  # MySQL is the default database
  mysql-server
  mysql-client
  libmysqlclient-dev
  libmysqld-dev

  # Other packages that come in handy
  imagemagick
  subversion
  git-core
  zip
  unzip
  ngrep
  curl
  make
  vim
  colordiff
  postfix

  # NTP service to keep clock current
  ntp

  # Req'd for i18n tools
  gettext

  # Req'd for Webgrind
  graphviz

  # Dos2unix
  # Allows conversion of DOS style line endings to something we'll have less
  # trouble with in Linux.
  dos2unix

  # Mailcatcher dependency
  libsqlite3-dev
)

### FUNCTIONS

network_detection() {
  # Network Detection
  #
  # Make an HTTP request to google.com to determine if outside access is available
  # to us. If 3 attempts with a timeout of 5 seconds are not successful, then we'll
  # skip a few things further in provisioning rather than create a bunch of errors.
  if [[ "$(wget --tries=3 --timeout=5 --spider http://google.com 2>&1 | grep 'connected')" ]]; then
    echo "Network connection detected..."
    ping_result="Connected"
  else
    echo "Network connection not detected. Unable to reach google.com..."
    ping_result="Not Connected"
  fi
}

network_check() {
  network_detection
  if [[ ! "$ping_result" == "Connected" ]]; then
    echo -e "\nNo network connection available, skipping package installation"
    exit 0
  fi
}

profile_setup() {
  # Copy custom dotfiles and bin file for the vagrant user from local
  rsync -rvzh "/srv/config/bash_profile" "/home/vagrant/.bash_profile"
  rsync -rvzh "/srv/config/bash_aliases" "/home/vagrant/.bash_aliases"
  rsync -rvzh "/srv/config/vimrc" "/home/vagrant/.vimrc"

  if [[ ! -d "/home/vagrant/.subversion" ]]; then
    mkdir "/home/vagrant/.subversion"
  fi

  rsync -rvzh "/srv/config/subversion-servers" "/home/vagrant/.subversion/servers"

  if [[ ! -d "/home/vagrant/bin" ]]; then
    mkdir "/home/vagrant/bin"
  fi

  rsync -rvzh --delete "/srv/config/homebin/" "/home/vagrant/bin/"
  chmod +x /home/vagrant/bin/*

  echo " * /srv/config/bash_profile                        -> /home/vagrant/.bash_profile"
  echo " * /srv/config/bash_aliases                        -> /home/vagrant/.bash_aliases"
  echo " * /srv/config/vimrc                               -> /home/vagrant/.vimrc"
  echo " * /srv/config/subversion-servers                  -> /home/vagrant/.subversion/servers"
  echo " * /srv/config/homebin                             -> /home/vagrant/bin"

  # If a bash_prompt file exists in the basebox config/ directory, copy to the VM.
  if [[ -f "/srv/config/bash_prompt" ]]; then
    rsync -rvzh "/srv/config/bash_prompt" "/home/vagrant/.bash_prompt"
    echo " * /srv/config/bash_prompt                          -> /home/vagrant/.bash_prompt"
  fi
}

package_check() {
  # Loop through each of our packages that should be installed on the system. If
  # not yet installed, it should be added to the array of packages to install.
  local pkg
  local package_version

  for pkg in "${apt_package_check_list[@]}"; do
    package_version=$(dpkg -s "${pkg}" 2>&1 | grep 'Version:' | cut -d " " -f 2)
    if [[ -n "${package_version}" ]]; then
      space_count="$(expr 20 - "${#pkg}")" #11
      pack_space_count="$(expr 30 - "${#package_version}")"
      real_space="$(expr ${space_count} + ${pack_space_count} + ${#package_version})"
      printf " * $pkg %${real_space}.${#package_version}s ${package_version}\n"
    else
      echo " *" $pkg [not installed]
      apt_package_install_list+=($pkg)
    fi
  done
}

package_install() {
  package_check

  # MySQL
  #
  # Use debconf-set-selections to specify the default password for the root MySQL
  # account. This runs on every provision, even if MySQL has been installed. If
  # MySQL is already installed, it will not affect anything.
  echo mysql-server mysql-server/root_password password "root" | debconf-set-selections
  echo mysql-server mysql-server/root_password_again password "root" | debconf-set-selections

  # Postfix
  #
  # Use debconf-set-selections to specify the selections in the postfix setup. Set
  # up as an 'Internet Site' with the host name 'basebox'. Note that if your current
  # Internet connection does not allow communication over port 25, you will not be
  # able to send mail, even with postfix installed.
  echo postfix postfix/main_mailer_type select Internet Site | debconf-set-selections
  echo postfix postfix/mailname string basebox | debconf-set-selections

  # Disable ipv6 as some ISPs/mail servers have problems with it
  echo "inet_protocols = ipv4" >> "/etc/postfix/main.cf"

  # Provide our custom apt sources before running `apt-get update`
  ln -sf /srv/config/apt-sources.list /etc/apt/sources.list.d/basebox-sources.list
  echo "Linked custom apt sources"

  if [[ ${#apt_package_install_list[@]} = 0 ]]; then
    echo -e "No apt packages to install.\n"
  else
    # Update all of the package references before installing anything
    echo "Running apt-get update..."
    apt-get update -y

    # Install required packages
    echo "Installing apt-get packages..."
    apt-get install -y ${apt_package_install_list[@]}

    # Clean up apt caches
    apt-get clean
  fi
}

tools_setup() {

  # npm
  #
  # Make sure we have the latest npm version and the update checker module
  sudo -i -u vagrant npm install -g npm
  sudo -i -u vagrant npm install -g npm-check-updates

  # xdebug
  #
  # XDebug 2.2.3 is provided with the Ubuntu install by default. The PECL
  # installation allows us to use a later version. Not specifying a version
  # will load the latest stable.
  pecl install xdebug

  # ack-grep
  #
  # Install ack-rep directory from the version hosted at beyondgrep.com as the
  # PPAs for Ubuntu Precise are not available yet.
  if [[ -f /usr/bin/ack ]]; then
    echo "ack-grep already installed"
  else
    echo "Installing ack-grep as ack"
    curl -s http://beyondgrep.com/ack-2.14-single-file > "/usr/bin/ack" && chmod +x "/usr/bin/ack"
  fi

  # Composer
  #
  # Install Composer if it is not yet available.
  if [[ ! -n "$(composer --version --no-ansi | grep 'Composer version')" ]]; then
    echo "Installing Composer..."
    curl -sS "https://getcomposer.org/installer" | php
    chmod +x "composer.phar"
    mv "composer.phar" "/usr/local/bin/composer"
  fi

  if [[ -f /vagrant/provision/github.token ]]; then
    ghtoken=`cat /vagrant/provision/github.token`
    composer config --global github-oauth.github.com $ghtoken
    echo "Your personal GitHub token is set for Composer."
  fi

  # Update both Composer and any global packages. Updates to Composer are direct from
  # the master branch on its GitHub repository.
  if [[ -n "$(composer --version --no-ansi | grep 'Composer version')" ]]; then
    echo "Updating Composer..."
    COMPOSER_HOME=/usr/local/src/composer composer self-update
    COMPOSER_HOME=/usr/local/src/composer composer -q global require --no-update phpunit/phpunit:4.8.*
    COMPOSER_HOME=/usr/local/src/composer composer -q global require --no-update phpunit/php-invoker:1.1.*
    COMPOSER_HOME=/usr/local/src/composer composer -q global require --no-update mockery/mockery:0.9.*
    COMPOSER_HOME=/usr/local/src/composer composer -q global require --no-update d11wtq/boris:v1.0.8
    COMPOSER_HOME=/usr/local/src/composer composer -q global config bin-dir /usr/local/bin
    COMPOSER_HOME=/usr/local/src/composer composer global update
  fi

  # Grunt
  #
  # Install or update Grunt based on current state.
  if [[ "$(grunt --version)" ]]; then
    echo "Updating Grunt CLI..."
    sudo -i -u vagrant npm update -g grunt-cli &>/dev/null
  else
    echo "Installing Grunt CLI..."
    sudo -i -u vagrant npm install -g grunt-cli &>/dev/null
  fi

  # Bower
  #
  # Install or update Bower based on current state.
  if [[ "$(bower --version)" ]]; then
    echo "Updating Bower..."
    sudo -i -u vagrant npm update -g bower &>/dev/null
  else
    echo "Installing Bower..."
    sudo -i -u vagrant npm install -g bower &>/dev/null
  fi

  # Sympm
  #
  # Install or update Sympm based on current state.
  if [[ "$(sympm --version)" ]]; then
    echo "Updating Sympm..."
    sudo -i -u vagrant npm update -g sympm &>/dev/null
  else
    echo "Installing Sympm..."
    sudo -i -u vagrant npm install -g sympm &>/dev/null
  fi

  # Graphviz
  #
  # Set up a symlink between the Graphviz path defined in the default Webgrind
  # config and actual path.
  echo "Adding graphviz symlink for Webgrind..."
  ln -sf "/usr/bin/dot" "/usr/local/bin/dot"
}

node_setup() {
  # NVM
  #
  # Installs NVM. NVM allows us to install the current version of Node.
  if [[ "$(nvm --version)" ]]; then
    echo "Updating NVM"
  else
    echo "Installing NVM from source"
    echo -e "\n[[ -e ~/.nvm/nvm.sh ]] && source ~/.nvm/nvm.sh" >> ~vagrant/.bash_profile
  fi

  # Installing and updating are handled within the install script
  curl -L -O https://raw.githubusercontent.com/creationix/nvm/v0.31.0/install.sh
  sudo -i -u vagrant bash install.sh
  rm install.sh

  source "~vagrant/.nvm/nvm.sh"

  # Install Node stable
  echo "Installing Node stable"
  sudo -i -u vagrant nvm install node
  sudo -i -u vagrant nvm alias default node
}

apache_setup() {
  # Used to to ensure proper services are started on `vagrant up`
  rsync -rvzh /srv/config/init/basebox-start.conf /etc/init/basebox-start.conf

  echo " * /srv/config/init/basebox-start.conf                -> /etc/init/basebox-start.conf"

  # If a custom httpd.conf file is not found, create an empty one
  if [[ ! -f "/srv/config/apache-config/httpd.conf" ]]; then
    touch "/srv/config/apache-config/httpd.conf"
  fi

  if [[ ! -d "/etc/apache2/custom-sites" ]]; then
    mkdir /etc/apache2/custom-sites
  fi

  # Disable default site
  a2dissite 000-default.conf

  # Copy Apache configuration from local
  rsync -rvzh "/srv/config/apache-config/apache2.conf" "/etc/apache2/apache2.conf"
  rsync -rvzh "/srv/config/apache-config/httpd.conf" "/etc/apache2/httpd.conf"
  rsync -rvzh --delete "/srv/config/apache-config/sites-available/" "/etc/apache2/sites-available/"

  echo " * /srv/config/apache-config/apache2.conf         -> /etc/apache2/apache2.conf"
  echo " * /srv/config/apache-config/httpd.conf           -> /etc/apache2/httpd.conf"
  echo " * /srv/config/apache-config/available-sites/     -> /etc/apache2/availablecustom-sites/"
  
  echo " "
  echo "Enable Custom Default Site"
  a2ensite default.conf 

  # Configure Apache
  a2enmod actions fastcgi alias

  # Enable mod_rewrite
  a2enmod rewrite

  # Enable SSL
  a2enmod ssl
  #a2ensite default-ssl.conf

  # Allow phpbrew to access apache files
  chmod -R oga+rw /usr/lib/apache2/modules
  chmod -R oga+rw /etc/apache2
}

php_setup() {
  # Make sure these directories exist
  mkdir -p "/etc/php5/apache2/custom-conf.d/"

  # Copy php configuration from local
  rsync -rvzh "/srv/config/php5-config/php-custom.ini" "/etc/php5/apache2/custom-conf.d/php-custom.ini"
  rsync -rvzh "/srv/config/php5-config/opcache.ini" "/etc/php5/apache2/custom-conf.d/opcache.ini"
  rsync -rvzh "/srv/config/php5-config/xdebug.ini" "/etc/php5/apache2/custom-conf.d/xdebug.ini"

  # Find the path to Xdebug and prepend it to xdebug.ini
  XDEBUG_PATH=$(find /usr -name 'xdebug.so' | head -1)
  sed -i "1izend_extension=\"$XDEBUG_PATH\"" "/etc/php5/mods-available/xdebug.ini"

  echo " * /srv/config/php5-config/php-custom.ini         -> /etc/php5/apache2/custom-conf.d/php-custom.ini"
  echo " * /srv/config/php5-config/opcache.ini            -> /etc/php5/apache2/custom-conf.d/opcache.ini"
  echo " * /srv/config/php5-config/xdebug.ini             -> /etc/php5/apache2/custom-conf.d/xdebug.ini"

  # Copy memcached configuration from local
  rsync -rvzh "/srv/config/memcached-config/memcached.conf" "/etc/memcached.conf"
  echo " * /srv/config/memcached-config/memcached.conf    -> /etc/memcached.conf"

  # phpbrew
  #
  # Install or update phpbrew based on current state.
  if [[ "$(phpbrew --version)" ]]; then
    # Update as root user
    echo "Updating phpbrew..."
    phpbrew self-update
  else
    echo "Installing phpbrew..."
    curl -L -O "https://github.com/phpbrew/phpbrew/raw/master/phpbrew"
    chmod +x "phpbrew"
    mv "phpbrew" "/usr/local/bin/phpbrew"
    # Initialize as vagrant user
    echo "Initializing phpbrew..."
    sudo -i -u vagrant phpbrew init
  fi

  # php-switch
  #
  # Install php-switch helper.
  if [[ ! -f "/usr/local/bin/php-switch" ]]; then
    echo "Installing php-switch..."
    cat > /usr/local/bin/php-switch <<'EOT'
#!/usr/bin/env bash
VERSION="$1"
SOFILE="/usr/lib/apache2/modules/libphp$VERSION.so"
CONFFILE="/etc/apache2/mods-available/php5.load"

if [[ -z "$VERSION" ]]; then
  echo "No PHP version specified"
  echo "Usage: php-switch <version> [-y]"
  echo "   -y: answer yes to all prompts"
  sudo -E -i -u vagrant phpbrew list
  exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid PHP version: $VERSION (should be x.x.x)"
  sudo -E -i -u vagrant phpbrew known
  exit 1
fi

if [[ ! "$VERSION" =~ ^5 ]]; then
  echo "Right now, only PHP version 5.x is supported."
  echo "Do you know how to configure PHP 7.x (or older versions of PHP) using"
  echo "PHPBrew? Help out by submitting a pull request at:"
  echo "https://github.com/ezekg/theme-juice-basebox"
  exit 1
fi

if [[ ! -f "$SOFILE" ]]; then
  echo "PHP version $VERSION is not installed"

  if [[ "${@: -1}" =~ ^-y$ ]]; then
    REPLY=y
  else
    read -p "Do you want to install it? (y/N) " -r
  fi

  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    echo "Installing PHP version $VERSION..."
    sudo -E -i -u vagrant phpbrew install "php-$VERSION" +default +mysql +debug +iconv +apxs2=/usr/bin/apxs2 -- --with-mysql-sock=/var/run/mysqld/mysqld.sock --with-config-file-scan-dir=/etc/php5/apache2/custom-conf.d/
  else
    exit 0
  fi
fi

sudo -E su vagrant <<END
  source ~vagrant/.phpbrew/bashrc

  echo "Switching PHP version to $VERSION..."
  phpbrew switch "$VERSION"

  echo "Installing PHP extensions for version $VERSION..."
  phpbrew ext install openssl || echo "Failed to install openssl"
  phpbrew ext install memcache || echo "Failed to install memcache"
  phpbrew ext install imagick || echo "Failed to install imagick"
  phpbrew ext install xdebug && phpbrew ext disable xdebug || echo "Failed to install xdebug"
END

if [[ -f "$SOFILE" ]]; then
  echo "Updating contents of $CONFFILE to load PHP version $VERSION..."
  echo "LoadModule php5_module $SOFILE" > "$CONFFILE"
else
  echo "Could not locate $SOFILE"
  echo "Failed to fully install PHP version $VERSION"
  exit 1
fi

echo "Restarting Apache..."
sudo service apache2 restart
EOT
    chmod +x "/usr/local/bin/php-switch"
    echo -e "\n[[ -e ~/.phpbrew/bashrc ]] && source ~/.phpbrew/bashrc" >> ~vagrant/.bash_profile
  fi
}

mysql_setup() {
  # If MySQL is installed, go through the various imports and service tasks.
  local exists_mysql

  exists_mysql="$(service mysql status)"
  if [[ "mysql: unrecognized service" != "${exists_mysql}" ]]; then
    echo -e "\nSetup MySQL configuration file links..."

    # Copy mysql configuration from local
    rsync -rvzh "/srv/config/mysql-config/my.cnf" "/etc/mysql/my.cnf"
    rsync -rvzh "/srv/config/mysql-config/root-my.cnf" "/home/vagrant/.my.cnf"

    echo " * /srv/config/mysql-config/my.cnf                 -> /etc/mysql/my.cnf"
    echo " * /srv/config/mysql-config/root-my.cnf            -> /home/vagrant/.my.cnf"

    # MySQL gives us an error if we restart a non running service, which
    # happens after a `vagrant halt`. Check to see if it's running before
    # deciding whether to start or restart.
    if [[ "mysql stop/waiting" == "${exists_mysql}" ]]; then
      echo "service mysql start"
      service mysql start
      else
      echo "service mysql restart"
      service mysql restart
    fi

    # IMPORT SQL
    #
    # Create the databases (unique to system) that will be imported with
    # the mysqldump files located in database/backups/
    if [[ -f "/srv/database/init-custom.sql" ]]; then
      mysql -u "root" -p"root" < "/srv/database/init-custom.sql"
      echo -e "\nInitial custom MySQL scripting..."
    else
      echo -e "\nNo custom MySQL scripting found in database/init-custom.sql, skipping..."
    fi

    # Setup MySQL by importing an init file that creates necessary
    # users and databases that our vagrant setup relies on.
    mysql -u "root" -p"root" < "/srv/database/init.sql"
    echo "Initial MySQL prep..."

    # Process each mysqldump SQL file in database/backups to import
    # an initial data set for MySQL.
    "/srv/database/import-sql.sh"
  else
    echo -e "\nMySQL is not installed. No databases imported."
  fi
}

rvm_setup() {
  # RVM
  #
  # Installs RVM. RVM allows us to install the current version of Ruby.
  local pkg

  rvm_version="$(/usr/bin/env rvm --silent --version 2>&1 | grep 'rvm ' | cut -d " " -f 2)"
  if [[ -n "${rvm_version}" ]]; then
    pkg="RVM"
    space_count="$(( 20 - ${#pkg}))" #11
    pack_space_count="$(( 30 - ${#rvm_version}))"
    real_space="$(( ${space_count} + ${pack_space_count} + ${#rvm_version}))"
    printf " * $pkg %${real_space}.${#rvm_version}s ${rvm_version}\n"
  else
    # RVM key D39DC0E3
    # Signatures introduced in 1.26.0
    gpg -q --no-tty --batch --keyserver "hkp://keyserver.ubuntu.com:80" --recv-keys D39DC0E3
    gpg -q --no-tty --batch --keyserver "hkp://keyserver.ubuntu.com:80" --recv-keys BF04FF17

    printf " * RVM [not installed]\n Installing from source"
    curl --silent -L "https://get.rvm.io" | bash -s stable --ruby
    source "/usr/local/rvm/scripts/rvm"
  fi

  # Install bundler gem
  gem install bundler
}

mailcatcher_setup() {
  # Mailcatcher
  #
  # Installs mailcatcher using RVM. RVM allows us to install all mailcatcher
  # dependencies reliably.
  local pkg

  mailcatcher_version="$(/usr/bin/env mailcatcher --version 2>&1 | grep 'mailcatcher ' | cut -d " " -f 2)"
  if [[ -n "${mailcatcher_version}" ]]; then
    pkg="Mailcatcher"
    space_count="$(( 20 - ${#pkg}))" #11
    pack_space_count="$(( 30 - ${#mailcatcher_version}))"
    real_space="$(( ${space_count} + ${pack_space_count} + ${#mailcatcher_version}))"
    printf " * $pkg %${real_space}.${#mailcatcher_version}s ${mailcatcher_version}\n"
  else
    echo " * Mailcatcher [not installed]"
    /usr/bin/env rvm default@mailcatcher --create do gem install mailcatcher --no-rdoc --no-ri
    /usr/bin/env rvm wrapper default@mailcatcher --no-prefix mailcatcher catchmail
  fi

  if [[ -f "/etc/init/mailcatcher.conf" ]]; then
    echo " *" Mailcatcher upstart already configured.
  else
    rsync -rvzh "/srv/config/init/mailcatcher.conf"  "/etc/init/mailcatcher.conf"
    echo " * /srv/config/init/mailcatcher.conf               -> /etc/init/mailcatcher.conf"
  fi

  if [[ -f "/etc/php5/mods-available/mailcatcher.ini" ]]; then
    echo " * Mailcatcher php already configured."
  else
    rsync -rvzh "/srv/config/php5-config/mailcatcher.ini" "/etc/php5/mods-available/mailcatcher.ini"
    echo " * /srv/config/php5-config/mailcatcher.ini     -> /etc/php5/mods-available/mailcatcher.ini"
  fi
}

services_restart() {
  # RESTART SERVICES
  #
  # Add the vagrant user to the www-data group so that it has better access
  # to PHP and Apache related files
  usermod -a -G www-data vagrant
  chown -R vagrant:www-data /tmp
  sed -i 's/APACHE_RUN_USER=www-data/APACHE_RUN_USER=vagrant/' /etc/apache2/envvars
  chown -R vagrant:www-data /var/lock/apache2/
  chown -R vagrant:www-data /var/lib/apache2/

  # Make sure the services we expect to be running are running.
  echo -e "\nRestart services..."
  a2enmod headers && service apache2 restart
  service memcached restart
  service mailcatcher restart

  # Disable PHP Xdebug module by default
  php5dismod xdebug

  # Enable PHP mcrypt module by default
  php5enmod mcrypt

  # Enable PHP mailcatcher sendmail settings by default
  php5enmod mailcatcher
}

wp_cli() {
  # WP-CLI Install
  if [[ ! -d "/srv/www/wp-cli" ]]; then
    echo -e "\nDownloading wp-cli, see http://wp-cli.org"
    git clone "https://github.com/wp-cli/wp-cli.git" "/srv/www/wp-cli"
    cd /srv/www/wp-cli
    composer install
  else
    echo -e "\nUpdating wp-cli..."
    cd /srv/www/wp-cli
    git pull --rebase origin master
    composer update
  fi
  # Link `wp` to the `/usr/local/bin` directory
  ln -sf "/srv/www/wp-cli/bin/wp" "/usr/local/bin/wp"
}

memcached_admin() {
  # Download and extract phpMemcachedAdmin to provide a dashboard view and
  # admin interface to the goings on of memcached when running
  if [[ ! -d "/srv/www/default/memcached-admin" ]]; then
    echo -e "\nDownloading phpMemcachedAdmin, see https://github.com/wp-cloud/phpmemcacheadmin"
    cd /srv/www/default
    wget -q -O phpmemcachedadmin.tar.gz "https://github.com/wp-cloud/phpmemcacheadmin/archive/1.2.2.1.tar.gz"
    tar -xf phpmemcachedadmin.tar.gz
    mv phpmemcacheadmin* memcached-admin
    rm phpmemcachedadmin.tar.gz
  else
    echo "phpMemcachedAdmin already installed."
  fi
}

opcached_status(){
  # Checkout Opcache Status to provide a dashboard for viewing statistics
  # about PHP's built in opcache.
  if [[ ! -d "/srv/www/default/opcache-status" ]]; then
    echo -e "\nDownloading Opcache Status, see https://github.com/rlerdorf/opcache-status/"
    cd /srv/www/default
    git clone "https://github.com/rlerdorf/opcache-status.git" opcache-status
  else
    echo -e "\nUpdating Opcache Status"
    cd /srv/www/default/opcache-status
    git pull --rebase origin master
  fi
}

webgrind_install() {
  # Webgrind install (for viewing callgrind/cachegrind files produced by
  # xdebug profiler)
  if [[ ! -d "/srv/www/default/webgrind" ]]; then
    echo -e "\nDownloading webgrind, see https://github.com/michaelschiller/webgrind.git"
    git clone "https://github.com/michaelschiller/webgrind.git" "/srv/www/default/webgrind"
  else
    echo -e "\nUpdating webgrind..."
    cd /srv/www/default/webgrind
    git pull --rebase origin master
  fi
}

phpmyadmin_setup() {
  # Download phpMyAdmin
  if [[ ! -d /srv/www/default/database-admin ]]; then
    echo "Downloading phpMyAdmin..."
    cd /srv/www/default
    wget -q -O phpmyadmin.tar.gz "https://files.phpmyadmin.net/phpMyAdmin/4.4.10/phpMyAdmin-4.4.10-all-languages.tar.gz"
    tar -xf phpmyadmin.tar.gz
    mv phpMyAdmin-4.4.10-all-languages database-admin
    rm phpmyadmin.tar.gz
  else
    echo "PHPMyAdmin already installed."
  fi
  rsync -rvzh "/srv/config/phpmyadmin-config/config.inc.php" "/srv/www/default/database-admin/"
  echo " * /srv/config/phpmyadmin-config/config.inc.php    -> /srv/www/default/database-admin/"
}



xo_install() {
  # Install xo
  if [[ ! -f "/usr/local/bin/xo" ]]; then
    echo "Installing xo (https://github.com/ezekg/xo)"
    curl -L -O https://github.com/ezekg/xo/releases/download/0.2.2/xo_0.2.2_linux_amd64.tar.gz
    tar -xvzf xo_0.2.2_linux_amd64.tar.gz
    rm xo_0.2.2_linux_amd64.tar.gz
    chmod +x xo_0.2.2_linux_amd64/xo
    mv xo_0.2.2_linux_amd64/xo /usr/local/bin/
    rm -rf xo_0.2.2_linux_amd64&
  fi
}



passenger_setup(){
  if [[ ! -f "/usr/bin/passenger-config" ]]; then
  
  # Install our PGP key and add HTTPS support for APT
  apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 561F9B9CAC40B2F7
  apt-get install -y apt-transport-https ca-certificates

  # Add our APT repository
  sh -c 'echo deb https://oss-binaries.phusionpassenger.com/apt/passenger trusty main > /etc/apt/sources.list.d/passenger.list'
  apt-get update

  # Install Passenger + Apache module
  apt-get install -y libapache2-mod-passenger
  
  # Enable Passenger
  a2enmod passenger
  # Restart Apache
  apache2ctl restart
  
  fi
  
  echo "Check Passenger command via 'passenger-config about ruby-command'"
  rm /vagrant/www/passanger.txt
   
  cat > /vagrant/www/passanger.txt <<'EOT'
  
  Sample apache2 config
  <VirtualHost *:80>
    ServerName yourserver.com

    # Tell Apache and Passenger where your app's 'public' directory is
    DocumentRoot /var/www/myapp/code/public

    PassengerRuby /path-to-ruby

    # Relax Apache security settings
    <Directory /var/www/myapp/code/public>
      Allow from all
      Options -MultiViews
      # Uncomment this if you're on Apache >= 2.4:
      #Require all granted
    </Directory>
</VirtualHost>
EOT
  
  passenger-config about ruby-command >> /vagrant/www/passanger.txt
  
}

elasticsearch_setup(){
  echo ">>> Checking for Elasticsearch"
	exists_elasticsearch="$(service elasticsearch status)"
	echo "${exists_elasticsearch}"
	if [[ " * elasticsearch is running" != "${exists_elasticsearch}" && " * elasticsearch is not running" != "${exists_elasticsearch}" ]]; then
		echo ">>> Installing Elasticsearch"
		
		# Set some variables
		ELASTICSEARCH_VERSION=2.0.0 # Check https://www.elastic.co/downloads/elasticsearch for latest version
		
		# Install prerequisite: Java
		# -qq implies -y --force-yes
		apt-get update
		apt-get install -qq openjdk-7-jre-headless
		
		wget --quiet https://download.elastic.co/elasticsearch/elasticsearch/elasticsearch-$ELASTICSEARCH_VERSION.deb
		dpkg -i elasticsearch-$ELASTICSEARCH_VERSION.deb
		rm elasticsearch-$ELASTICSEARCH_VERSION.deb
		
		cp /srv/config/elasticsearch-config/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml
		
		service elasticsearch restart
		
		# Configure to start up Elasticsearch automatically
		/usr/share/elasticsearch/bin/plugin install royrusso/elasticsearch-hq
		/usr/share/elasticsearch/bin/plugin install lmenezes/elasticsearch-kopf

	fi
  
  if [ ! -f /srv/kibana/bin/kibana ]; then
		# Install kibana
		echo "Installing Kibana..."
		mkdir -p /srv/kibana
		
		wget https://download.elastic.co/kibana/kibana/kibana-4.2.0-linux-x64.tar.gz
		
		tar xvf kibana-*.tar.gz
		
		cp -R kibana-4*/* /srv/kibana/
		
		rm -rf kibana-4*		
		
	fi
	
	if [ ! -f /etc/init.d/kibana ]; then
		cp /srv/config/elasticsearch-config/kibana /etc/init.d/kibana4
		# below is to fix the problem of CRLF (DOS format) to LF format
		perl -pi -e 's/\r\n/\n/g' /etc/init.d/kibana4
		chmod +x /etc/init.d/kibana4
		update-rc.d kibana4 defaults 99 10
	fi
}

rabbitMq_install() {
  # Install rabbitmq
  if [[ ! -f "/etc/default/rabbitmq-server" ]]; then
    echo "Installing RabbitMq"
    
    echo "Updating sources"
    sh -c 'echo deb http://www.rabbitmq.com/debian/ testing main >> /etc/apt/sources.list'
    sh -c 'echo deb http://packages.erlang-solutions.com/ubuntu trusty contrib >> /etc/apt/sources.list'

    echo "Adding verification key"
    wget -O- https://www.rabbitmq.com/rabbitmq-release-signing-key.asc |  apt-key add -
    wget -c -O- http://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc |  apt-key add -
    
    echo "Apt Update"
    apt-get update

    echo "Install Erlang"
    apt-get install erlang-base -y

    echo "Install RabbitMq"
    apt-get install -y rabbitmq-server

    rabbitmq-plugins enable rabbitmq_management

    echo "Add RabbitMq User"
    service rabbitmq-server restart
    rabbitmqctl add_user vagrant vagrant
    rabbitmqctl set_user_tags vagrant administrator
    rabbitmqctl set_permissions -p / vagrant ".*" ".*" ".*"

  fi
}


letsEncrypt_install() {
  if [[ ! -d "/srv/letsencrypt" ]]; then
      mkdir /srv/letsencrypt
  fi

  cd /srv/letsencrypt

  # Download and extract Lets Encrypt
  if [[ ! -f "/srv/letsencrypt/certbot-auto" ]]; then
    echo -e "\nDownloading LetsEncrypt Certbot"
    
    wget https://dl.eff.org/certbot-auto
    
  else
   
    echo "LetsEncrypt Certbot already installed."
   
  fi
  
  chmod a+x certbot-auto
  wget -O -  https://get.acme.sh | sh
  #./certbot-auto --apache --dry-run 

}

### SCRIPT
#set -xv

network_check

# Profile_setup
echo "Bash profile setup and directories"
profile_setup

network_check

# Package and Tools Install
echo " "
echo "Main packages check and install"
package_install

echo "Tool packages check and install"
xo_install
node_setup
tools_setup
apache_setup
rvm_setup
mailcatcher_setup
php_setup
services_restart
mysql_setup

passenger_setup

elasticsearch_setup

rabbitMq_install

network_check

# WP-CLI and debugging tools
echo " "
echo "Installing/updating wp-cli and debugging tools"
wp_cli
memcached_admin
opcached_status
webgrind_install
phpmyadmin_setup

network_check

#letsEncrypt_install
#network_check


#set +xv
# And it's done
end_seconds="$(date +%s)"
echo "-----------------------------"
echo "Provisioning complete in "$((${end_seconds} - ${start_seconds}))" seconds"
echo "For further setup instructions, visit http://basebox.dev"
