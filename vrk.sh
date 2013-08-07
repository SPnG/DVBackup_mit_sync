#!/bin/bash



# Pruefung auf Viren und Rootkits
# Muss als root laufen.
#
# Speedpoint nG (FW), Stand: Juli 2012



# Hier bitte anpassen: ---------------------------------------
#
USER="david@localhost"
TOOL="/install/skripte/notify.sh"
VSCAN="/home/david/trpword"      
#
# ------------------------------------------------------------









# Pruefungen auf Rootrechte:
#
if [ ! "`id -u`" -eq "0" ]; then
   echo "Sorry, nur fuer root ausfuehrbar."
   exit 1
fi

# ------------------------------------------------------------

# Rootkit Suche

LOG=`mktemp /tmp/rk.XXXXXXXXXX` || exit 1

WARN=0
INFECT=0
MESSAGE="Keine Rootkits gefunden."

echo "Rootkit Suche von `date`" >$LOG
echo "" >>$LOG
chkrootkit 2>&1 >>$LOG
echo "" >>$LOG

INFECT=`grep "INFECTED" <$LOG`
WARN=`grep "WARNING" <$LOG`
if [ -z "$INFECT" -o -z "$WARN" ]; then
   echo $MESSAGE
   echo ""
   echo $MESSAGE | mail -s "Rootkit Suche ok :-)" $USER
else
   MAILFILE="/tmp/rk-mailfile.tmp"
   MESSAGE="ACHTUNG, Rootkitbefall entdeckt!"
   echo $MESSAGE
   echo ""
   echo $INFECT >$MAILFILE
   echo "----------------------" >>$MAILFILE
   echo $WARN >>$MAILFILE
   cat $MAILFILE | mail -s "Rootkit Alarm!" $USER
   $TOOL -m "Rootkit Alarm!"
   rm -f $MAILFILE
fi
rm -f $LOG

# ------------------------------------------------------------

# Virensuche

#LOG=`mktemp /tmp/vir.XXXXXXXXXX` || exit 1

#echo "Virenscan von `date`" >$LOG
#echo "" >>$LOG
#echo "Aktualisierung der Virenschutzdaten:"
#freshclam 2>&1 >>$LOG
#echo "" >>$LOG
#clamscan --log=$LOG --bell --infected $pfad

#if [ `cat $LOG | grep "Infected" | awk '{print $3}'` -ne 0 ]; then
#   echo "Virenfund in $VSCAN!"
#   cat $LOG | mail -s "Virenalarm!" $USER
#   $TOOL -m "Virenalarm!"
#else
#   echo "Keine Viren in $VSCAN gefunden."
#   echo ""
#   cat $LOG | mail -s "Virenpruefung ok :-)" $USER
#fi
#rm $LOG


exit 0
