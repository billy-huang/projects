#!/bin/bash
mnt_usb="/usb_mnt"
#准备U盘 分区，格式化，设置为引导分区
read -p "Please input usb name [example:/dev/sdb]: " usb_dir
dd if=/dev/zero of=${usb_dir} bs=500 count=1
fdisk ${usb_dir} <<EOF
n
p
1


a
1
w
EOF
mkdir ${mnt_usb}
mount ${usb_dir} ${mnt_usb}

#安装文件系统与BASH程序，重要命令（工具）、基础服务
yum clean all &>/dev/null
yum makecache 
if [ $? -eq 0 ];then
	yum -y install filesystem bash coreutils passwd shadow-utils openssh-clients rpm yum net-tools bind-utils vim-enhanced findutils lvm2 util-linux-ng --installroot=${mnt_usb}
else 
	echo "please configure yum.repo."
vmlinuz=$(ls /boot | grep '^vmlinuz')
initramfs=$(ls /boot | grep '^initramfs')
release=$(ls /lib/modules/)
cp /boot/$vmlinuz ${mnt_usb}
cp /boot/$initramfs ${mnt_usb}
cp -arv /lib/modules/$release ${mnt_usb}

#安装grub程序
yum install yum-utils -y 
yumdownloader grub.x86_64 --destdir=/usr/local/src
grub=$(ls /usr/local/src | grep '^grub')
rpm -ivh $grub --nodeps --force

#安装驱动
grub-install --root-directory=${mnt_usb}  --recheck  ${usb_dir}

#定义grub.conf
cp /boot/grub/grub.conf ${mnt_usb}/boot/grub/

uuid=$(blkid /dev/sda1 | awk '{print $2}' | sed 's/"//g')
cat >${mnt_usb}/boot/grub/grub.conf<<EOF
default=0
timeout=5
splashimage=/boot/grub/splash.xpm.gz
title My USB System from billy
        root (hd0,0)
        kernel /boot/$vmlinuz ro root=$uuid selinux=0
        initrd /boot/$initramfs
EOF

#完善环境变量与配置文件:
cp /etc/skel/.bash* ${mnt_usb}/root/
uuid_fs=$(blkid /dev/sda1 | awk '{print $2}') 
cat >${mnt_usb}/etc/fstab<<EOF
${uuid_fs} / ext4 defaults 0 0
sysfs                   /sys                    sysfs   defaults        0 0
proc                    /proc                   proc    defaults        0 0
tmpfs                   /dev/shm                tmpfs   defaults        0 0
devpts                  /dev/pts                devpts  gid=5,mode=620  0 0
EOF

#修改root密码
sed  '/^root/d' ${mnt_usb}/etc/shadow
echo 'root123:$1$LnssQ/$LMaRecErPKEkqFX9B7jCq.:17377:0:99999:7:::' >> ${mnt_usb}/etc/shadow
echo "root password is : 123456"
#同步脏数据
sync
