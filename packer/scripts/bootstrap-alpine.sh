#!/usr/bin/env bash
# Bootstrap a minimal Alpine Linux rootfs onto the blank EBS volume.
# ~150MB, ~2min. The helper instance (Ubuntu) contributes nothing to the image.
set -euo pipefail

DISK=$(lsblk -dpno NAME,SIZE | awk '$2=="2G"{print $1; exit}')
PART="${DISK}p1"; [ -b "$PART" ] || PART="${DISK}1"

apt-get update -qq
apt-get install -y -qq parted e2fsprogs wget >/dev/null

parted -s "$DISK" mklabel msdos mkpart primary ext4 1MiB 100%
mkfs.ext4 -F -L rootfs "$PART"

TARGET=/mnt/scratch
mkdir -p "$TARGET"
mount "$PART" "$TARGET"

ALPINE_V=3.22
REPO="http://dl-cdn.alpinelinux.org/alpine/v${ALPINE_V}/main"

# apk.static + Alpine signing keys — one ~3MB download, runs anywhere (static musl)
APKFILE=$(wget -qO- "$REPO/x86_64/" | grep -o 'apk-tools-static-[^"]*\.apk' | head -1)
wget -qO /tmp/apk-tools.apk "$REPO/x86_64/$APKFILE"
mkdir -p /tmp/apkroot && tar -xzf /tmp/apk-tools.apk -C /tmp/apkroot

KEYS=/tmp/apkroot/etc/apk/keys
if [ -d "$KEYS" ]; then TRUST=(--keys-dir "$KEYS"); else TRUST=(--allow-untrusted); fi

# linux-virt: virtio/NVMe/ENA built in — the cloud kernel. No cloud-init: ~30MB saved.
/tmp/apkroot/sbin/apk.static --root "$TARGET" --repository "$REPO" \
  "${TRUST[@]}" --initdb --no-progress \
  add alpine-base linux-virt openssh ifupdown-ng curl grub-bios

mount --bind /dev  "$TARGET/dev"
mount --bind /proc "$TARGET/proc"
mount --bind /sys  "$TARGET/sys"
cp -L /etc/resolv.conf "$TARGET/etc/resolv.conf"

cat > "$TARGET/setup.sh" <<'EOF'
#!/bin/sh
set -e
DISK="$1"

echo from-scratch > /etc/hostname
echo 'LABEL=rootfs  /  ext4  defaults  0 1' > /etc/fstab

cat > /etc/network/interfaces <<'N'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
N

# serial console: kernel output + getty on ttyS0 (EC2 serial console works)
cat > /etc/default/grub <<'G'
GRUB_TIMEOUT=1
GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200"
G
sed -i 's/^#ttyS0/ttyS0/' /etc/inittab

# what setup-alpine would have enabled
for s in devfs dmesg mdev hwdrivers; do
  if [ -e "/etc/init.d/$s" ]; then rc-update add "$s" sysinit; fi
done
for s in modules sysctl hostname root networking bootmisc syslog; do
  if [ -e "/etc/init.d/$s" ]; then rc-update add "$s" boot; fi
done
for s in sshd local; do
  if [ -e "/etc/init.d/$s" ]; then rc-update add "$s" default; fi
done
for s in killprocs mount-ro savecache; do
  if [ -e "/etc/init.d/$s" ]; then rc-update add "$s" shutdown; fi
done

# SSH keys from EC2 metadata (IMDSv2) — the 10 lines cloud-init normally owns
cat > /etc/local.d/00-ssh-keys.start <<'K'
#!/bin/sh
TOKEN=$(curl -s -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' \
  http://169.254.169.254/latest/api/token)
KEY=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key)
[ -n "$KEY" ] || exit 0
mkdir -p /root/.ssh
echo "$KEY" >> /root/.ssh/authorized_keys
chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys
K
chmod +x /etc/local.d/00-ssh-keys.start

grub-install "$DISK"
grub-mkconfig -o /boot/grub/grub.cfg
EOF
chmod +x "$TARGET/setup.sh"
chroot "$TARGET" /setup.sh "$DISK"
rm "$TARGET/setup.sh"

umount "$TARGET/dev" "$TARGET/proc" "$TARGET/sys"
umount "$TARGET"
sync
