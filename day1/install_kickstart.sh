#!/bin/bash
pxelinux_cfg="/var/lib/tftpboot/pxelinux.cfg"
tftpboot="/var/lib/tftpboot/"
#自定义静态IP
file="/etc/sysconfig/network-scripts/"
echo "Set System something"
read -p "Set hostname,please input hostname: " hostname
read -p "Input iso mount point,[example: file:///mnt]: " mount_dir

static(){
cat > $file$netdev <<EOF
DEVICE=$dev
NAME=$dev
TYPE=Ethernet
BOOTPROTO="none"
ONBOOT=yes
IPADDR=$ip
NETMASK=$netmask
GATEWAY=$gateway
DNS=$dns
EOF
}

network(){
service network restart &>/dev/null
}

ask_ip(){
	echo "set ipaddress: "
        read -p "Input ipaddress: " ip
        read -p "Input netmask: " netmask
        read -p "Input gateway: " gateway
        read -p "Input DNS: " dns
}

sys_init(){
#关闭selinux
setenforce &>/dev/null
sed -in 's/SELINUX=enforcing/SELINUX=disabled/'  /etc/selinux/config
#关闭防火墙
service iptables stop &>/dev/null
chkconfig iptables off
#设置主机名
hostname $hostname
echo "$hostname" > /etc/hostname
#设置yum
cat > /etc/yum.repos.d/iso.repo <<EOF
[iso]
name=iso
baseurl=$mount_dir
enabled=1
gpgcheck=0
EOF
mount_file="$(awk -F "//" 'NR==3{print $2}'  /etc/yum.repos.d/iso.repo)"
#echo "/dev/cdrom   $mount_file  iso9660   loop,ro   0 0" >> /etc/fstab
#mount -a
}


init_dhcp(){
#安装dhcp服务
yum install -y dhcp &>/dev/null
#修改dhcp配置文件
dhcp_config=$(rpm -qd dhcp | grep -w "dhcpd.conf.sample")
\cp ${dhcp_config} /etc/dhcp/dhcpd.conf
cat > /etc/dhcp/dhcpd.conf <<EOF
allow booting;
allow bootp;

default-lease-time 600;
max-lease-time 7200;
log-facility local7;

subnet $subnet netmask $netmask {
  range $range_frs $range_end;
  next-server $ip;
  filename "pxelinux.0";
}
EOF
chkconfig dhcpd on
service dhcpd start &>/dev/null
service network restart &>/dev/null
echo "install dhcp is ok."
}

init_tftp(){
#安装xientd、tftp-server和syslinux
yum install -y xinetd tftp-server syslinux &> /dev/null
sed -i  's/disable/enable/' /etc/xinetd.d/tftp

cp /usr/share/syslinux/pxelinux.0 $tftpboot
mkdir ${pxelinux_cfg}
touch ${pxelinux_cfg}/defalut
cat > ${pxelinux_cfg}/default<<EOF
default vesamenu.c32 
timeout 60 
display boot.msg 
menu background splash.jpg 
menu title Welcome to Global Learning Services Setup! 

label local  
        menu label Boot from ^local drive 
        menu default
        localhost 0xffff 

label install
        menu label Install rhel6
        kernel vmlinuz
        append initrd=initrd.img ks=http://$ip/myks.cfg
EOF

cd ${mount_file}/isolinux
cp boot.msg initrd.img vmlinuz vesamenu.c32 splash.jpg $tftpboot
chkconfig xinetd on
service xinetd start &>/dev/null
echo "install xinetd tftp-server is ok."
}


init_httpd(){
yum install -y httpd &>/dev/null
cat >/var/www/html/myks.cfg<<EOF
#version=RHEL7
# System authorization information
auth --enableshadow --passalgo=sha512
# Reboot after installation 
reboot
# Use network installation
url --url="http://$ip/dvd/"  
# Use graphical install
#graphical 
text
# Firewall configuration
firewall --enabled --service=ssh  
firstboot --disable
ignoredisk --only-use=sda
# Keyboard layouts
keyboard us
# new format:
#keyboard --vckeymap=us --xlayouts='us' 
# System language 
lang en_US.UTF-8
# Network information
network  --bootproto=dhcp 
network  --hostname=localhost.localdomain
# Root password
rootpw --iscrypted nope
# SELinux configuration
selinux --disabled
# System services
services --disabled="kdump,rhsmcertd" --enabled="network,sshd,rsyslog,ovirt-guest-agent,chronyd"
# System timezone
timezone Asia/Shanghai --isUtc
# System bootloader configuration
bootloader --append="console=tty0 crashkernel=auto" --location=mbr --timeout=1 
# 设置boot loader安装选项 --append指定内核参数 --location 设定引导记录的>位置
# Clear the Master Boot Record
zerombr 
# Partition clearing information
clearpart --all --initlabel 
# Disk partitioning information
part / --fstype="ext4" --ondisk=sda --size=6144 
%post
echo "redhat" | passwd --stdin root
useradd carol
echo "redhat" | passwd --stdin carol
# workaround anaconda requirements
%end

%packages
@core
%end
EOF
chown apache. /var/www/html/myks.cfg
mkdir /var/www/html/dvd
mount -o loop,ro /dev/cdrom /var/www/html/dvd
echo "/dev/cdrom   /var/www/html/dvd  iso9660   loop,ro   0 0" >> /etc/fstab
chkconfig httpd on
service httpd start &> /dev/null
echo "install httpd is ok."
}


echo "Set network device ipaddress."
select dev in $(ip link | grep -v "link" | awk -F ": " '{print $2}') exit
   do	
        if [ $dev == "exit" ];then
                break
        fi
        netdev="ifcfg-$dev"
        cd $file
        [ -e $netdev ] && \cp  "$netdev" "$netdev-$(date "+%F-%H:%M")"
           ask_ip
           static
           network
           echo 'Complete!'
   done
echo "Set DHCP parameter"
read -p "Input subnet,[example: 192.168.1.0]: " subnet
read -p "Input dhcp ip range first,[example:192.168.1.100]: " range_frs
read -p "Input dhcp ip range end,[example:192.168.1.250]: " range_end
echo "Installing..."
sys_init
init_dhcp
init_tftp
init_httpd
