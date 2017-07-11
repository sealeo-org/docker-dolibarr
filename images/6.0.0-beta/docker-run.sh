#!/bin/bash

usermod -u $WWW_USER_ID www-data
groupmod -g $WWW_GROUP_ID www-data

if [ ! -d /var/www/documents ]; then
  mkdir /var/www/documents
fi

chown -R www-data:www-data /var/www

if [ ! -f /usr/local/etc/php/php.ini ]; then
  cat <<EOF > /usr/local/etc/php/php.ini
date.timezone = $PHP_INI_DATE_TIMEZONE
sendmail_path = /usr/sbin/sendmail -t -i
EOF
fi

if [ ! -f /etc/mailname ]; then
  echo $MAIL_DOMAIN_NAME > /etc/mailname
fi

if [ ! -f /etc/exim4/update-exim4.conf.conf ]; then
  cat <<EOF > /etc/exim4/update-exim4.conf.conf
dc_eximconfig_configtype='internet'
dc_other_hostnames='${MAIL_DOMAIN_NAME}; localhost.localdomain; localhost'
dc_local_interfaces='127.0.0.1; ::1'
dc_readhost=''
dc_relay_domains=''
dc_minimaldns='false'
dc_relay_nets=''
dc_smarthost=''
CFILEMODE='644'
dc_use_split_config='false'
dc_hide_mailname='true'
dc_mailname_in_oh='true'
dc_localdelivery='mail_spool'
EOF

  service exim4 restart
fi

if [ ! -f /var/www/html/conf/conf.php ]; then
	cat <<EOF > /var/www/html/conf/conf.php
<?php
\$dolibarr_main_url_root='${DOLI_URL_ROOT}';
\$dolibarr_main_document_root='/var/www/html';
\$dolibarr_main_url_root_alt='/custom';
\$dolibarr_main_document_root_alt='/var/www/html/custom';
\$dolibarr_main_data_root='/var/www/documents';
\$dolibarr_main_db_host='${DOLI_DB_HOST}';
\$dolibarr_main_db_port='3306';
\$dolibarr_main_db_name='${DOLI_DB_NAME}';
\$dolibarr_main_db_prefix='llx_';
\$dolibarr_main_db_user='${DOLI_DB_USER}';
\$dolibarr_main_db_pass='${DOLI_DB_PASSWORD}';
\$dolibarr_main_db_type='mysqli';
EOF

	chown www-data:www-data /var/www/html/conf/conf.php
	chmod 400 /var/www/html/conf/conf.php
fi

if [ $DOLI_INSTALL_AUTO -eq 1 ]; then
  r=1
  while [ $r -ne 0 ]; do
    mysql -u $DOLI_DB_USER -p${DOLI_DB_PASSWORD} -h $DOLI_DB_HOST -e "status" > /dev/null 2>&1
    r=$?
    if [ $r -ne 0 ]; then
      echo "Waiting that SQL database is up..."
      sleep 2
    fi
  done

  mysql -u $DOLI_DB_USER -p${DOLI_DB_PASSWORD} -h $DOLI_DB_HOST $DOLI_DB_NAME -e "SELECT * FROM llx_const" > /dev/null 2>&1
  if [ $? -ne 0 ]; then

    for f in /var/www/html/install/mysql/tables/*.sql; do
      if [[ $f != *.key.sql ]]; then
        echo "Importing table from `basename $f`..."
        sed -i 's/--.*//g;' $f # remove all comment
        mysql -u $DOLI_DB_USER -p${DOLI_DB_PASSWORD} -h $DOLI_DB_HOST $DOLI_DB_NAME < $f
      fi
    done

    for f in /var/www/html/install/mysql/tables/*.key.sql; do
      echo "Importing table key from `basename $f`..."
      sed -i 's/--.*//g;' $f
      mysql -u $DOLI_DB_USER -p${DOLI_DB_PASSWORD} -h $DOLI_DB_HOST $DOLI_DB_NAME < $f > /dev/null 2>&1
    done

    for f in /var/www/html/install/mysql/functions/*.sql; do
      echo "Importing `basename $f`..."
      sed -i 's/--.*//g;' $f
      mysql -u $DOLI_DB_USER -p${DOLI_DB_PASSWORD} -h $DOLI_DB_HOST $DOLI_DB_NAME < $f > /dev/null 2>&1
    done

    for f in /var/www/html/install/mysql/data/*.sql; do
      echo "Importing data from `basename $f`..."
      sed -i 's/--.*//g;' $f
      mysql -u $DOLI_DB_USER -p${DOLI_DB_PASSWORD} -h $DOLI_DB_HOST $DOLI_DB_NAME < $f > /dev/null 2>&1
    done

    echo "Create SuperAdmin account ..."
    pass_crypted=`echo -n $DOLI_ADMON_PASSWORD | md5sum | awk '{print $1}'`
    mysql -u $DOLI_DB_USER -p${DOLI_DB_PASSWORD} -h $DOLI_DB_HOST $DOLI_DB_NAME -e "INSERT INTO llx_user (entity, login, pass_crypted, lastname, admin, statut) VALUES (0, '${DOLI_ADMIN_LOGIN}', '${pass_crypted}', 'SuperAdmin', 1, 1);" > /dev/null 2>&1

    echo "Set some default const ..."
    mysql -u $DOLI_DB_USER -p${DOLI_DB_PASSWORD} -h $DOLI_DB_HOST $DOLI_DB_NAME -e "DELETE FROM llx_const WHERE name='MAIN_VERSION_LAST_INSTALL';" > /dev/null 2>&1
    mysql -u $DOLI_DB_USER -p${DOLI_DB_PASSWORD} -h $DOLI_DB_HOST $DOLI_DB_NAME -e "DELETE FROM llx_const WHERE name='MAIN_NOT_INSTALLED';" > /dev/null 2>&1
    mysql -u $DOLI_DB_USER -p${DOLI_DB_PASSWORD} -h $DOLI_DB_HOST $DOLI_DB_NAME -e "DELETE FROM llx_const WHERE name='MAIN_LANG_DEFAULT';" > /dev/null 2>&1
    mysql -u $DOLI_DB_USER -p${DOLI_DB_PASSWORD} -h $DOLI_DB_HOST $DOLI_DB_NAME -e "INSERT INTO llx_const(name,value,type,visible,note,entity) values('MAIN_VERSION_LAST_INSTALL', '${DOLI_VERSION}', 'chaine', 0, 'Dolibarr version when install', 0);" > /dev/null 2>&1
    mysql -u $DOLI_DB_USER -p${DOLI_DB_PASSWORD} -h $DOLI_DB_HOST $DOLI_DB_NAME -e "INSERT INTO llx_const(name,value,type,visible,note,entity) VALUES ('MAIN_LANG_DEFAULT', 'auto', 'chaine', 0, 'Default language', 1);" > /dev/null 2>&1

    touch /var/www/documents/install.lock
    chown www-data:www-data /var/www/documents/install.lock
    chmod 400 /var/www/documents/install.lock
  fi
fi

exec apache2-foreground
