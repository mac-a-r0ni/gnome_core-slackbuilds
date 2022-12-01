if [ -x /usr/bin/update-desktop-database ]; then
  /usr/bin/update-desktop-database -q usr/share/applications >/dev/null 2>&1
fi

if [ -e usr/share/icons/hicolor/icon-theme.cache ]; then
  if [ -x /usr/bin/gtk-update-icon-cache ]; then
    /usr/bin/gtk-update-icon-cache usr/share/icons/hicolor >/dev/null 2>&1
  fi
fi
if [ -e usr/share/glib-2.0/schemas ]; then
  if [ -x /usr/bin/glib-compile-schemas ]; then
    /usr/bin/glib-compile-schemas usr/share/glib-2.0/schemas >/dev/null 2>&1
  fi
fi
( cd usr/share/help/cs/pika-backup/media ; rm -rf archives-button.svg )
( cd usr/share/help/cs/pika-backup/media ; ln -sf ../../../C/pika-backup/media/archives-button.svg archives-button.svg )
( cd usr/share/help/cs/pika-backup/media ; rm -rf setup-button.svg )
( cd usr/share/help/cs/pika-backup/media ; ln -sf ../../../C/pika-backup/media/setup-button.svg setup-button.svg )
( cd usr/share/help/da/pika-backup/media ; rm -rf archives-button.svg )
( cd usr/share/help/da/pika-backup/media ; ln -sf ../../../C/pika-backup/media/archives-button.svg archives-button.svg )
( cd usr/share/help/da/pika-backup/media ; rm -rf setup-button.svg )
( cd usr/share/help/da/pika-backup/media ; ln -sf ../../../C/pika-backup/media/setup-button.svg setup-button.svg )
( cd usr/share/help/de/pika-backup/media ; rm -rf archives-button.svg )
( cd usr/share/help/de/pika-backup/media ; ln -sf ../../../C/pika-backup/media/archives-button.svg archives-button.svg )
( cd usr/share/help/de/pika-backup/media ; rm -rf setup-button.svg )
( cd usr/share/help/de/pika-backup/media ; ln -sf ../../../C/pika-backup/media/setup-button.svg setup-button.svg )
( cd usr/share/help/eu/pika-backup/media ; rm -rf archives-button.svg )
( cd usr/share/help/eu/pika-backup/media ; ln -sf ../../../C/pika-backup/media/archives-button.svg archives-button.svg )
( cd usr/share/help/eu/pika-backup/media ; rm -rf setup-button.svg )
( cd usr/share/help/eu/pika-backup/media ; ln -sf ../../../C/pika-backup/media/setup-button.svg setup-button.svg )
( cd usr/share/help/hu/pika-backup/media ; rm -rf archives-button.svg )
( cd usr/share/help/hu/pika-backup/media ; ln -sf ../../../C/pika-backup/media/archives-button.svg archives-button.svg )
( cd usr/share/help/hu/pika-backup/media ; rm -rf setup-button.svg )
( cd usr/share/help/hu/pika-backup/media ; ln -sf ../../../C/pika-backup/media/setup-button.svg setup-button.svg )
( cd usr/share/help/ru/pika-backup/media ; rm -rf archives-button.svg )
( cd usr/share/help/ru/pika-backup/media ; ln -sf ../../../C/pika-backup/media/archives-button.svg archives-button.svg )
( cd usr/share/help/ru/pika-backup/media ; rm -rf setup-button.svg )
( cd usr/share/help/ru/pika-backup/media ; ln -sf ../../../C/pika-backup/media/setup-button.svg setup-button.svg )
( cd usr/share/help/sv/pika-backup/media ; rm -rf archives-button.svg )
( cd usr/share/help/sv/pika-backup/media ; ln -sf ../../../C/pika-backup/media/archives-button.svg archives-button.svg )
( cd usr/share/help/sv/pika-backup/media ; rm -rf setup-button.svg )
( cd usr/share/help/sv/pika-backup/media ; ln -sf ../../../C/pika-backup/media/setup-button.svg setup-button.svg )
( cd usr/share/help/uk/pika-backup/media ; rm -rf archives-button.svg )
( cd usr/share/help/uk/pika-backup/media ; ln -sf ../../../C/pika-backup/media/archives-button.svg archives-button.svg )
( cd usr/share/help/uk/pika-backup/media ; rm -rf setup-button.svg )
( cd usr/share/help/uk/pika-backup/media ; ln -sf ../../../C/pika-backup/media/setup-button.svg setup-button.svg )
