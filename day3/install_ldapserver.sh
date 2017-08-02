#!/bin/bash
slapd=/etc/openldap/slapd.d

#关闭防火墙和selinux
iptables -F
setenforce 0
#安装软件
yum install openldap-clients migrationtools openldap-servers openldap -y

#配置启动openldap
cat > /etc/openldap/slapd.conf <<EOF
include         /etc/openldap/schema/corba.schema
include         /etc/openldap/schema/core.schema
include         /etc/openldap/schema/cosine.schema
include         /etc/openldap/schema/duaconf.schema
include         /etc/openldap/schema/dyngroup.schema
include         /etc/openldap/schema/inetorgperson.schema
include         /etc/openldap/schema/java.schema
include         /etc/openldap/schema/misc.schema
include         /etc/openldap/schema/nis.schema
include         /etc/openldap/schema/openldap.schema
include         /etc/openldap/schema/pmi.schema
include         /etc/openldap/schema/ppolicy.schema
include         /etc/openldap/schema/collective.schema
allow bind_v2
pidfile         /var/run/openldap/slapd.pid
argsfile        /var/run/openldap/slapd.args
####  Encrypting Connections
TLSCACertificateFile /etc/pki/tls/certs/ca.crt
TLSCertificateFile /etc/pki/tls/certs/slapd.crt
TLSCertificateKeyFile /etc/pki/tls/certs/slapd.key
### Database Config###          
database config
rootdn "cn=admin,cn=config"
rootpw {SSHA}IeopqaxvZY1/I7HavmzRQ8zEp4vwNjmF
access to * by dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth manage by * break
### Enable Monitoring
database monitor
# allow only rootdn to read the monitor
access to * by dn.exact="cn=admin,cn=config" read by * none
EOF
# ---转换格式与修改权限
rm -rf /etc/openldap/slapd.d/*
slaptest -f /etc/openldap/slapd.conf -F $slapd
chown -R ldap:ldap $slapd
chmod -R 000 $slapd
chmod -R u+rwX $slapd

#生成密钥对 ( CA证书 ldap的密钥对)
chmod +x auto_mkcert.sh
./auto_mkcert.sh --create-ca-keys
./auto_mkcert.sh --create-ldap-keys
cd /etc/pki/CA
cp my-ca.crt /etc/pki/tls/certs/ca.crt
cp ldap_server.key /etc/pki/tls/certs/slapd.key
cp ldap_server.crt /etc/pki/tls/certs/slapd.crt

#生成数据库目录及DB_CONFIG文件
rm -rf /var/lib/ldap/*
chown ldap.ldap /var/lib/ldap
cp -p /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap. /var/lib/ldap/DB_CONFIG
systemctl start  slapd.service

#创建用户数据库
mkdir ~/ldif
cat ~/ldif/bdb.ldif <<EOF
dn: olcDatabase=bdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcBdbConfig
olcDatabase: {1}bdb
olcSuffix: dc=example,dc=org
olcDbDirectory: /var/lib/ldap
olcRootDN: cn=Manager,dc=example,dc=org
olcRootPW: redhat
olcLimits: dn.exact="cn=Manager,dc=example,dc=org" time.soft=unlimited time.hard=unlimited size.soft=unlimited size.hard=unlimited
olcDbIndex: uid pres,eq
olcDbIndex: cn,sn,displayName pres,eq,approx,sub
olcDbIndex: uidNumber,gidNumber eq
olcDbIndex: memberUid eq
olcDbIndex: objectClass eq
olcDbIndex: entryUUID pres,eq
olcDbIndex: entryCSN pres,eq
olcAccess: to attrs=userPassword by self write by anonymous auth by dn.children="ou=admins,dc=example,dc=org" write  by * none
olcAccess: to * by self write by dn.children="ou=admins,dc=example,dc=org" write by * read
EOF
#--导入dn: olcDatabase={2}bdb,cn=config 数据库
ldapadd -x -D "cn=admin,cn=config" -w config -f ~/ldif/bdb.ldif -h localhost
#通过ldap转换脚本来实现将系统用户转换成ldap用户
cd /usr/share/migrationtools/
sed 's#DEFAULT_MAIL_DOMAIN = "padl.com";#DEFAULT_MAIL_DOMAIN = "example.org";#' migrate_common.ph
sed 's#DEFAULT_BASE = "dc=padl,dc=com";#DEFAULT_MAIL_DOMAIN = "dc=example,dc=org";#' migrate_common.ph

#指定目录
mkdir /ldapuser
#通过http方式共享出ca.crt文件,通过nfs方式共享出用户家目录
yum -y install httpd nfs-utils
cp /etc/pki/tls/certs/ca.crt /var/www/html/
cat /etc/exports << EOF
/ldapuser       *(rw,async)
EOF
systemctl start httpd &> /dev/null
systemctl start httpd &> /dev/null
systemctl restart rpcbind &> /dev/null
systemctl restart nfs &> /dev/null

echo "导入数据密码为：redhat,请牢记"
echo 'Complete!'
