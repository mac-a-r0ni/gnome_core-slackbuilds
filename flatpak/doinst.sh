#!/bin/sh
config() {
  NEW="$1"
  OLD="`dirname $NEW`/`basename $NEW .new`"
  # If there's no config file by that name, mv it over:
  if [ ! -r $OLD ]; then
    mv $NEW $OLD
  elif [ "`cat $OLD | md5sum`" = "`cat $NEW | md5sum`" ]; then # toss the redundant copy
    rm $NEW
  fi
  # Otherwise, we leave the .new copy for the admin to consider...
}
preserve_perms() {
  NEW="\$1"
  OLD="\$(dirname \$NEW)/\$(basename \$NEW .new)"
  if [ -e \$OLD ]; then
    cp -a \$OLD \${NEW}.incoming
    cat \$NEW > \${NEW}.incoming
    mv \${NEW}.incoming \$NEW
  fi
  config \$NEW
}

config etc/profile.d/flatpak.sh.new
preserve_perms etc/profile.d/flatpak.sh.new

# Make the flathub/gnome-nightly repositories available systemwide:
chroot . \
  /usr/bin/flatpak remote-add --user --if-not-exists \
  flathub /etc/flatpak/remotes.d/flathub.flatpakrepo
  /usr/bin/flatpak remote-add --user --if-not-exists \
  gnome-nightly /etc/flatpak/remotes.d/gnome-nightly.flatpakrepo

flatpak remote-list --system &> /dev/null || :
