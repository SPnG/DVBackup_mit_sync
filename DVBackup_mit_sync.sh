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
# Speedpoint nG GmbH (FW), Version 2.1, Stand: September 2014




### Folgende Werte bitte anpassen: #############################################
#
user=david                              # Lokaler Empfaenger der Statusmails
# 
config="/etc/rsnapshot.spng.conf"       # Optional eigene Konfigurationsdatei
#
snap="/dev/sdc1"                        # Devicebezeichn. der Snapshot Partition
hddout=yes                              # $snap nach dem Snapshot aushaengen?
#
crypt=yes                               # Verschluesselung auf dem ext. Medium?
dvkey=david                             # Passwort fuer Verschluesselung
#
rdxdev="/dev/sdd"                       # Devicebezeichnung des RDX-Laufwerks
#
godown=yes                              # Server Shutdown nach dem Backup?
reset=no                                # Server Reset nach dem Backup?
#
toolpfad="/install/skripte"             # Wo liegen die Zusatzskripte?
rktool="$toolpfad/rkcheck.sh"           # Testtool auf Rootkits
vtool="$toolpfad/vcheck.sh"             # clamav Virenscanner inkl. freshclam
tool="$toolpfad/mirror_hdd.sh"          # Tool zur HDD Synchronisation
#
mirror=yes                              # Sync der Spiegelplatte vor dem Backup
rkcheck=no                              # Rootkit Suche starten?
vcheck=yes                              # Virenscanner starten?
#
#
# ACHTUNG: Namen der Logdatei im Skript SaveAndHalt.bat des WinPCs abgleichen!
padmplog="/home/david/trpword/DMPPABackupLog.txt" # Logdatei von SaveAndHalt.bat
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

# RDX Medium vorhanden?
rdxok=no
rdx=`echo $rdxdev | sed -e 's/\/dev\///g'`
remove="eject $rdxdev"
cat /proc/partitions | grep $rdx >/dev/null 2>&1 && rdxok=yes
echo "$rdxdev wurde als RDX Laufwerk angegeben."

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
      umount $snap >/dev/null 2>&1 && sleep 1
      mount | grep $snap && FEHLER=1
      # Falls umount scheitert, greifen vermutlich noch Prozesse auf das device zu:
      if [ "${FEHLER}" = "1" ] ; then 
         echo "Folgende Prozesse greifen derzeit auf $snap zu. Kill wird versucht."
         lsof $snap
         kill $(lsof -t $snap) >/dev/null 2>&1 || echo "Kill gescheitert."
         umount $snap >/dev/null 2>&1 && sleep 1 || umount -l $snap >/dev/null 2>&1
         mount | grep $snap && fscheck="fsck wurde nicht gestartet, da umount von $snap fehlschlug."
         echo $fscheck   
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
            #exit 1
         fi
      fi
fi

echo ""
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo "ACHTUNG: Nach der Sicherung erfolgt u.U.ein Reset bzw. ein Systemstop!"
echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo ""


# Schritt 0: Rootkit und Virensuche --------------------------------------------
if [ "$rkcheck" = "yes" ]; then
   $rktool
fi 
#
if [ "$vcheck" = "yes" ]; then
   $vtool
fi     


# Schritt 1: HDD 1 auf Spiegelplatte synchronisieren ---------------------------
if [ "$mirror" = "yes" ]; then
   hier=`pwd`
   echo "Spiegelplatte wird synchronisiert..."
   check=0
   echo ""
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
echo ""
echo -n "ISAM beenden..."
./iquit || echo "Fehler beim Beenden des ISAM Dienstes." >>$errorlog

# Snapshot erstellen & Logdatei fuer Fehler anlegen
echo "Lokaler Snapshot wird auf $snap erstellt."
CHECK=0
rsnapshot -c $config -v daily 2>>$errorlog
CHECK=`echo $?`
if [ "${CHECK}" = "0" ] ; then
   backup_success=true
   echo "rsnapshot erfolgreich."
else
   backup_success=false
   echo "rsnapshot mit Fehler(n) beendet." >>$errorlog
fi

echo -n "ISAM starten..."
./isam >/dev/null 2>&1 && echo "OK"
cd $here
echo ""

# Schritt 3: Externe Sicherung -------------------------------------------------

# Medium vorhanden?
if [ "$rdxok" = "no" ]; then
   rdxtext="Auf $rdxdev kann nicht gesichert werden (kein Medium?). "
   echo $rdxtext
   info="FEHLERHAFT"
else
   echo "$rdxdev okay, externe Sicherung wird vorbereitet."
   # ggf. verschluesselte Kopie von daily.0 anlegen & verschluesseln
   if [ "$crypt"  = "yes" ]; then
      rm -f $mountpoint/*.tar.nc 2>/dev/null
      keyfile=`mktemp /tmp/keyfile.XXXXXXXX`
      echo $dvkey >$keyfile
      echo "Verschluesselung vorbereiten..."
      tar -cf $mountpoint/daily.0.tar $mountpoint/daily.0 --exclude=$mountpoint/daily.0/localhost/home/install --one-file-system 2> >(egrep -v 'socket ignored\|Kann stat nicht' >&2) && echo "OK."
      echo "Verschluesseln..."
      CHECK=0
      mcrypt -f `echo $keyfile` $mountpoint/daily.0.tar 2>>$errorlog || CHECK=1
      if [ "${CHECK}" = "0" ] ; then
         crypt_message="Die gesicherten Daten wurden mit dem Passwort '$dvkey' verschluesselt."
         echo $crypt_message
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
   chmod 666 $rdxdev
   CHECK=0
   echo "Medium $rdxdev wird beschrieben."
   tar -cvf $rdxdev $data >>$tempfile 2>&1
   CHECK=`echo $?`
   if [ "${CHECK}" = "0" ] ; then
      info="erfolgreich"
      echo "Externe Sicherung okay."
      # Medienauswurf
      echo "Medium $rdxdev wird ausgeworfen."
      $remove || echo "Auswurf fehlerhaft."
   else
      info="FEHLERHAFT"
      echo "WARNUNG: Externe Datensicherung fehlerhaft."
      cat $tempfile | mail -s "WARNUNG: $rdxtext Externe Datensicherung fehlerhaft!" $user@localhost
      rm -f $tempfile && echo "$tempfile geloescht."
      echo "Kein Medeinauswurf von $rdxdev."
   fi
fi

# Nachricht absetzen:
echo ""
mailtext="Die Externe Datensicherung von $jetzt wurde $info abgeschlossen. $crypt_message $fscheck"
echo $mailtext
echo $mailtext | mail -s "Externe Datensicherung $info" $user@localhost
echo ""

# HDD ggf. aushaengen
if [ "$hddout" = "yes" ]; then
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

if [ "$godown" = "yes" ]; then
   echo "+++++++++++++++++++++++++++++++++++++++++"
   echo " Das System schaltet in 120 Sekunden ab."
   echo "+++++++++++++++++++++++++++++++++++++++++"
   sleep 120
   /sbin/shutdown -h now
elif [ "$reset" = "yes" ]; then
   echo "+++++++++++++++++++++++++++++++++++++++++"
   echo " Das System startet in 120 Sekunden neu."
   echo "+++++++++++++++++++++++++++++++++++++++++"
   sleep 120
   /sbin/shutdown -r now
else
   /install/skripte/dp_cleaner.spng.sh || info="Fehler bei Ausfuehrung von dp_cleaner.sh."
   echo ""
   echo $info
   echo ""
   echo $info | mail -s "CGM-Assist Bereinigung gescheitert." $user@localhost
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
exclude          Recycled/
exclude          Trash/
exclude          lost+found/
exclude          /home/install/
exclude          .gvfs/
exclude          *_uds_*
exclude          *.SP
exclude          *.SF
#
###############################
### BACKUP POINTS / SCRIPTS ###
###############################
# LOCALHOST
backup           /home/           localhost/
backup           /etc/            localhost/
backup           /usr/local/etc   localhost/
