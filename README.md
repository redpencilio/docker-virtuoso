# Virtuoso docker
Docker for hosting Virtuoso.

The Virtuoso is built from a specific commit SHA in https://github.com/openlink/virtuoso-opensource.
This image is currently build from commit [f3d88f16bca4274265160e098be3ba3c7d68341c](https://github.com/openlink/virtuoso-opensource/commit/f3d88f16bca4274265160e098be3ba3c7d68341c), which corresponds to virtuoso 7.2.10. You can build this image from a different commit by providing the correct commit id as the `VIRTUOSO_COMMIT` [build argument](https://docs.docker.com/engine/reference/commandline/build/#set-build-time-variables---build-arg).

## Running your Virtuoso
    docker run --name my-virtuoso \
        -p 8890:8890 -p 1111:1111 \
        -e DBA_PASSWORD=myDbaPassword \
        -e SPARQL_UPDATE=true \
        -e DEFAULT_GRAPH=http://www.example.com/my-graph \
        -v /my/path/to/the/virtuoso/db:/data \
        -d redpencil/virtuoso

The Virtuoso database folder is mounted in `/data`.

The Docker image exposes port 8890 and 1111.

## Docker compose
The image can also be configured and used via docker-compose.

```
db:
  image: redpencil/virtuoso:1.0.0
  environment:
    SPARQL_UPDATE: "true"
    DEFAULT_GRAPH: "http://www.example.com/my-graph"
  volumes:
    - ./data/virtuoso:/data
  ports:
    - "8890:8890"
```
## Upgrading
There are multiple ways of upgrading your virtuoso version. The procedure described here takes a bit longer, but will result in using all of the latest features of your new virtuoso version and optimizes your DB size on disk.

NOTE: Upgrading virtuoso is a procedure to be done with great care, make sure to have backups before starting. 

### 1. dump nquads
When upgrading it's recommended (and sometimes required!) to first dump to quads using the `dump_nquads` procedure:
```sh
docker compose exec virtuoso isql-v
SQL> dump_nquads ('dumps', 1, 1000000000, 1);
```

### 2. stop the db
```sh
docker compose stop virtuoso
```
### 3. remove old db and related files
When this has completed move the dumps folder to the toLoad folder. Make sure to remove the following files:
- `.data_loaded` 
- `.dba_pwd_set`
- `virtuoso.db`
- `virtuoso.trx`
- `virtuoso.pxa`
- `virtuoso-temp.db`

```sh
mv data/db/dumps/* data/db/toLoad
rm data/db/virtuoso.{db,trx,pxa} data/db/virtuoso-temp.db data/db/.data_loaded data/db/.dba_pwd_set
```

Consider truncating or removing the virtuoso.log file as well. 

### 4. update virtuoso version
Modify the docker-compose file to update the virtuoso version

```diff
   virtuoso:
-    image: redpencil/virtuoso:1.0.0
+    image: redpencil/virtuoso:1.2.0-rc.1
```
### 5. start the db
Start the DB and monitor the logs, importing the nquads might take a long time .
```sh
docker compose up -d virtuoso
docker compose logs -f virtuoso
```
After that your application can be started again and you should be good to go.

## Configuration
### dba password
The `dba` password can be set at container start up via the `DBA_PASSWORD` environment variable. If not set, the default `dba` password will be used.

### SPARQL update permission
The `SPARQL_UPDATE` permission on the SPARQL endpoint can be granted by setting the `SPARQL_UPDATE` environment variable to `true`.

### CORS
You may want to enable basic CORS headers on the SPARQL endpoint, this can be done by setting the `ENABLE_CORS` environment variable to any value. If not set (the default), no cors headers are sent.

### .ini configuration
All properties defined in `virtuoso.ini` can be configured via the environment variables. The environment variable should be prefixed with `VIRT_` and have a format like `VIRT_$SECTION_$KEY`. `$SECTION` and `$KEY` are case sensitive. They should be CamelCased as in `virtuoso.ini`. E.g. property `ErrorLogFile` in the `Database` section should be configured as `VIRT_Database_ErrorLogFile=error.log`.

## Dumping your Virtuoso data as quads
Enter the Virtuoso docker, open ISQL and execute the `dump_nquads` procedure. The dump will be available in `/my/path/to/the/virtuoso/db/dumps`.

    docker exec -it my-virtuoso bash
    isql-v -U dba -P $DBA_PASSWORD
    SQL> dump_nquads ('dumps', 1, 10000000, 1);

For more information, see http://virtuoso.openlinksw.com/dataspace/doc/dav/wiki/Main/VirtRDFDumpNQuad

## Loading quads in Virtuoso
### Manually
Make the quad `.nq` files available in `/my/path/to/the/virtuoso/db/dumps`. The quad files might be compressed. Enter the Virtuoso docker, open ISQL, register and run the load.

    docker exec -it my-virtuoso bash
    isql-v -U dba -P $DBA_PASSWORD
    SQL> ld_dir('dumps', '*.nq', 'http://foo.bar');
    SQL> rdf_loader_run();
    SQL> checkpoint;
    SQL> checkpoint_interval(N);
    SQL> scheduler_interval(M);

> Note: **N** and **M** should be fetched from your virtuoso.ini config by looking for **CheckpointInterval** and **SchedulerInterval** respectively.

Validate the `ll_state` of the load. If `ll_state` is 2, the load completed.

    select * from DB.DBA.load_list;

For more information, see http://virtuoso.openlinksw.com/dataspace/doc/dav/wiki/Main/VirtBulkRDFLoader

### Automatically
By default, any data that is put in the `toLoad` directory in the Virtuoso database folder (`/my/path/to/the/virtuoso/db/toLoad`) is automatically loaded into Virtuoso on the first startup of the Docker container. The default graph is set by the `DEFAULT_GRAPH` environment variable, which defaults to `http://localhost:8890/DAV`.

## Creating a backup
A virtuoso backup can be created by executing the appropriate commands via the ISQL interface.

```
docker exec -i virtuoso_container mkdir -p backups
docker exec -i virtuoso_container isql-v <<EOF
    exec('checkpoint');
    backup_context_clear();
    backup_online('backup_',30000,0,vector('backups'));
    exit;
```
## Restoring a backup
To restore a backup, stop the running container and restore the database using a new container.

```
docker run --rm -it -v path-to-your-database:/data redpencil/virtuoso virtuoso-t +restore-backup backups/backup_ +configfile /data/virtuoso.ini
```

The new container will exit once the backup has been restored, you can then restart the original db container.

It is also possible to restore a backup placed in /data/backups using a environment variable. Using this approach the backup is loaded automatically on startup and it is not required to run a separate container.

```
docker run --name my-virtuoso \
            -p 8890:8890 \
            -p 1111:1111 \
            -e DBA_PASSWORD=dba \
            -e SPARQL_UPDATE=true \
            -e BACKUP_PREFIX=backup_ \_
            -v path-to-your-database:/data \
            -d redpencil/virtuoso
```

## Contributing

Contributions to this repository are welcome, please create a pull request on the master branch.

New features will be tested on redpencil/virtuoso:latest first. Once the image is verified, version branches will be rebased on master.
