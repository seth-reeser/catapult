
# requirements to build php
sudo yum -y install \
gcc \
libxml2-devel \
libXpm-devel \
gmp-devel \
libicu-devel \
t1lib-devel \
aspell-devel \
openssl-devel \
bzip2-devel \
libcurl-devel \
libjpeg-devel \
libvpx-devel \
libpng-devel \
freetype-devel \
readline-devel \
libtidy-devel \
libxslt-devel \
libmcrypt-devel \
pcre-devel \
curl-devel \
mysql-devel \
ncurses-devel \
gettext-devel \
net-snmp-devel \
libevent-devel \
libtool-ltdl-devel \
libc-client-devel \
postgresql-devel \
bison \
gcc \
make

# clone the php project
if [ ! -d "/opt/source" ]; then
    sudo mkdir -p /opt/source
    cd /opt/source && git clone https://github.com/php/php-src.git
fi

# declare an array variable
declare -a php_versions=("5.5" "5.6")

# now loop through the above array
for php_version in "${php_versions[@]}"; do

    # checkout the php version
    cd /opt/source/php-src && git checkout "PHP-$php_version"

    # determine if php is built
    if [ ! -d "/opt/php-$php_version" ]; then

        # build the configuation file
        sudo ./buildconf --force

        # create our target directory
        sudo mkdir -p /opt/php-$php_version

        # create our build configuration
        ./configure \
        --prefix=/opt/php-$php_version \
        --with-pdo-pgsql \
        --with-zlib-dir \
        --with-freetype-dir \
        --enable-mbstring \
        --with-libxml-dir=/usr \
        --enable-soap \
        --enable-calendar \
        --with-curl \
        --with-mcrypt \
        --with-zlib \
        --with-gd \
        --with-pgsql \
        --disable-rpath \
        --enable-inline-optimization \
        --with-bz2 \
        --with-zlib \
        --enable-sockets \
        --enable-sysvsem \
        --enable-sysvshm \
        --enable-pcntl \
        --enable-mbregex \
        --with-mhash \
        --enable-zip \
        --with-pcre-regex \
        --with-mysql \
        --with-pdo-mysql \
        --with-mysqli \
        --with-png-dir=/usr \
        --enable-gd-native-ttf \
        --with-openssl \
        --with-fpm-user=nginx \
        --with-fpm-group=nginx \
        --with-libdir=lib64 \
        --enable-ftp \
        --with-imap \
        --with-imap-ssl \
        --with-kerberos \
        --with-gettext \
        --with-gd \
        --with-jpeg-dir=/usr/lib/ \
        --with-fpm-user=nginx \
        --with-fpm-group=nginx \
        --enable-fpm

        # clean out any make remenence
        make clean

        # make our package
        make

        # install our package
        make install

    fi

    # echo the php version
    /opt/php-$php_version/bin/php --version

    # copy over the default php-fpm config
    #sudo cp /opt/php-$php_version/etc/php-fpm.conf.default /opt/php-$php_version/etc/php-fpm.conf
    sudo cat > /opt/php-$php_version/etc/php-fpm.conf << EOF
[www]
user = nginx
group = nginx
listen = 127.0.0.1:90${php_version//.}
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
EOF

    # copy over the default php.ini
    sudo cp /opt/source/php-src/php.ini-production /opt/php-$php_version/lib/php.ini

    # start php-fpm on boot
    sudo cp /opt/source/php-src/sapi/fpm/init.d.php-fpm /etc/init.d/php$php_version-fpm

    # configure the correct permissions
    sudo chmod 755 /etc/init.d/php$php_version-fpm

    # start php-fpm
    sudo /etc/init.d/php$php_version-fpm start
    sudo /etc/init.d/php$php_version-fpm status

done
