# Simple and Small backup tool

This is *S*imple and *S*mall *backup* tool to simply do incremental backups
regularly on some machines. And even if a backup point fails it will retry
on next execution.

I wrote this simple tool to backup some machines at home, which includes:
laptops, desktops and a file server.

It works by simply mounting the backup volume (in my case an usb hd) and
then creates the directories and copy files.

Files are copied with _rsync -aHx_, other options may be included in a
simple way.

## Installing

Install is pretty simple, just:
```
make install
```

and you are done. Check Makefile to see what happens.

### Dependencies

You should have the following software installed:
 - ssh
 - rsync
 - bash
 - gawk
 - coreutils

## Configuring

After installing you will get two config files:

1. /etc/ssbackup/backup.conf

This file will get you some variables to be configured. It is pretty
straightforward, just check it out.

2. /etc/ssbackup/machine.conf

This file is where you will configure all machines that should have a
backup, it is simple too and straightforward.

Also you should put your backup mountpoint in /etc/fstab and you must create
a file named '.alive' inside the backup volume.

You should be able to ssh into every machine without the need to enter a
password or a passphrase. The use of a passphraseless ssh key is
recommended. There are some security implications but your backup machine
should be the best protected machine in your network.

## Running

```
/usr/sbin/ssbackup
```

You may give a different file as backup.conf
```
/usr/sbin/ssbackup /root/my-own-backup.conf
```

### Automatically running

For now you should set a cron to run it, a good start is:
```
0 * * * * /usr/sbin/ssbackup

```

Or just symbolic link ssbackup to /etc/cron.hourly
