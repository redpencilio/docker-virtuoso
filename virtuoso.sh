#!/bin/bash
SETTINGS_DIR=/settings
mkdir -p $SETTINGS_DIR

cd /data

mkdir -p dumps

if [ ! -f ./virtuoso.ini ];
then
  mv /virtuoso.ini . 2>/dev/null
fi

chmod +x /clean-logs.sh
mv /clean-logs.sh . 2>/dev/null

if [ ! -f "$SETTINGS_DIR/.config_set" ];
then
  echo "Converting environment variables to ini file"
  printenv | grep -P "^VIRT_" | while read setting
  do
    section=`echo "$setting" | grep -o -P "^VIRT_[^_]+" | sed 's/^.\{5\}//g'`
    key=`echo "$setting" | sed -E 's/^VIRT_[^_]+_(.*)=.*$/\1/g'`
    value=`echo "$setting" | grep -o -P "=.*$" | sed 's/^=//g'`
    echo "Registering $section[$key] to be $value"
    crudini --set virtuoso.ini $section $key "$value"
  done
  echo "`date +%Y-%m%-dT%H:%M:%S%:z`" >  $SETTINGS_DIR/.config_set
  echo "Finished converting environment variables to ini file"
fi

# NOTE: Make a temporary copy of virtuoso.ini to start Virtuoso
#       on another port while doing initial setup
cp virtuoso.ini /tmp/virtuoso.ini
crudini --set /tmp/virtuoso.ini HTTPServer ServerPort 27015

if [ ! -f ".backup_restored" -a -d "backups" -a ! -z "$BACKUP_PREFIX" ] ;
then
    echo "Start restoring a backup with prefix $BACKUP_PREFIX"
    cd backups
    virtuoso-t +restore-backup $BACKUP_PREFIX +configfile /tmp/virtuoso.ini
    if [ $? -eq 0 ]; then
        cd /data
        echo "`date +%Y-%m-%dT%H:%M:%S%:z`" > .backup_restored
    else
        exit -1
    fi
fi

if [ ! -f ".dba_pwd_set" ];
then
  touch /sql-query.sql
  if [ "$DBA_PASSWORD" ]; then echo "user_set_password('dba', '$DBA_PASSWORD');" >> /sql-query.sql ; fi
  if [ "$SPARQL_UPDATE" = "true" ]; then echo "GRANT SPARQL_UPDATE to \"SPARQL\";" >> /sql-query.sql ; fi
  virtuoso-t +configfile /tmp/virtuoso.ini +wait && isql-v -U dba -P dba < /docker-virtuoso/dump_nquads_procedure.sql && isql-v -U dba -P dba < /sql-query.sql
  kill "$(ps aux | grep '[v]irtuoso-t' | awk '{print $2}')"
  echo "`date +%Y-%m-%dT%H:%M:%S%:z`" >  .dba_pwd_set
fi

VIRTUOSO_DB_PASSWORD=${DBA_PASSWORD:-"dba"}
if [ ! -f ".data_loaded" -a -d "toLoad" ] ;
then
    echo "Start data loading from toLoad folder"
    graph="http://localhost:8890/DAV"

    if [ "$DEFAULT_GRAPH" ]; then graph="$DEFAULT_GRAPH" ; fi
    echo "ld_dir('toLoad', '*', '$graph');" >> /load_data.sql
    echo "rdf_loader_run();" >> /load_data.sql
    echo "exec('checkpoint');" >> /load_data.sql
    echo "WAIT_FOR_CHILDREN; " >> /load_data.sql
    echo "$(cat /load_data.sql)"
    virtuoso-t +configfile /tmp/virtuoso.ini +wait && isql-v -U dba -P "$VIRTUOSO_DB_PASSWORD" < /load_data.sql
    kill $(ps aux | grep '[v]irtuoso-t' | awk '{print $2}')
    echo "`date +%Y-%m-%dT%H:%M:%S%:z`" > .data_loaded
fi

if [[ "$SPARQL_UPDATE" = "true" && ! -f "$SETTINGS_DIR/.user-rights-applied" ]];
then
    echo "WARNING: applying user rights workaround"
    # disable checkpoint audit trail to make sure checkpoints remain consistent
    crudini --set /tmp/virtuoso.ini Parameters CheckpointAuditTrail 0
    echo "DB.DBA.RDF_DEFAULT_USER_PERMS_SET ('nobody', 7);" > /sql-query.sql
    echo "grant execute on DB.DBA.L_O_LOOK_NE to SPARQL_UPDATE;" >> /sql-query.sql
    echo "shutdown();" >> /sql-query.sql
    virtuoso-t +configfile /tmp/virtuoso.ini +wait && isql-v -U dba -P "$VIRTUOSO_DB_PASSWORD" < /sql-query.sql
    touch "$SETTINGS_DIR/.user-rights-applied"
    rm /sql-query.sql
fi


if [ ! -z "$ENABLE_CORS" ];
then
    echo "enabling cors on SPARQL endpoint"
    virtuoso-t +configfile /tmp/virtuoso.ini +wait && isql-v -U dba -P "$VIRTUOSO_DB_PASSWORD" < /docker-virtuoso/add_cors.sql
    kill $(ps aux | grep '[v]irtuoso-t' | awk '{print $2}')
fi

rm /tmp/virtuoso.ini
exec virtuoso-t +wait +foreground
