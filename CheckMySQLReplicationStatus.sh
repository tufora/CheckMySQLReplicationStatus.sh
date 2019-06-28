#!/bin/bash

ServiceSystemName="mysql"
ServiceFriendlyName="MySQL"
SQLThreadStatus=$(/usr/bin/mysql -e "SHOW SLAVE STATUS\G" | grep "Slave_SQL_Running:" | awk '{ print $2 }')
IOThreadStatus=$(/usr/bin/mysql -e "SHOW SLAVE STATUS\G" | grep "Slave_IO_Running:" | awk '{ print $2 }')
LagStatus=$(/usr/bin/mysql -e "SHOW SLAVE STATUS\G"| grep "Seconds_Behind_Master:" | awk '{ print $2 }')
LagStatus=$(($LagStatus+0))
ServiceStatusFile="ServiceStatus.txt"
ServiceStatusValue="$(<$ServiceStatusFile)"
ReplicationStatusFile="ReplicationStatus.txt"
ReplicationStatusValue="$(<$ReplicationStatusFile)"
LagStatusFile="LagStatus.txt"
LagStatusValue="$(<$LagStatusFile)"
SlackChannelName="#webhook-test"
SlackWebhookURL="https://hooks.slack.com/services/AAAAA/BBBBBBBB/CCCCCCCCCCCCCC"

CheckStatusFiles() {

    #
    # Making sure that status files are in place
    # Once these are in place we'll perform all checks
    # OK - This is it 
    #

    if [ ! -e "$ServiceStatusFile" ] || [ ! -e "$ReplicationStatusFile" ] || [ ! -e "$LagStatusFile" ]
    then

        if [ ! -e "$ServiceStatusFile" ]
        then

            echo "[ ** ] - Status File: $ServiceStatusFile file not found, creating it now..."
            touch $ServiceStatusFile
            echo "-" >> $ServiceStatusFile
        
        fi

        if [ ! -e "$ReplicationStatusFile" ]
        then

            echo "[ ** ] - Status File: $ReplicationStatusFile file not found, creating it now..."
            touch $ReplicationStatusFile
            echo "-" >> $ReplicationStatusFile
        
        fi

        if [ ! -e "$LagStatusFile" ]
        then

            echo "[ ** ] - Status File: $LagStatusFile file not found, creating it now..."
            touch $LagStatusFile
            echo "-" >> $LagStatusFile
        
        fi

    else

        echo "[ OK ] - Status File: All needed files for our checks were found, we'll move to our next step..."

        CheckServiceStatus
        CheckThreadsStatus
        CheckLagStatus

    fi

}

CheckServiceStatus() {

    #
    # Checking service status
    #
    # 0 - Service is not running
    # 1 - Service is running
    #

    ServiceStatus=`systemctl is-active $ServiceSystemName.service`
    
    if [[ ${ServiceStatus} == 'active' ]]
    then
    
        if [[ ${ServiceStatusValue} == '-' ]]
        then

            echo "[ ** ] - $ServiceFriendlyName Service: Is running but this is our very first check, let's write that to $ServiceStatusFile file..."

            > $ServiceStatusFile
            echo "1" >> $ServiceStatusFile

        elif [[ ${ServiceStatusValue} == '1' ]]
        then

            echo "[ OK ] - $ServiceFriendlyName Service: Is up and running, no need to panic..."

            > $ServiceStatusFile
            echo "1" >> $ServiceStatusFile

        elif [[ ${ServiceStatusValue} == '0' ]]
        then

            echo "[ OK ] - $ServiceFriendlyName Service: Is currently running, previously was marked as being down..."

            slack \
                -a "${ServiceFriendlyName} Notifications" \
                -t "Service Status: ${HOSTNAME}" \
                -m "MySQL service is now *back online* and running like a charm... (¬‿¬)" \
                -s "good" \
                -c "${SlackChannelName}" \
                -w $SlackWebhookURL

            > $ServiceStatusFile
            echo "1" >> $ServiceStatusFile

        else

            echo "[ ?? ] - $ServiceFriendlyName Service: Unknown value found on $ServiceStatusFile, recreating this file..."

            slack \
                -a "${ServiceFriendlyName} Notifications" \
                -t "Service Status: ${HOSTNAME}" \
                -m "Unknown value found on ${ServiceStatusFile} file, no need to panic as the service is running fine and it has been automatically recreated with its default value. ¯\_(ツ)_/¯ " \
                -s "info" \
                -c "${SlackChannelName}" \
                -w $SlackWebhookURL

            > $ServiceStatusFile
            echo "1" >> $ServiceStatusFile

        fi
    
    elif [[ ${ServiceStatus} != 'active' ]]
    then
    
        if [[ ${ServiceStatusValue} == '1' ]]
        then

            echo "[ !! ] - $ServiceFriendlyName Service: Is NOT running, we'll stop here and send out a notification message..."

            slack \
                -a "${ServiceFriendlyName} Notifications" \
                -t "Service Status: ${HOSTNAME}" \
                -m "MySQL service is *not running*, take a deep breath and try to see what's going on... I would start by checking first the Disk Space (`df -h`), CPU or Memory (`htop`) and even a `tail -f /var/log/mysqld.log` would be good." \
                -s "danger" \
                -c "${SlackChannelName}" \
                -w $SlackWebhookURL

            > $ServiceStatusFile
            echo "0" >> $ServiceStatusFile

            exit 1

        elif [[ ${ServiceStatusValue} == '0' ]]
        then
        
            echo "[ !! ] - $ServiceFriendlyName Service: Is NOT running and a notification message has been sent already..."

        fi
    
    fi
}


CheckThreadsStatus() {

    #
    # Checking MySQL Replication Status, if it's running or not
    #
    # 0 - MySQL Replication is stopped 
    # 1 - MySQL Replication is running
    # 10 - SQL Thread is not running 
    # 20 - IO Thread is not running
    # 

    # First check, no issue or recovery check
    if [[ ${SQLThreadStatus} == 'Yes' ]] && [[ ${IOThreadStatus} == 'Yes' ]]
    then

        if [[ ${ReplicationStatusValue} == '-' ]]
        then

            echo "[ ** ] - $ServiceFriendlyName Replication Status: Replication is fine but this is our very first check, let's write that to $ReplicationStatusFile file..."

            > $ReplicationStatusFile
            echo "1" >> $ReplicationStatusFile

        elif [[ ${ReplicationStatusValue} == '1' ]]
        then

            echo "[ OK ] - $ServiceFriendlyName Replication Status: Replication is up and running, no need to panic at all..."

        elif [[ ${ReplicationStatusValue} == '0' ]] || [[ ${ReplicationStatusValue} == '10' ]] || [[ ${ReplicationStatusValue} == '20' ]]
        then

            echo "[ OK ] - $ServiceFriendlyName Replication Status: Replication is up and running now..."

            slack \
                -a "${ServiceFriendlyName} Notifications" \
                -t "Replication Status: ${HOSTNAME}" \
                -m "Both *SQL and IO Threads* are now *running again*. No further action needed maybe except a coffee for you just to keep an eye on the replication lag for a while..." \
                -s "good" \
                -c "${SlackChannelName}" \
                -w $SlackWebhookURL

                > $ReplicationStatusFile
                echo "1" >> $ReplicationStatusFile

        fi

    elif [[ ${SQLThreadStatus} == 'No' ]] && [[ ${IOThreadStatus} == 'Yes' ]]
    then

        if [[ ${ReplicationStatusValue} == "1" ]] || [[ ${ReplicationStatusValue} == "20" ]]
        then

            echo "[ !! ] - $ServiceFriendlyName Replication Status: SQL Thread is not running..."

            slack \
                -a "${ServiceFriendlyName} Notifications" \
                -t "Replication Status: ${HOSTNAME}" \
                -m "Bad news, *SQL Thread is not running* meaning that the replication is stopped." \
                -s "danger" \
                -c "${SlackChannelName}" \
                -w $SlackWebhookURL

                > $ReplicationStatusFile
                echo "10" >> $ReplicationStatusFile

            elif [[ ${ReplicationStatusValue} == "10" ]]
            then

                echo "[ !! ] - $ServiceFriendlyName Replication Status: SQL Thread is not running but we have already sent a notification message..."

            fi

    elif [[ ${SQLThreadStatus} == 'Yes' ]] && [[ ${IOThreadStatus} == 'No' ]]
    then

        if [[ ${ReplicationStatusValue} == "1" ]] || [[ ${ReplicationStatusValue} == "10" ]]
        then

            echo "[ !! ] - $ServiceFriendlyName Replication Status: IO Thread is not running..."

            slack \
                -a "${ServiceFriendlyName} Notifications" \
                -t "Replication Status: ${HOSTNAME}" \
                -m "Bad news, *IO Thread is not running* meaning that the replication is stopped." \
                -s "danger" \
                -c "${SlackChannelName}" \
                -w $SlackWebhookURL

                > $ReplicationStatusFile
                echo "20" >> $ReplicationStatusFile

        elif [[ ${ReplicationStatusValue} == "20" ]]
        then

            echo "[ !! ] - $ServiceFriendlyName Replication Status: IO Thread is not running but we have already sent a notification message..."

        fi

    else

        echo "[ !! ] - $ServiceFriendlyName Replication Status: Something fishy is going on as I am not able to get the status..."

    fi


    # Replication is clearly broken or is been manually stopped
    if [[ ${SQLThreadStatus} == 'No' ]] && [[ ${IOThreadStatus} == 'No' ]]
    then

        if [[ ${ReplicationStatusValue} == '0' ]]
        then

            echo "[ !! ] - $ServiceFriendlyName Replication Status: Replication is down but we've already sent a notification message..."

        elif [[ ${ReplicationStatusValue} == '1' ]] || [[ ${ReplicationStatusValue} == '10' ]] || [[ ${ReplicationStatusValue} == '20' ]]
        then

            echo "[ !! ] - $ServiceFriendlyName Replication Status: Replication is down and we'll send out a notification message..."

            slack \
                -a "${ServiceFriendlyName} Notifications" \
                -t "Replication Status: ${HOSTNAME}" \
                -m "MySQL *replication is not running*, both IO and SQL threads being marked as down. If, and only if the replication has been manullay stopped you can ignore this message." \
                -s "danger" \
                -c "${SlackChannelName}" \
                -w $SlackWebhookURL

                > $ReplicationStatusFile
                echo "0" >> $ReplicationStatusFile

        elif [[ ${SQLThreadStatus} == 'No' ]] && [[ ${IOThreadRunning} == 'Yes' ]]
        then

            echo "[ !! ] - MySQL Replication Status: Error found, SQL Thread is NOT running. We'll send out a notification message..."

            slack \
                -a "${ServiceFriendlyName} Notifications" \
                -t "Replication Status: ${HOSTNAME}" \
                -m "Bad news, *SQL Thread is not running*, IO Thread instead looks to be fine. Please check what is going on as the replication is now broken." \
                -s "danger" \
                -c "${SlackChannelName}" \
                -w $SlackWebhookURL

                > $ReplicationStatusFile
                echo "10" >> $ReplicationStatusFile

        elif [[ ${IOThreadRunning} == 'No' ]] && [[ ${SQLThreadStatus} == 'Yes' ]]
        then

            echo "[ !! ] - ${ServiceFriendlyName} Replication Status: Error found, IO Thread is NOT running. We'll send out a notification message..."

            slack \
                -a "${ServiceFriendlyName} Notifications" \
                -t "Replication Status: ${HOSTNAME}" \
                -m "Bad news, *IO Thread is not running*, SQL Thread instead looks to be fine. Please check what is going on as the replication is now broken." \
                -s "danger" \
                -c "${SlackChannelName}" \
                -w $SlackWebhookURL

                > $ReplicationStatusFile
                echo "20" >> $ReplicationStatusFile

        fi

    fi

}


CheckLagStatus() {

    #
    # Checking MySQL Replication Lag, if there's any
    # 
    # 0 - No lag, under ten minutes
    # 1 - Under 1 hour
    # 2 - Between 1 and 6 hours
    # 3 - Between 6 and 12 hours
    # 4 - Over 12 hours
    #

    # 
    # Under ten minutes
    # Level 0
    #

    if [ $LagStatus -ge 0 ] && [ "$LagStatus" -lt 600 ]
    then

        LagTime="$LagStatus seconds"

        if [[ ${LagStatusValue} == '-' ]]
        then

            echo "[ OK ] - $ServiceFriendlyName Replication Lag: No lag detected but this is our very first check, let's write that to $LagStatusFile file..."

            > $LagStatusFile
            echo "0" >> $LagStatusFile

        elif [[ ${LagStatusValue} == '0' ]]
        then

            echo "[ OK ] - $ServiceFriendlyName Replication Lag: $LagTime behind master, no notification will be sent and to be fair that would be very silly..."

        elif [[ ${LagStatusValue} == '1' ]] || [[ ${LagStatusValue} == '2' ]] || [[ ${LagStatusValue} == '3' ]] || [[ ${LagStatusValue}  == '4' ]]
        then

            echo "[ OK ] - $ServiceFriendlyName Replication Lag: Happy days, the slave is now back in sync..."

            slack \
                -a "${ServiceFriendlyName} Notifications" \
                -t "Replication Lag: ${HOSTNAME}" \
                -m "Good news, this slave is now back in sync." \
                -s "good" \
                -c "${SlackChannelName}" \
                -w $SlackWebhookURL

            > $LagStatusFile
            echo "0" >> $LagStatusFile

        fi

    fi

    #
    # Under one hour
    # Level 1
    #

    if [ $LagStatus -gt 600 ] && [ $LagStatus -lt 3600 ]
    then

        LagTime="$(($LagStatus/60)) minute(s)"

        if [[ ${LagStatusValue} == '0' ]] || [[ ${LagStatusValue} == '2' ]] || [[ ${LagStatusValue} == '3' ]] || [[ ${LagStatusValue}  == '4' ]]
        then

            echo "[ !! ] - $ServiceFriendlyName Replication Lag: We're just a bit over $LagTime behind master, we'll send out a nitification message but nothing to worry about..."

            slack \
                -a "${ServiceFriendlyName} Notifications" \
                -t "Replication Lag: ${HOSTNAME}" \
                -m "This slave is just a bit over ${LagTime} behind master, this message is more of a heads up, nothing to worry about for now as a small lag from time to time is expected. Next check should give us a better overview, stay tuned and check your messages in a few minutes." \
                -s "info" \
                -c "${SlackChannelName}" \
                -w $SlackWebhookURL

            > $LagStatusFile
            echo "1" >> $LagStatusFile

        elif [[ ${LagStatusValue} == '1' ]]
        then

            echo "[ OK ] -  $ServiceFriendlyName Replication Lag: We already sent a notification message..."

        fi

    fi

    #
    # Between one and six hours
    # Level 2
    #

    if [ $LagStatus -gt 3600 ] && [ $LagStatus -lt 21600 ]
    then

        LagTime="$(($LagStatus/3600)) hour(s)"

        if [[ ${LagStatusValue} == '0' ]] || [[ ${LagStatusValue} == '1' ]] || [[ ${LagStatusValue} == '3' ]] || [[ ${LagStatusValue}  == '4' ]]
        then

            echo "[ !! ] - $ServiceFriendlyName Replication Lag: We're $LagTime behind master, we'll send out a nitification message but nothing to worry about..."

            slack \
                -a "${ServiceFriendlyName} Notifications" \
                -t "Replication Lag: ${HOSTNAME}" \
                -m "This slave is now ${LagTime} behind master which is not ideal but due amount of data we can't say it's dangerous either. We'll keep an eye on this for you and if it passes over 6 hours threshold then we'll let you know." \
                -s "warning" \
                -c "${SlackChannelName}" \
                -w $SlackWebhookURL

            > $LagStatusFile
            echo "2" >> $LagStatusFile

        elif [[ ${LagStatusValue} == '2' ]]
        then

            echo "[ OK ] -  $ServiceFriendlyName Replication Lag: We already sent a notification message..."

        fi

    fi

    #
    # Over six hours but less than twelve
    # Level 3
    #

    if [ $LagStatus -ge 21600 ] && [ $LagStatus -le 43200 ]
    then

        LagTime="$(($LagStatus/3600)) hours"

        if [[ ${LagStatusValue} == '0' ]] || [[ ${LagStatusValue} == '1' ]] || [[ ${LagStatusValue} == '2' ]] || [[ ${LagStatusValue}  == '4' ]]
        then

            echo "[ !! ] - $ServiceFriendlyName Replication Lag: We're $LagTime behind master, we'll send out a nitification message but nothing to worry about..."

            slack \
                -a "${ServiceFriendlyName} Notifications" \
                -t "Replication Lag: ${HOSTNAME}" \
                -m "Oh man... is now *${LagTime} behind master* and it does not look good. Please check what is going on, a good starting point would be network latency and also disk speed. We will leave it with you now but if it passes over 12 hours threshold will let you know." \
                -s "danger" \
                -c "${SlackChannelName}" \
                -w $SlackWebhookURL

            > $LagStatusFile
            echo "3" >> $LagStatusFile

        elif [[ ${LagStatusValue} == '3' ]]
        then

            echo "[ OK ] -  $ServiceFriendlyName Replication Lag: We already sent a notification message..."

        fi

    fi

    # 
    # Over twelve hours
    # Level 4
    #

    if [ $LagStatus -gt 43200 ]
    then

        LagTime="$(($LagStatus/3600)) hours"

        if [[ ${LagStatusValue} == '0' ]] || [[ ${LagStatusValue} == '1' ]] || [[ ${LagStatusValue} == '2' ]] || [[ ${LagStatusValue}  == '3' ]]
        then

            echo "[ !! ] - $ServiceFriendlyName Replication Lag: We're $LagTime behind master, we'll send out a nitification message but nothing to worry about..."

            slack \
                -a "${ServiceFriendlyName} Notifications" \
                -t "Replication Lag: ${HOSTNAME}" \
                -m "Really bad news, this slave is now *${LagTime} behind master* and to be fair this is really bad, quite a huge lag I would say and a self-recovery from this point forward is pure lottery. Check what is going on with this slave and shout if any help needed." \
                -s "danger" \
                -c "${SlackChannelName}" \
                -w $SlackWebhookURL

            > $LagStatusFile
            echo "4" >> $LagStatusFile

        elif [[ ${LagStatusValue} == '4' ]]
        then

            echo "[ OK ] -  $ServiceFriendlyName Replication Lag: We already sent a notification message..."

        fi

    fi

}

CheckStatusFiles