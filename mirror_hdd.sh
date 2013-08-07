#!/bin/bash


# lokale Spiegelung des Systems auf zweite HDD mit rsync.
# Rootrechte erforderlich, Ziel-HDD muss eingehaengt sein.
# Zur Vervendung mit cron.
#
# Speedpoint nG (FW), Stand: Juni 2012


# Variablen, bitte anpassen -----------------------------------------
#
ziel=/mnt/mirror              # Mountpunkt fuer $hdd
hdd=sdb2                      # Partition auf der Mirror-Disk
user=david@localhost          # Empfaenger von Statusmails
#
# -------------------------------------------------------------------








# Los


# Duerfen wir das hier alles?
if [ ! "`id -u`" = "0" ]; then
   echo ""
   echo "ABBRUCH, Rootrechte erforderlich!"
   echo ""
   exit 1
fi


# User vorhanden?
[ -e "`cat /etc/passwd | fgrep $user`" ] && echo "ABBRUCH, $user existiert nicht." && exit 1


# Log anlegen und Sync starten
log=`mktemp mirror.XXXXXXXX`
echo "----- Start `date +%d.%m.%Y\ \-\ \%R\ \%Z`" >>$log


# Spiegel HDD eingehaengt?
if [ ! "`mount | fgrep $hdd`" ]; then
   echo "ABBRUCH DER SPIEGELUNG, $hdd nicht gefunden. Bitte dringen Speedpoint anrufen!" | tee -a $log
   cat $log | mail -s "ACHTUNG: Spiegelfestplatte nicht gefunden!" $user
   exit 1
fi

# ISAM beenden

hier=`pwd`
cd /home/david
./iquit


# Sync starten
rsync -ahH --delete --force --one-file-system --exclude=/mnt --exclude=/proc --exclude=/sys -P / $ziel/ 2>>$log


# Status klaeren und berichten
status=`echo $?`
echo "----------------------------------------------------------------------" >>$log
echo "Ende: `date +%d.%m.%Y\ \-\ \%R\ \%Z`" >>$log
if [ $status = 0 ]; then
   echo "Plattenspiegelung erfolgreich abgeschlossen." | tee -a $log
   tail -n2 $log | mail -s "Festplattenspiegelung ok :-)" $user
else
   cat $log | mail -s "ACHTUNG: Fehler bei der Festplattenspiegelung!" $user
fi


# ISAM starten
cd /home/david
./isam
cd $hier


rm -f $log
exit 0
