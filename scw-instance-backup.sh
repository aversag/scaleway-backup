#!/bin/bash
#
# Started by @Grraahaam
# Continued by @Aversag
#
# Description :
#       Script to manage Scaleway server/instance backups,
#       It will create a backup for the given servers/instances (tag filter)
#       and delete the backups that's too old (N days)
#
# /!\ WARNING /!\ Only tested on servers/instances with single attached volumes
#

# Format/color output codes
if [ ! -z $TERM ]; then
    BOLD=$(tput bold); NORM=$(tput sgr0);
fi

RED='\033[0;31m'; BRED=${RED}${BOLD}
GREEN='\033[0;32m'; BGREEN=${GREEN}${BOLD}
YELLOW='\033[1;33m'; BYELLOW=${YELLOW}${BOLD}
WHITE='\033[1;37m'; BWHITE=${WHITE}${BOLD}
NC='\033[0m'; RESET=${NC}${NORM}

############################################# FUNCTIONS

_query() {
    echo ${1} | base64 -d | jq -r ${2}
}

# Taking only the year-month-day (daily backup, more precision would be useless)
get_date() {
    date --utc --date="$1" +"%Y%m%d"
}

############################################# VARIABLES

# Set configuration environment
export $(grep -v '^#' $SIB_ENV_PATH.env | xargs)

DRY_RUN=$([[ $1 == "dry-run" ]] && echo 1 || echo 0)
TODAY=$(date +"%Y-%m-%d")
SIB_MAX_RETENTION_DATE=$(get_date $(date --date="${TODAY} -${SIB_MAX_RETENTION} day" +%Y-%m-%d))

############################################# BACKUP PROCESS

printf "\n🚧 Scaleway Instance Backup v0.2 (beta) 🚧\n\n"
printf "🤞 @Grraahaam\n\n"

[ $DRY_RUN -eq 0 ] && printf "Dry run : ✗\n" || printf "Dry run : ✓\n"
printf "Max. retention days : \t\t${BWHITE}$SIB_MAX_RETENTION${RESET}\n"
printf "Max. retention date : \t\t${BWHITE}$SIB_MAX_RETENTION_DATE${RESET}\n"
printf "Max. backups (per server) : \t${BWHITE}$SIB_MAX_BACKUP${RESET}\n\n"

printf "🕖 Searching your servers and backups...\n\n"

# Fetch the list only once
INSTANCES=$(scw instance server list $SIB_ZONE -o json | jq -r '.[] | @base64')
IMAGES=$(scw instance image list $SIB_ZONE -o json | jq -r '.[] | @base64')
SNAPSHOTS=$(scw instance snapshot list $SIB_ZONE -o json | jq -r '.[] | @base64')

for instance in $(echo "$INSTANCES"); do

    active=$([[ $(_query "$instance" '.state') == "running" ]] && echo "$BGREEN" || echo "$BRED")

    printf "Name: ${BWHITE}$(_query "$instance" '.name')${RESET} (${active}$(_query "$instance" '.state')${RESET})\n"
    printf "ID: ${WHITE}$(_query "$instance" '.id') ${NC}\n"
    printf "Volume ID: ${WHITE}$(_query "$instance" '.volumes[].id') ${NC}\n"

    # Define current instance/server variables
    count=0
    deleted=0
    create=1

    for image in $(echo "$IMAGES"); do

        if [[ "$(_query "$image" '.server_id')" == "$(_query "$instance" '.id')" ]]; then

            # Increment the backup counter (per server/instance)
            (( count++ ))

            printf "[${BYELLOW}${count}${RESET}] 💿 Associated image:\n"
            printf "\tname:\t\t${LGRAY}$(_query "$image" '.name')${RESET}\n"
            printf "\tid:\t\t${LGRAY}$(_query "$image" '.id')${RESET}\n"
            printf "\tcreation date:\t${LGRAY}$(get_date $(_query "$image" '.creation_date'))${RESET}\n"

            # Images/Snapshots list is ordered ASC, so the latest backups are at the end of the list
            if [[ $count > $SIB_MAX_BACKUP ]] || [[ $(get_date $(_query "$image" '.creation_date')) -lt "$SIB_MAX_RETENTION_DATE" ]]; then

                printf "[${BYELLOW}${count}${RESET}] 🔥 ${BRED}Deleting old image and associated snapshot!${RESET}\n"
                printf "\tname:\t\t${LGRAY}$(_query "$image" '.name')${RESET}\n"
                printf "\tid:\t\t${LGRAY}$(_query "$image" '.id')${RESET}\n"
                printf "\tcreation date:\t${LGRAY}$(get_date $(_query "$image" '.creation_date'))${RESET}\n"

                if [ $DRY_RUN -eq 0 ]; then
                    scw instance image delete $(_query "$image" '.id') $SIB_ZONE
                    scw instance snapshot delete $(_query "$image" '.root_volume.id') $SIB_ZONE
                else
                    printf "\nDRY-RUN : scw instance image delete $(_query "$image" '.id') $SIB_ZONE\n"
                    printf "DRY-RUN : scw instance snapshot delete $(_query "$image" '.root_volume.id') $SIB_ZONE\n"
                fi

                # Increment deleted backup counter
                (( delete++ ))
            fi

            # Should we take a snapshot?
            create=$([[ $(get_date "$TODAY") > $(get_date $(_query "$image" '.creation_date')) ]] && echo 1 || echo 0)
        fi
    done

    for snapshot in $(echo "$SNAPSHOTS"); do

        if [[ $(get_date $(_query "$snapshot" '.creation_date')) -lt "$SIB_MAX_RETENTION_DATE" ]]; then

            printf "[${BYELLOW}${count}${RESET}] 🔥 ${BRED}Deleting old snapshot!${RESET}\n"
            printf "\tname:\t\t${LGRAY}$(_query "$snapshot" '.name')${RESET}\n"
            printf "\tid:\t\t${LGRAY}$(_query "$snapshot" '.id')${RESET}\n"
            printf "\tcreation date:\t${LGRAY}$(get_date $(_query "$snapshot" '.creation_date'))${RESET}\n"

            if [ $DRY_RUN -eq 0 ]; then
                scw instance snapshot delete $(_query "$snapshot" '.id') $SIB_ZONE
            else
                printf "\nDRY-RUN : scw instance snapshot delete $(_query "$snapshot" '.id') $SIB_ZONE\n"
            fi

        fi

    done

    # Only create a backup if none today
    if [ $create -ne 0 ]; then

        printf "\n📀 Snapshotting! (${BYELLOW}backup_$(_query "$instance" '.name')_$TODAY${RESET})\n"

        if [ $DRY_RUN -eq 0 ]; then
            scw instance server backup "$(_query "$instance" '.id')" name="backup_$(_query "$instance" '.name')_$TODAY" $SIB_ZONE
        else
            printf "\nDRY-RUN : scw instance server backup $(_query "$instance" '.id') name=backup_$(_query "$instance" '.name')_$TODAY $SIB_ZONE\n"
        fi
    fi

    printf "\n------------------------\n\n"

done

printf "Backup complete!👍\n\n"

