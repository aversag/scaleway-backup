# scaleway-backup

backup script for scaleway instances

## setup

Create a .env file to specify some variables :

* SCW_ACCESS_KEY
* SCW_SECRET_KEY
* SCW_DEFAULT_ORGANIZATION_ID
* SCW_DEFAULT_PROJECT_ID
* SCW_DEFAULT_REGION=fr-par
* SCW_DEFAULT_ZONE=fr-par-1
* SCW_API_URL=https://api.scaleway.com
* SIB_BACKUP_TAG=backup
* SIB_ZONE="zone=fr-par-1"
* SIB_MAX_RETENTION=5
* SIB_MAX_BACKUP=5

## needed by the script

* jq
* date
* scw https://github.com/scaleway/scaleway-cli
