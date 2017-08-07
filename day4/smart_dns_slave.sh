#!/bin/bash

conf="/etc/named.conf"
TTL="TTL"
if [ ! -e $conf ];then
yum install -y bind
fi
systemctl named start &>/dev/null
[ $? ne 0 ] && service named restart &>/dev/null
sed -i 's#listen-on port 53 { 127.0.0.1; };#listen-on port 53 { 127.0.0.1; any; };#'  $conf
sed -i 's#listen-on-v6 port 53 { ::1; };##' $conf
sed -i 's#allow-query     { localhost; };#allow-query     { localhost; any; };#' $conf
sed -i 's#include "/etc/named.rfc1912.zones";##' $conf
sed -i '37,40d' $conf
while :
  do
	read -p "Please input domain,[input:q,exit]: " domain
	[ $domain == "q" ] && exit
	read -p "Please input match-clients,[input:q,exit]: " match
	[ $match == "q" ] && exit
	read -p "Please input view name,[input:q,exit]: " view
	[ $view == "q" ] && exit
	read -p "Please input master ip,[input:q,exit]: " master_ip
	[ ${master_ip} == "q" ] && exit
	read -p "Please input allow transfer,[input:q,exit]: " transfer
	[ $transfer == "q" ] && exit
	sed -i 's#include "/etc/named.root.key";##' $conf
	cat >>$conf << EOF
	view "$view" {
        match-clients {$match; };
        zone "." IN {
                type hint;
                file "named.ca";
        };
        zone "$domain" IN {
                type slave;
		transfer-source {$transfer;};
		master {$master_ip;};
                file "slaves/$view.$domain.zone";
        };
	include "/etc/named.rfc1912.zones";
	};
EOF
	echo 'include "/etc/named.root.key";' >> /etc/named.conf
systemctl named restart &>/dev/null
[ $? ne 0 ] && service named restart &>/dev/null
echo 'Complete!'
read -p "Please enter exit for exit,other continue: " e
[ $e == "exit" ] && exit
  done

