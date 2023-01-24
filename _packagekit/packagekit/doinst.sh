( cd usr/lib64 ; rm -rf libpackagekit-glib2.so )
( cd usr/lib64 ; ln -sf libpackagekit-glib2.so.18 libpackagekit-glib2.so )
( cd usr/lib64 ; rm -rf libpackagekit-glib2.so.18 )
( cd usr/lib64 ; ln -sf libpackagekit-glib2.so.18.1.3 libpackagekit-glib2.so.18 )


config() {
  NEW="$1"
  OLD="`dirname $NEW`/`basename $NEW .new`"
  # If there's no config file by that name, mv it over: 
  if [ ! -r /$ROOT/$OLD ]; then
    mv /$ROOT/$NEW /$ROOT/$OLD
  elif [ "`cat /$ROOT/$OLD 2>/dev/null | md5sum`" = "`cat /$ROOT/$NEW 2>/dev/null | md5sum`" ]; then # toss the redundant copy
    rm /$ROOT/$NEW
  fi
  # Otherwise, we leave the .new copy for the admin to consider...
}

config /etc/PackageKit/Katja.conf.new
config /etc/PackageKit/PackageKit.conf.new
config /etc/PackageKit/Vendor.conf.new

