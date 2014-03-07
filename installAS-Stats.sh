yum install -y httpd httpd-devel php php-gd phpimap php-ldap php-odbc php-pear php-xml php-xmlrpc php-mcrypt curl curl-devel perl-libwwwperl libxml2 php-mbstring rrdtool perl-rrdtool
yum install -y jwhois
service iptables stop
service iptables status
chkconfig iptables off

mkdir /data
cd /data
git clone git://github.com/datatecuk/AS-Stats
mv /data/AS-Stats/ /data/as-stats
mkdir /data/as-stats/rrd
chmod 0777 /data/as-stats/rrd
mkdir /data/as-stats/www/asset
chmod 0777 /data/as-stats/www/asset
cp /data/as-stats/contrib/centos/as-stats /etc/rc.d/init.d/as-stats
chmod 0755 /etc/rc.d/init.d/as-stats
chmod 0777 /data/as-stats/bin/asstatd.pl
chmod 0777 /data/as-stats/bin/rrd-extractstats.pl
cp /data/as-stats/tools/add_ds.sh /data/as-stats/rrd/add_ds.sh
chmod 0777 /data/as-stats/rrd/add_ds.sh

echo "Alias /as-stats /data/as-stats/www
<Directory /data/as-stats/www/>
    DirectoryIndex index.php
    Options -Indexes
    AllowOverride all
    order allow,deny
    allow from all
    AddType application/x-httpd-php .php
    php_flag magic_quotes_gpc on
    php_flag track_vars on
</Directory>
" > /etc/httpd/conf.d/as-stats.conf

echo "<html>
<head>
<meta http-equiv=\"REFRESH\" content=\"0;URL=/as-stats/\">
</head>
<body>
</body>
</html>
" > /var/www/html/index.html

echo "*/5 * * * * root perl /data/as-stats/bin/rrd-extractstats.pl /data/as-stats/rrd /data/as-stats/conf/knownlinks /data/as-stats/asstats_day.txt  > /dev/null 2>&1
" > /etc/cron.d/as-stats

chkconfig httpd on
service httpd start
chkconfig as-stats on
service as-stats start
