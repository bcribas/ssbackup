#!/bin/bash
# This script is distributed as is, under GPLv2 license

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

function checkalive()
{
  local machine=$1
  ping -q -c5 -W1 $machine &>/dev/null &&
    ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no $machine true
}

function updatebkpdir()
{
  local machine=$1
  local origin=$2
  local destdir=$2
  local now=$3
  local checkpoint=$CHECKPOINTSTRING
  if [[ "$(date +%d)" != "$CHECKPOINTDAY" ]]; then
    checkpoint=""
  fi

  if [[ "$destdir" == "/" ]]; then
    destdir=root
  else
    destdir=$(sed -e 's#^/##' <<< "$destdir")
    destdir=$(tr '/' '_' <<< "$destdir")
  fi

  cd $BACKUPDIR/$machine/$destdir
  cp -al next $(date --date=@$now +%F-%T)

  #XXX make it more graciously
  while (( $(ls |grep -v next|grep -v "$CHECKPOINTSTRING"|wc -l|awk '{print $1}') > MAXBKP )); do
    echo "Removing $(ls |grep -v next|grep -v "$CHECKPOINTSTRING"|head -n1)"
    rm -rf $(ls |grep -v next|grep -v "$CHECKPOINTSTRING"|head -n1)
  done
  cd $OLDPWD
}

function deploynext()
{
  local work=$1

  #should not enter here.
  if [[ ! -d "$work" ]]; then
    echo "$work: Does not exist. Aborting"
    exit
  fi

  cd $work
  LAST="$(ls|tail -n1)"
  if [[ "x$LAST" == "x" ]]; then
    mkdir next
  else
    printf "mv $LAST next\n"
    mv $LAST next
    printf "Copying with hardlinks next to $LAST"
    cp -al next $LAST
    echo .
  fi
  cd $OLDPWD
}

function fazer-backup()
{
  local machine=$1
  local origindir=$2
  local destdir=$2
  local now=$3
  local rsyncparam="$4"
  local especialending=$5
  if [[ "$origindir" == "/" ]]; then
    destdir=root
  else
    destdir=$(sed -e 's#^/##' <<< "$origindir")
    destdir=$(tr '/' '_' <<< "$destdir")
  fi

  local destination=${BACKUPDIR}/$machine/$destdir

  # check if it is our first backup on this machine/origindir
  if [[ ! -d "$destination" ]]; then
    mkdir -p "$destination/next"
  elif [[ ! -d "$destination/next" ]]; then
    deploynext $destination
  fi
  rsync -aHx -S $rsyncparam --delete-during --delete-excluded --verbose \
    --stats --numeric-ids $machine:$origindir $destination/next

}

#Some default variables
NOW="$(date +%s)"
CONFFILE=$1
CONFFILE=${CONFFILE:=/etc/ssbackup/ssbackup.conf}
BACKUPDIR=${BACKUPDIR:=/backup}
LOGDIR=${LOGDIR:=/var/log/ssbackup}
MACHINECONF=${MACHINECONF:=/etc/ssbackup/machine.conf}
LASTBKPSTATE=${LASTBKPSTATE:=/var/cache/ssbackup.laststate}
MAXBKP=${MAXBKP:=90}
RUNFILE=${RUNFILE:=/var/run/ssbackup.pid}
CHECKPOINTSTRING=${CHECKPOINTSTRING:=checkpoint}
CHECKPOINTDAY=${CHECKPOINTDAY:=01}
AGRESSIVELOG=${AGRESSIVELOG:=f}

if [[ -e "$CONFFILE" ]]; then
  source $CONFFILE || exit 1
fi

#check for a running instance
if [[ -e "$RUNFILE" ]]; then
  exit 0
fi

if [[ ! -d "$LOGDIR" ]]; then
  echo "$LOGDIR: does not exist"
  exit 1
fi

exec &> $LOGDIR/execution-$NOW
if [[ "$AGRESSIVELOG" == "t" ]]; then
  set -x
fi

echo $$ > $RUNFILE


#Read Last backup state
declare -A LASTBKP
if [[ -e "$LASTBKPSTATE" ]]; then
  while read subscript value; do
    LASTBKP[$subscript]=$value
  done < "$LASTBKPSTATE"
fi

#Read conf file
if [[ ! -e "$MACHINECONF" ]]; then
  echo "Missing $MACHINECONF"
  exit 1
fi

declare -A BKPINTERVAL BKPPARAMS
while read machine dir interval rsyncparams; do
  if [[ "$machine" =~ "#" ]]; then continue; fi
  BKPINTERVAL[$machine,$dir]=$interval
  BKPPARAMS[$machine,$dir]="$rsyncparams"
  [[ "${LASTBKP[$machine,$dir]}" == "" ]] && LASTBKP[$machine,$dir]=0
done < "$MACHINECONF"

# check if need backup
# this is done to avoid unnecessary mount of /backup
# we don't want to wake our backup disk very often.
need=0
for machinedir in ${!BKPINTERVAL[@]}; do
  if (( (NOW - ${LASTBKP[$machinedir]})/60 >= ${BKPINTERVAL[$machinedir]}*60 )) &&
      checkalive $(cut -d, -f1 <<< $machinedir) ;then
    ((need++))
  fi
done

(( need == 0 )) && rm $RUNFILE && exit 0

if ! df -H "$BACKUPDIR" | grep -q "$BACKUPDIR" ; then
  mount $BACKUPDIR
  RESP=$?
  if (( RESP != 0 )); then
    echo "Could not mount $BACKUPDIR. Is it in /fstab?"
    exit $RESP
  fi
fi

if [[ ! -e "$BACKUPDIR/.alive" ]]; then
  echo "Can't find '$BACKUPDIR/.alive', exiting now"
  echo " You should create this file in order to enable the mountpoint to"
  echo " receive backups"
  exit 1
fi


for machinedir in ${!BKPINTERVAL[@]}; do
  if (( (NOW - ${LASTBKP[$machinedir]})/60 >= ${BKPINTERVAL[$machinedir]}*60 ));then
    machine="$(cut -d',' -f1 <<< "$machinedir")"
    dir="$(cut -d',' -f2 <<< "$machinedir")"
    #if we can ping and ssh into the machine
    if checkalive $machine; then
      BKPLOGFILE=$LOGDIR/$machine-$(tr '/' '_' <<< "$dir")-$NOW
      fazer-backup "$machine" "$dir" "$NOW" "${BKPPARAMS[$machinedir]}" &> $BKPLOGFILE
      if ! tail $BKPLOGFILE|grep -q "connection unexpectedly closed"; then
        LASTBKP[$machinedir]=$NOW
      fi
    fi
  fi
done

#after backing up some (or all) machines, run for delayed update of destdir
#we can't store them in next forever. 'next' will be our point of real files
#(no hardlinks).
for machinedir in ${!BKPINTERVAL[@]}; do
  machine="$(cut -d',' -f1 <<< "$machinedir")"
  dir="$(cut -d',' -f2 <<< "$machinedir")"
  if [[ "${LASTBKP[$machinedir]}" == "$NOW" ]]; then
    updatebkpdir $machine $dir $NOW
  fi
done

sync
umount /backup

#update last backup state file
for machinedir in ${!BKPINTERVAL[@]}; do
  echo "$machinedir ${LASTBKP[$machinedir]}"
done > $LASTBKPSTATE

rm $RUNFILE
