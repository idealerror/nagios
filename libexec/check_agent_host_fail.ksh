#!/bin/ksh
#------------------------------------------
#
# Created By : Jim DeNisco  
# File Name : check_agent_host_fail.ksh
# Creation Date : 08-02-2011
# Last Modified : Wed 09 Feb 2011 02:38:34 PM EST
# Category : Nagios monitoring tool
# Purpose : check to see if agents failed
# Version : 0.9
#
#------------------------------------------

restart_count="/usr/local/nagios/var/tmp/restart_failed_agent"
logfile="/usr/local/nagios/var/tmp/restart_failed_agent.log"
rscript="/usr/local/nagios/libexec/check_agent_restart.ksh"


# running mysql query to get failed agents

results=`mysql -N -u nagios -pguest --host prod-write  <<EOFMYSQL
use production
select count(*) from agent where in_rotation and state in ('failed','stopped') and instance_name not rlike 'fastsearch';
quit
EOFMYSQL`

#checking to see if any agents failed
if (( $results > 0 )); then

	testhost=`mysql -N -u nagios -pguest --host prod-write  <<EOFMYSQL1
	use production
	select distinct host_name from agent where in_rotation and state in ('failed','stopped') and instance_name not rlike 'fastsearch';
	quit
	EOFMYSQL1`

	host_instance=`mysql -u nagios -pguest --host prod-write  <<EOFMYSQL1
	use production
	select distinct host_name, instance_name from agent where in_rotation and state in ('failed','stopped') and instance_name not rlike 'fastsearch';
	quit
	EOFMYSQL1`

	# if we have a failed host let get host_name  and try to restart if we have not tred to restart already 
	if [[ $(cat $restart_count) == 1 ]]; then
		# write message to nagios to send alert
		echo -n  "CRITICAL agents failed on the following hosts $host_instance.
 Nagios has already tried to restart with no luck.
" 
 		return 2
	else

            echo "1" > $restart_count
            for badhost in $testhost
            do

		# special case: 029
		if [[ "_$badhost" == "_pod-worker-029" ]] ; then
			continue
		fi

		if [[ "_$badhost" == "_pod-worker-032" ]] ; then
			continue
		fi

		if [[ "_$badhost" == "_rlau-laptop" ]] ; then
			continue
		fi

		echo " " >> $logfile
	    	echo $badhost >> $logfile 
	    	echo $(date) >> $logfile

	    	#sshoutput=`sudo /usr/bin/ssh -t -T  $badhost "service podzinger restart"`
		#echo $sshoutput >> $logfile

                # first attempt to stop agent
                echo "Restarting podzinger agent on $badhost" >> $logfile
                sshoutput=$(sudo /usr/bin/ssh -t -T  $badhost "service podzinger stop && service podzinger stop")
                echo $sshoutput >> $logfile

                # count agant threads
                numcount=$(sudo /usr/bin/ssh -t -T  $badhost "ps auxww | grep com.everyzing.ramp.agent | grep -v grep | wc -l")

                if (( $numcount > 0 )); then

			echo "Found zombie agent threads on $badhost. Invoke kill procedure..." >> $logfile

			# kill all remaining threads via PID
			pids=$(sudo /usr/bin/ssh -t -T  $badhost "ps auxww | grep com.everyzing.ramp.agent | grep -v grep " | awk '{print $2}')
			echo "Killing PIDs $pids" >> $logfile
			for kpid in $pids; do
				echo "Killing PID $kpid on $badhost..." >> $logfile
				sshoutput=s$(sudo /usr/bin/ssh -t -T  $badhost "kill -9 $kpid")
                		echo $sshoutput >> $logfile
			done
                fi

                # agents gone, start up again
                sshoutput=$(sudo /usr/bin/ssh -t -T  $badhost "service podzinger start")
                echo $sshoutput >> $logfile

            	if [[ "_$badhost" != "_pod-worker-029" && "_$badhost" != "_pod-worker-032" && "_$badhost" != "_rlau-laptop" ]]; then
			hostlist += $badhost
		fi

            done
	
	    echo  "Restarting agents $hostlist..."
        fi

	return 1
else
	# if all is well then lets find out how many agents are running and get a count
	runningcount=`mysql -u nagios -pguest --host prod-write  <<EOFMYSQL2
	use production
	select distinct count(*) from agent where state != "stopped" or "failed";
	quit
	EOFMYSQL2`

	echo OK $runningcount agents are up and running
	echo 0 > $restart_count
	return 0
fi
