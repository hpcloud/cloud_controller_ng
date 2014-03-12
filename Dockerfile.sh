# Script to install ccng and its dependencies into the docker image.

for DIR in `/bin/ls ext`; do
  ln -s `pwd`/ext/$DIR /s/code/
done

apt-get -qy update
# Runtime dependency of the librrd gem.
apt-get -qy install librrd4

# Capture install history for later removal
DPKG_LOG_LENGTH=`wc -l /var/log/dpkg.log`
apt-get -qy install build-essential

# For the librrd gem.
apt-get -qy install librrd-dev
# For nokogiri gem.
apt-get -qy install libxml2-dev libxslt-dev
# For mysql2 gem.
apt-get -qy install libmysqld-dev libmysqlclient-dev mysql-client
# For pg gem.
apt-get -qy install libpq-dev

/opt/rubies/current/bin/bundle install --without=test

apt-get -qy clean && apt-get -qy autoclean && apt-get -qy autoremove
DPKG_RECENT_LIST=`tail -n +$DPKG_LOG_LENGTH /var/log/dpkg.log | grep "\ install\ " | awk '{print $4}' | tr "\\n" " "`
apt-get -qyf remove $DPKG_RECENT_LIST
