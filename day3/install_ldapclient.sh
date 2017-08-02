#!/bin/bash

#获取LDAP服务器域名
read -p "请输入LDAP服务器域名地址： " ldap_domain
read -p "输入LDAP服务器IP地址：" ldap_ip
#关闭防火墙、selinux
setenforce 0
iptables -F

#安装软件
yum clean all &>/dev/null
yum makecache &>/dev/null
[ $? -ne 0 ] && echo "请先配置好安装源"
yum install openldap openldap-clients nss-pam-ldapd autofs -y

#通过证书连接ldap服务器
authconfig --enableldap --enableldapauth --ldapserver=${ldap_domain} --ldapbasedn="dc=example,dc=org" --enableldaptls --ldaploadcacert=http://${ldap_domain}/ca.crt  --update

#自动挂接用户家目录
echo "/ldapuser /etc/auto.ldap" >> /etc/auto.master
echo "*       -rw,soft,intr ${ldap_ip}:/ldapuser/&"
service autofs start
echo 'Complete!'
