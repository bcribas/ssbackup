INSTALLDIR:=/usr

ssbackup: backup.sh
	@cp $^ $@
	@chmod a+x $@

install: ssbackup
	install -o root ssbackup $(INSTALLDIR)/sbin/
	install -d /etc/ssbackup
	test -e /etc/ssbackup/ssbackup.conf || install -m 644 -o root ssbackup.conf /etc/ssbackup/
	test -e /etc/ssbackup/machine.conf || install -m 644 -o root machine.conf /etc/ssbackup/
	install -d /var/log/ssbackup
