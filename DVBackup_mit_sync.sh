#!/bin/bash



# Backup Script fuer taegliche Backups mit rsnapshot & tar
# rsnapshot mit optionaler Benachrichtigung auf den Desktop eines Users
# Zur Benutzung mit cron als root
#
# Erfordert rsnapshot, libnotify, perl-Lchown, tar, mt, mcrypt
#
# --> HDD fuer rsnapshot Daten in der /etc/fstab eintragen!
# --> Anpassung der /etc/rsnapshot.conf nicht vergessen!
#     Bitte passendes Beispiel conf Datei beachten (s.u.) 
#
# Speedpoint nG GmbH (FW), Stand: Januar 2014



### Folgende Werte bitte anpassen: #############################################
#
user=david                             # Empfaenger fuer Nachrichten & Mails
message=true                           # Desktop Benachrichtigung senden? 
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
media=rdx                              # Hier nur 'dds' oder 'rdx' einsetzen!
godown=false                           # Shutdown nach Backup?
reset=true                             # Reset nach Backup?
#
toolpfad=/install/skripte
vcheck=false                           # Virensuche in trpword starten?
vtool=$toolpfad/vcheck.sh              # Pfad zu virencheck.sh
#
rkcheck=true                           # Rootkit Suche starten?
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
     device="/dev/st0"
     echo "Externes Medium ist $device."
     remove="mt -f $device offline"
     ;;
   rdx)
     device="/dev/sdd"
     echo "Externes Medium ist $device."
     remove="eject $device"
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
if [ "`cat /etc/fstab | grep $snap`" ]; then
   mount $snap
   if [ $? = "1" ]; then
      text="Fehler beim Einhaengen der Sicherungsfestplatte $snap."
      echo $text
      echo $text | mail -s "WARNUNG: Backup nicht korrekt konfiguriert!" $user@localhost
      exit 1
      echo ""
   else
      umount $snap && sleep 3
      # ~~~ neu ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      # Pruefen, ob Dateisystem von $snap sauber ist:
      echo "Snapshot Medium ist $snap."
      if [ "`e2fsck -n $snap | grep 'sauber'`" ]; then
         sauber=true
         fscheck="Das Dateisystem von $snap ist sauber."
         echo $fscheck
      else
         sauber=false
         text="WARNUNG: Das Dateisystem von $snap muss repariert werden, bitte umgehend Speedpoint anrufen."
         echo $text | mail -s "Die Sicherungsfestlatte ist fehlerhaft und muss geprueft werden." $user@localhost
         echo $text
         echo ""
         exit 1
      fi
      # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   fi
fi

# Fuer Display Benachrichtigungen
ichbins=`whoami`
export DISPLAY=:0.0
export XAUTHORITY=$(/usr/bin/find /var/run/gdm -path "*$user*/database") ;


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
   if $message ; then
	  su - $user -c "notify-send 'Spiegelplatte wird aktualisiert...' -i /usr/share/icons/gnome/32x32/actions/go-jump.png --hint=int:transient:1"
   fi

   echo "Spiegelplatte wird synchronisiert..."
   cd $toolpfad
   $tool

   if [ ! $? -eq 0 ]; then
      echo "WARNUNG: Fehler beim Synchronisieren der Spiegelplatte!"
   fi
   cd $hier
else
   echo "Synchronisation der HDDs nicht aktiviert."
fi   


# Schritt 2: Lokalen Snapshot erstellen ----------------------------------------

# rsnapshot HDD ggf. einhaengen
mount | grep "on ${volume} type" > /dev/null
if [ $? -ne 0 ]; then 
   mount $snap &> /dev/null
fi

# Startnachricht an User
if $message ; then
   su - $user -c "notify-send 'Starte Backup auf Festplatte...' -i /usr/share/icons/gnome/32x32/actions/go-jump.png --hint=int:transient:1"
fi

here=`pwd`
cd /home/david
./iquit

# Snapshot erstellen & Logdatei fuer Fehler anlegen
jetzt=`date`
errorlog="$snap/Fehler.log"
rsnapshot -c $config -v $interval 2>>$errorlog

if [ $? -eq 0 ]; then
   backup_success=true
else
   backup_success=false
fi

./isam
cd $here

# ggf. verschluesselte Kopie von daily.0 anlegen & verschluesseln
data=$snap/daily.0

if $crypt ; then
   rm -f $snap/*.tar.nc 2>>/dev/null
   keyfile=`mktemp /tmp/keyfile.XXXXXXXX`
   echo $dvkey >$keyfile
   echo "Verschluesselung vorbereiten..."
   tar cf $snap/daily.0.tar $snap/daily.0 && echo OK
   echo "Verschluesseln..."
   if $message ; then
      su - $user -c "notify-send 'Verschluesseln... $crypt_message' -i /usr/share/icons/gnome/32x32/emblems/emblem-default.png --hint=int:transient:1"
   fi
   mcrypt -f `echo $keyfile` $snap/daily.0.tar 2>>$errorlog
   if [ $? -eq 0 ]; then
      crypt_message="Die gesicherten Daten wurden mit dem Passwort $dvkey verschluesselt"
      echo "Verschluesselung mit Passwort $dvkey erfolgreich."
      data=$snap/daily.0.tar.nc
   else
      crypt_message="ACHTUNG: Bei der Verschluesselung ist ein Fehler aufgetreten, bitte $errorlog beachten!  "
      echo "WARNUNG: Fehler bei der Verschluesselung, bitte $errorlog beachten!"
   fi
   rm -f $snap/daily.0.tar
   rm -f $keyfile 
else
   echo "Verschluesselung deaktiviert"
   crypt_message="Die gesichterten Daten wurden nicht verschluesselt."
fi

if $message ; then
   if  $backup_success ; then
      # Erfolgsmeldung auf Desktop
      su - $user -c "notify-send 'Backup erfolgreich. $crypt_message' -i /usr/share/icons/gnome/32x32/emblems/emblem-default.png --hint=int:transient:1"
   else
      su - $user -c "notify-send 'WARNUNG: Backup mit Fehlern beendet $crypt_message :-(    Bitte $errorlog beachten!' -i /usr/share/icons/gnome/32x32/status/dialog-error.png"
   fi
fi

# Schritt 3: Externe Sicherung -------------------------------------------------

tempfile=`mktemp /tmp/tarbackup.XXXXXXXX`|| exit 1
echo $crypt_message >>$tempfile
echo "" >>$tempfile

if $message ; then
   su - $user -c "notify-send 'Externe Sicherung startet...' -i /usr/share/icons/gnome/32x32/actions/go-jump.png --hint=int:transient:1"
fi

chmod 0666 $device

tar -cvf $device $data >>$tempfile 2>&1
if [ $? -eq 0 ]; then
   info="erfolgreich"
   echo "Externe Sicherung okay."
else
   info="--> FEHLERHAFT <--"
   echo "WARNUNG: Externe Datensicherung fehlerhaft."
   cat $tempfile | mail -s "WARNUNG: Externe Datensicherung fehlerhaft!" $user@localhost
fi

echo "Die Externe Datensicherung von $jetzt wurde $info abgeschlossen. $crypt_message. $fscheck" | mail -s "Externe Datensicherung $info" $user@localhost
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


# Medienauswurf
$remove

rm -f $tempfile

# HDD ggf. aushaengen
if $snapout ; then
   cd / && sleep 5	
   umount $snap &> /dev/null
fi

# Backup Protokoll des/der PA/DMP PCs als Mail versenden, falls vorhanden:
if [ -r $padmplog ]; then
   cat $padmplog | mail -s "Datensicherung am Windows PC" $user@localhost
   # falls Logdatei zu gross wird, umbenennen:
   if [ `cat $padmplog | wc -l` -gt 1000 ]; then
      mv $padmplog /home/david/trpword/padmplog.old.txt
   fi
fi

echo ""
if $message ; then
   su - $user -c "notify-send 'Externe Sicherung `echo $info` beendet. `echo $ansage`' -i /usr/share/icons/gnome/32x32/actions/go-jump.png --hint=int:transient:1"
fi

#export DISPLAY=`cat $ichbins/DisplayAusgabe`

if $godown ; then
   echo "Das System schaltet in 20 Sekunden ab..." && sleep 20
   /sbin/shutdown -h now
elif $reset ; then
   echo "Das System startet in 120 Sekunden neu..." sleep 120
   /sbin/shutdown -r now
fi

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
#
###############################
### BACKUP POINTS / SCRIPTS ###
###############################
# LOCALHOST
backup   /home/      localhost/
backup   /etc/       localhost/
