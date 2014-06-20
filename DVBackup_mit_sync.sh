#!/bin/bash



# Backup Script fuer regelmaessige Backups mit rsnapshot & tar.
# Es werden rsnapshots lokal gesichert und danach (optional verschluesselt)
# auf ein externes Medium gesichert.
#
# Zur Benutzung mit cron als root
#
# Erfordert rsnapshot, libnotify, perl-Lchown, tar, mt, mcrypt.
#
# --> HDD fuer rsnapshot Daten in der /etc/fstab eintragen!
# --> Anpassung der /etc/rsnapshot.conf nicht vergessen!
#     Bitte passendes Beispiel conf Datei beachten (s.u.) 
#
# Speedpoint nG GmbH (FW), Version 2.0, Stand: Juni 2014




### Folgende Werte bitte anpassen: #############################################
#
user=david                             # Lokaler Empfaenger der Statusmails
#
interval=daily                         # [hourly/daily/weekly/monthly]  
config=/etc/rsnapshot.spng.conf        # Optional eigene Konfigurationsdatei
#
snap=/dev/sdc1                         # Devicebezeichn. der Snapshot Partition
hddout=true                            # nach rsnapshot aushaengen?
#
crypt=true                             # Verschluesselung auf dem ext. Medium?
dvkey=david                            # Passwort fuer Verschluesselung
#
media=rdx                              # [dds/rdx]
godown=false                           # Shutdown nach Backup?
reset=true                             # Reset nach Backup?
#
toolpfad=/install/skripte
vcheck=false                           # Virensuche in trpword starten?
vtool=$toolpfad/vcheck.sh              # Pfad zu virencheck.sh
rkcheck=false                          # Rootkit Suche starten?
rktool=$toolpfad/rkcheck.sh            # Pfad zu rootkit.sh
#
mirror=true                            # Sync der Spiegelplatte vor dem Backup
tool=$toolpfad/mirror_hdd.sh           # Pfad & Name des Sync Scripts
#
#
# ACHTUNG: Namen der Logdatei im Skript SaveAndHalt.bat des WinPCs abgleichen!
padmplog=/home/david/trpword/DMPPABackupLog.txt   # Logdatei von SaveAndHalt.bat
#
#
### Ende der Anpassungen #######################################################






# Ab hier bitte Finger weg!





echo ""

# Duerfen wir das alles?
if [ "$(id -u)" != "0" ]; then
   echo "ABBRUCH, Ausfuehrung nur durch root!"
   echo "Script als root starten!" | mail -s "WARNUNG: Backup nicht korrekt konfiguriert!" $user@localhost
   echo ""
   exit 1
fi

# Medium gewaehlt?
case "$media" in
   dds)
     device=/dev/st0
     echo "Externes Medium ist $device."
     remove="mt -f $device offline"
     rdxin=true # Kein Irrtum!
     ;;
   rdx)
     device=/dev/sdd
     echo "Externes Medium ist $device."
     remove="eject $device"
     rdxin=true
     partition=`echo $device | sed 's/\/dev\///'`
     cat /proc/partitions | grep $partition >/dev/null || rdxin=false
     ;;
   *)
     echo "ABBRUCH, bitte externes Medium korrekt angeben!"
     echo "Externes Backupmedium nicht korrekt angegeben." | mail -s "WARNUNG: Backup nicht korrekt konfiguriert!" $user@localhost
     exit 1
     ;;
esac

# Wurde die config fuer rsnapshot korrekt angegeben?
if   [ ! -e $config ]; then
     text1="$config nicht gefunden."
fi
if [[ `cat $config | grep Speedpoint` = "" ]]; then
     text2="Die Datei muss den Ausdruck \"Speedpoint\" enthalten."
     echo "$text1 $text2" | mail -s "WARNUNG: Backup nicht korrekt konfiguriert!" $user@localhost
     exit 1
fi

# Mountpoint fuer die Snapshots testen:
check=0
cat /etc/fstab | grep $snap >/dev/null
CHECK=`echo $?`
if [ "${CHECK}" != "0" ] ; then
      text="Sicherungsfestplatte $snap nicht in fstab gefunden."
      echo $text
      echo $text | mail -s "WARNUNG: Backup nicht korrekt konfiguriert!" $user@localhost
      exit 1
      echo ""
   else
      echo "Snapshot Medium ist $snap."
      FEHLER=0
      umount $snap >/dev/null 2>&1 &&sleep 1
      mount | grep $snap && FEHLER=1
      if [ "${FEHLER}" = "1" ] ; then 
         echo "Fehler beim aushaengen von $snap, fsck Pruefung daher nicht moeglich."
         fscheck="fsck wurde nicht gestartet, da umount von $snap fehlschlug."
         echo ""
         echo "Folgende Prozesse greifen derzeit auf $snap zu:"
         lsof $snap
         echo ""
      else
         # Pruefen, ob Dateisystem von $snap sauber ist:
         check=0
         e2fsck -n $snap | grep 'sauber' >/dev/null
         CHECK=`echo $?`
         if [ "${CHECK}" = "0" ] ; then
            sauber=true
            fscheck="Das Dateisystem von $snap ist sauber."
            echo $fscheck
         else
            text="WARNUNG: Das Dateisystem von $snap muss repariert werden, bitte umgehend Speedpoint anrufen."
            echo $text | mail -s "Die Sicherungsfestlatte ist offenbar fehlerhaft und muss geprueft werden." $user@localhost
            echo $text
            echo ""
            exit 1
         fi
      fi
fi

echo ""
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "ACHTUNG: Nach der Sicherung erfolgt u.U.ein Reset bzw. ein Systemstop!"
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo ""


# Schritt 0: Rootkit & Virensuche ----------------------------------------------
if $vcheck ; then
   $vtool
fi   
#
if $rkcheck ; then
   $rktool
fi   

# Schritt 1: HDD 1 auf Spiegelplatte synchronisieren ---------------------------
if $mirror ; then
   hier=`pwd`
   echo "Spiegelplatte wird synchronisiert..."
   check=0
   echo "Externes Script $tool wird aufgerufen."
   cd $toolpfad
   $tool
   CHECK=`echo $?`
   if [ "${CHECK}" != "0" ] ; then
      echo "WARNUNG: Fehler beim Synchronisieren der Spiegelplatte!"
   fi
   cd $hier
   echo "Externes Skript beendet."
else
   echo "Synchronisation der HDDs nicht aktiviert."
fi   


# Schritt 2: Lokalen Snapshot erstellen ----------------------------------------
echo ""
echo "Lokalen Snapshot erstellen:"
jetzt=`date`

# rsnapshot HDD ggf. einhaengen
check=0
mount | grep $snap >/dev/null 2>&1 || mount $snap >/dev/null 2>&1
CHECK=`echo $?`
if [ "${CHECK}" != "0" ] ; then 
   echo "ABBRUCH: Fehler beim Einhaengen von $snap."
   echo ""
   exit 1
else
   echo "$snap wurde gemountet."
fi

mountpoint=`cat /etc/fstab | grep $snap | awk {'print $2'}`

errorlog=$mountpoint/Fehler.log
echo "Fehlerprotokoll ist $errorlog."

#export DAV_HOME=/home/david
cd /home/david
echo "ISAM beenden."
./iquit 2>>$errorlog

# Snapshot erstellen & Logdatei fuer Fehler anlegen
echo ""
echo "Lokaler Snapshot wird auf $snap erstellt."
CHECK=0
rsnapshot -c $config -v $interval 2>>$errorlog
CHECK=`echo $?`
if [ "${CHECK}" = "0" ] ; then
   backup_success=true
   echo "rsnapshot erfolgreich."
else
   backup_success=false
   echo "rsnapshot mit Fehler(n) beendet." >>$errorlog
fi
echo ""

echo "ISAM starten..."
./isam 2>>$errorlog && echo "OK"
cd $here


# Schritt 3: Externe Sicherung -------------------------------------------------

echo "Externe Sicherung beginnt."
# Medium vorhanden?
##################################################
if ! $rdxin ; then
   rdxtext="Kein Backup Medium eingelegt. "
   echo $rdxtext
   info="FEHLERHAFT"
else
   # ggf. verschluesselte Kopie von daily.0 anlegen & verschluesseln
   if $crypt ; then
      rm -f $mountpoint/*.tar.nc 2>/dev/null
      keyfile=`mktemp /tmp/keyfile.XXXXXXXX`
      echo $dvkey >$keyfile
      echo "Verschluesselung vorbereiten..."
      tar -cf $mountpoint/daily.0.tar $mountpoint/daily.0 --exclude=$mountpoint/daily.0/localhost/home/install --one-file-system 2> >(egrep -v 'socket ignored\|Kann stat nicht' >&2) && echo "OK."
      echo "Verschluesseln..."
      CHECK=0
      mcrypt -f `echo $keyfile` $mountpoint/daily.0.tar 2>>$errorlog || CHECK=1
      if [ "${CHECK}" = "0" ] ; then
         crypt_message="Die gesicherten Daten wurden mit dem Passwort $dvkey verschluesselt"
         echo "Verschluesselung mit Passwort $dvkey erfolgreich."
         data=$mountpoint/daily.0.tar.nc
      else
         crypt_message="ACHTUNG: Bei der Verschluesselung ist ein Fehler aufgetreten, bitte $errorlog beachten!  "
         echo "WARNUNG: Fehler bei der Verschluesselung, bitte $errorlog beachten!"
      fi
      rm -f $mountpoint/daily.0.tar
      rm -f $keyfile    
   else
      echo "mcrypt Verschluesselung deaktiviert."
      crypt_message="Die gesichterten Daten wurden nicht verschluesselt."
      data=$mountpoint/daily.0
   fi
   # Auf Medium schreiben:
   tempfile=`mktemp /tmp/tarbackup.XXXXXXXX`
   echo "Temp. Datei ist $tempfile."
   echo $crypt_message >>$tempfile
   echo "" >>$tempfile
   rdxtext=""
   chmod 666 $device
   CHECK=0
   echo "Medium $device wird beschrieben."
   tar -cvf $device $data >>$tempfile 2>&1
   CHECK=`echo $?`
   if [ "${CHECK}" = "0" ] ; then
      info="erfolgreich"
      echo "Externe Sicherung okay."
      # Medienauswurf
      echo "Medium $device wird ausgeworfen."
      $remove || echo "Auswurf fehlerhaft."
   else
      info="FEHLERHAFT"
      echo "WARNUNG: Externe Datensicherung fehlerhaft."
      cat $tempfile | mail -s "WARNUNG: $rdxtext Externe Datensicherung fehlerhaft!" $user@localhost
      rm -f $tempfile && echo "$tempfile geloescht."
      echo "Kein Medeinauswurf von $device."
   fi
fi

# Nachricht absetzen:
echo ""
mailtext="Die Externe Datensicherung von $jetzt wurde $info abgeschlossen. $crypt_message $fscheck"
echo $mailtext
echo $mailtext | mail -s "Externe Datensicherung $info" $user@localhost
echo ""

# HDD ggf. aushaengen
if $hddout ; then
   cd / && sleep 2	
   umount $snap >/dev/null 2>&1 || echo "Fehler bei umount von $snap."
else
   echo "$snap bleibt eingehaengt."
fi

# Backup Protokoll des/der PA/DMP PCs als Mail versenden, falls vorhanden:
if [ -r $padmplog ]; then
   cat $padmplog | mail -s "Datensicherung am Windows PC" $user@localhost
   # falls Logdatei zu gross wird, umbenennen:
   if [ `cat $padmplog | wc -l` -gt 1000 ]; then
      mv $padmplog /home/david/trpword/padmplog.old.txt
   fi
fi

if $godown ; then
   echo "Das System schaltet in 20 Sekunden ab..." && sleep 20
   /sbin/shutdown -h now
elif $reset ; then
   echo "Das System startet in 120 Sekunden neu..." && sleep 120
   /sbin/shutdown -r now
fi

echo "Skript beendet."
echo ""
exit 0

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Scriptende
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------





# Hier eine passende rsnaphot.conf als Beispiel
#
# Kommentare '' entfernen und Datei in /etc hinterlegen.
# ACHTUNG: KEINE LEERZEICHEN, SONDERN TABs VERWENDEN!!



#########################################
#   Speedpoint Version fuer rsapshot    #
#########################################  
config_version   1.2
snapshot_root    /mnt/snapshots/
no_create_root   1
#
cmd_rm           /bin/rm
cmd_rsync        /usr/bin/rsync
cmd_logger       /usr/bin/logger
#
#########################################
#           BACKUP INTERVALS            #
#########################################
interval         daily   20
#
verbose          2
loglevel         3
lockfile         /var/run/rsnapshot.pid
one_fs           1
#
## Exclude List ##
exclude  Recycled/
exclude  Trash/
exclude  lost+found/
exclude  .gvfs/
exclude  *_uds_*
exclude  *.SP
exclude  *.SF
exclude  /home/install
#
###############################
### BACKUP POINTS / SCRIPTS ###
###############################
# LOCALHOST
backup   /home/      localhost/
backup   /etc/       localhost/
