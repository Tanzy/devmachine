#!/bin/bash

# basebox custom site import
echo " "
echo "basebox custom site import"

custom_basebox() {
  # Find new sites to setup.
  # Kill previously symlinked Apache configs
  # We can't know what sites have been removed, so we have to remove all
  # the configs and add them back in again.
  find /etc/apache2/custom-sites -name 'basebox-auto-*.conf' -exec rm {} \;

  # Look for site setup scripts
  for SITE_CONFIG_FILE in $(find /srv/www -maxdepth 5 -name 'basebox-init.sh'); do
    DIR="$(dirname "$SITE_CONFIG_FILE")"
    (
    cd "$DIR"
    source basebox-init.sh
    )
  done

  # Look for Apache vhost files, symlink them into the custom sites dir
  for SITE_CONFIG_FILE in $(find /srv/www -maxdepth 5 -name 'basebox-apache.conf'); do
    DEST_CONFIG_FILE=${SITE_CONFIG_FILE//\/srv\/www\//}
    DEST_CONFIG_FILE=${DEST_CONFIG_FILE//\//\-}
    DEST_CONFIG_FILE=${DEST_CONFIG_FILE/%-basebox-apache.conf/}
    DEST_CONFIG_FILE="basebox-auto-$DEST_CONFIG_FILE-$(md5sum <<< "$SITE_CONFIG_FILE" | cut -c1-32).conf"
    # We allow the replacement of the {basebox_path_to_folder} token with
    # whatever you want, allowing flexible placement of the site folder
    # while still having an Apache config which works.
    DIR="$(dirname "$SITE_CONFIG_FILE")"
    sed "s#{basebox_path_to_folder}#$DIR#" "$SITE_CONFIG_FILE" > "/etc/apache2/custom-sites/""$DEST_CONFIG_FILE"
  done

  # Parse any basebox-hosts file located in www/ or subdirectories of www/
  # for domains to be added to the virtual machine's host file so that it is
  # self aware.
  #
  # Domains should be entered on new lines.
  echo "Cleaning the virtual machine's /etc/hosts file..."
  sed -n '/# basebox-auto$/!p' /etc/hosts > /tmp/hosts
  mv /tmp/hosts /etc/hosts
  echo "Adding domains to the virtual machine's /etc/hosts file..."
  find /srv/www/ -maxdepth 5 -name 'basebox-hosts' | \
  while read hostfile; do
    while IFS='' read -r line || [ -n "$line" ]; do
      if [[ "#" != ${line:0:1} ]]; then
        if [[ -z "$(grep -q "^127.0.0.1 $line$" /etc/hosts)" ]]; then
          echo "127.0.0.1 $line # basebox-auto" >> "/etc/hosts"
          echo " * Added $line from $hostfile"
        fi
      fi
    done < "$hostfile"
  done
}

ssl_cert_setup() {
  echo "Adding self-signed SSL certs"  >> /srv/log/ssl-create.log
  sites=$(cat /etc/apache2/custom-sites/*.conf | xo '/\*:443.*?ServerName\s(www)?\.?([-.0-9A-Za-z]+)/$1?:www.$2/mis')
  echo "Sites = $sites"   >> /srv/log/ssl-create.log 
  # Install a cert for each domain
  for site in $sites; do
    if [[ $site =~ "localhost" ]] || [[ ! $site =~ ".dev" && ! $site =~ ".vm" ]] ; then
      echo "$site not valid " >> /srv/log/ssl-create.log
      continue
    fi

    domain=$(echo "$site" | sed "s/^www.//")

    if [[ -f "/etc/ssl/certs/$domain.pem" ]]; then
      echo " * Cert for $domain already exists" >> /srv/log/ssl-create.log
      continue
    fi

    openssl genrsa -des3 -passout pass:x -out "$domain.pass.key" 2048 &>/dev/null
    openssl rsa -passin pass:x -in "$domain.pass.key" -out "$domain.key" &>/dev/null
    rm "$domain.pass.key"
    openssl req -new -key "$domain.key" -out "$domain.csr" -subj "/C=US/ST=New York/L=New York City/O=Evil Corp/OU=IT Department/CN=$domain" &>/dev/null
    openssl x509 -req -days 365 -in "$domain.csr" -signkey "$domain.key" -out "$domain.pem" &>/dev/null

    mv "$domain.key" /etc/ssl/private/
    mv "$domain.pem" /etc/ssl/certs/
    rm "$domain.csr"

    echo " * Created cert for $domain"  >> /srv/log/ssl-create.log
  done
}


echo " "
echo "Setting up custom Websites"
custom_basebox

echo " "
echo "Installing/configuring SSL certs"
ssl_cert_setup