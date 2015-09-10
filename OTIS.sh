# Do some unimportant stuff

loadkeys us
locale-gen
timedatectl set-ntp true

# Get wireless info

ip addr show | grep wlp
echo ""
echo "Network name thing:"
read network

# Partition and mount harddrive

lsblk
echo ""
echo "Drive to partition:"
read drive
echo "Drivetype (UEFI or BIOS):"
read drivetype

partition() {
if [ "$drivetype" == "UEFI" ]; then
	parted $drive mklabel gpt
	parted $drive mkpart ESP fat32 1MiB 513MiB
	parted $drive set 1 boot on
	parted $drive mkpart primary ext4 514MiB 20GiB
	parted $drive mkpart primary linux-swap 20GiB 24GiB
	parted $drive mkpart primary ext4 24GiB 100%
else
	parted $drive mklabel msdos
	parted $drive mkpart primary ext4 1MiB 20GiB
	parted $drive set 1 boot on
	parted $drive mkpart primary linux-swap 20GiB 24GiB
	parted $drive mkpart primary ext4 24GiB 100%
fi
}

prepareDrive() {
if [ "$drivetype" == "UEFI" ]; then
	mkfs.vfat -F32 $drive\1
	mkfs.ext4 -F $drive\2
	mkfs.ext4 -F $drive\4
	mkswap $drive\3
	swapon $drive\3
	mount $drive\2 /mnt
	mkdir /mnt/boot
	mkdir /mnt/home
	mount $drive\1 /mnt/boot
	mount $drive\4 /mnt/home
else
	mkfs.ext4 -F $drive\1
	mkswap $drive\2
	swapon $drive\2
	mkfs.ext4 -F $drive\3
	mkdir /mnt
	mount $drive\1 /mnt
	mkdir /mnt/home
	mount $drive\3 /mnt/home
fi
}

partition $drive
prepareDrive $drive

# Install reflector and rate mirrors

pacman -Sy reflector --noconfirm
reflector --verbose -l 200 -p http --sort rate --save /etc/pacman.d/mirrorlist

# Install base system and extras, then chroot into install

pacstrap -i /mnt $(cat ~/OTIS/packages) --noconfirm
genfstab -U /mnt > /mnt/etc/fstab

# Do some unimportant stuff

arch-chroot /mnt loadkeys us
echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
arch-chroot /mnt ln -sf /usr/share/zoneinfo/America/Kentucky/Louisville /etc/localtime
arch-chroot /mnt hwclock --systohc --utc

# Configure hostname

echo "Choose a hostname:"
read hostname
echo $hostname > /mnt/etc/hostname
echo "#<ip-address>	<hostname.domain.org>	<hostname>
127.0.0.1		localhost.localdomain	localhost	$hostname
::1		localhost.localdomain	localhost	$hostname" > /mnt/etc/hosts

# Set root password

echo "Choose a root password:"
arch-chroot /mnt passwd

# Install and configure bootloader

if [ "$drivetype" == "UEFI" ]; then
	touch /mnt/boot/loader/entries/arch.conf
	arch-chroot /mnt pacman -S dosfstools --noconfirm
	arch-chroot /mnt bootctl --path=/boot install
	mkdir -p /mnt/boot/loader/entries/
	echo "title	Arch Linux
	linux	/vmlinuz-linux
	initrd	/initramfs-linux.img
	options	root=$drive\2 rw" > /mnt/boot/loader/entries.conf
else
	mkdir -p /mnt/boot/grub/
	arch-chroot /mnt pacman -S grub os-prober --noconfirm
	arch-chroot /mnt grub-install --recheck $drive
	arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
fi

# Setup user account

echo "Enter user account name (lowercase, no spaces):"
read username
arch-chroot /mnt useradd -m -G wheel -s /bin/bash $username
echo "$username ALL=(ALL) ALL" >> /mnt/etc/sudoers
echo "Enter user account password for $username:"
arch-chroot /mnt passwd $username

# Add yaourt repo and some programs

echo "[archlinuxfr]
SigLevel = Never
Server = http://repo.archlinux.fr/\$arch" >> /mnt/etc/pacman.conf
arch-chroot /mnt pacman -Syyu yaourt --noconfirm
arch-chroot /mnt yaourt -S i3-gaps-git screencloud dropbox numix-themes-git numix-circle-icon-theme-git filebot --noconfirm

# Copy over some configs

mkdir -p /mnt/home/$username/.config/i3/conky/
touch /mnt/home/$username/.config/i3/config
touch /mnt/home/$username/.config/i3/conky/conkyrc
touch /mnt/home/$username/.Xdefaults
cd /mnt/home/$username/
git clone https://github.com/cehcuhl/dotfiles.git
cp -R /mnt/home/$username/dotfiles/ /
rmdir /mnt/home/$username/dotfiles/

# Enable some services

arch-chroot /mnt systemctl enable lxdm.service
arch-chroot /mnt systemctl enable netctl-auto@$network.service

# End installation

umount -R /mnt
reboot
